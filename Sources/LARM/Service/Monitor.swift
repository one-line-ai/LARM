import Foundation
import AppKit
import LARMCore

/// 상주 감시 오케스트레이터.
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var health = HealthSnapshot()
    @Published private(set) var pause = PauseState()
    @Published private(set) var openGaps: [CoverageGap] = []
    @Published private(set) var recentGaps: [CoverageGap] = []
    @Published private(set) var watchedDirs: [String] = []
    @Published private(set) var polledFiles: [String] = []
    @Published private(set) var nextReconcileAt: Date?
    @Published private(set) var reconcileBasis = ""
    var decision: DecisionLayer = HeuristicDecisionLayer()
    var decisionInput: () -> DecisionInput = { DecisionInput() }

    private let db: SQLiteDB
    private let trigger: (String, Set<String>?) -> Void     // (kind, scopeIDs)
    private let onGapChange: (NotificationRequest) -> Void
    private let onHookData: (Data) -> Void
    private var socket: HookSocketServer?
    @Published private(set) var hookInstalled = false
    @Published private(set) var activityVerifiedAt: Date?
    @Published private(set) var lastEventAt: Date?
    var expectingTestEvent = false
    private var watchers: [String: FSEventsWatcher] = [:]      // scopeID → watcher
    private var poller = PathPoller(files: [])
    private var fileScope: [String: String] = [:]              // file → scopeID
    private var dirScope: [String: String] = [:]
    private var healthTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?
    private var reconcileTimer: DispatchSourceTimer?
    private var debounce: DispatchWorkItem?
    private var pendingScopes = Set<String>()
    private var failedDirs: [String] = []
    private var observers: [NSObjectProtocol] = []
    private(set) var running = false
    private var lastSocketRetry = Date.distantPast

    static let healthInterval: TimeInterval = 10
    static let pollInterval: TimeInterval = 60
    static let reconcileInterval: TimeInterval = 30 * 60
    static let debounceInterval: TimeInterval = 2

    init(db: SQLiteDB, trigger: @escaping (String, Set<String>?) -> Void, onGapChange: @escaping (NotificationRequest) -> Void, onHookData: @escaping (Data) -> Void) {
        self.db = db; self.trigger = trigger; self.onGapChange = onGapChange; self.onHookData = onHookData
    }


    static var claudeSettingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }

    func refreshHookInstalled() {
        let text = (try? String(contentsOfFile: Self.claudeSettingsPath, encoding: .utf8)) ?? ""
        hookInstalled = HookInstaller.isInstalled(settingsText: text)
    }

    private func startSocket() {
        socket?.stop()
        let srv = HookSocketServer(path: Paths.socketURL.path) { [weak self] data in Task { @MainActor in self?.receivedHook(data) } }
        if srv.start() { socket = srv; try? CoverageGapRepo.close(db, surface: "activity", reason: "socket_down", evidence: "연결 통로 재시작") }
        else { socket = nil; _ = try? CoverageGapRepo.open(db, surface: "activity", reason: "socket_down") }
    }

    private func receivedHook(_ data: Data) {
        lastEventAt = Date()
        if String(decoding: data, as: UTF8.self).contains("\"phase\":\"test\"") {
            expectingTestEvent = false
            activityVerifiedAt = Date()
            try? Settings.set(db, "activity_verified_at", Clock.utc(Date()))
        }
        onHookData(data)
    }

    /// 시험 활동 기록: 번들 안의 larm-hook을 --test로 실행한다 (제품이 서명한 어댑터만 실행, N01).
    func sendTestEvent() -> String {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("larm-hook"), FileManager.default.fileExists(atPath: url.path) else {
            return "번들 안에 larm-hook이 없음 (swift run 환경). 설치된 앱에서 시험하기"
        }
        expectingTestEvent = true
        let p = Process(); p.executableURL = url; p.arguments = ["--test"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run(); p.waitUntilExit() } catch { expectingTestEvent = false; return "연결 확인 신호 실행 실패: \(error.localizedDescription)" }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "연결 확인 신호를 보냈음. 수신 확인을 기다림" : out
    }


    func start(scopes: [Scope]) {
        guard !running else { rebuild(scopes: scopes); return }
        running = true
        recordNotRunningGap()
        pause = PauseState.load(db)
        rebuild(scopes: scopes)
        startSocket()
        refreshHookInstalled()
        activityVerifiedAt = Settings.get(db, "activity_verified_at").flatMap { Clock.parse($0) }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.enterGap("sleep") } })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.recover(from: "sleep") } })
        observers.append(nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.enterGap("session_inactive") } })
        observers.append(nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.recover(from: "session_inactive") } })
        healthTimer = timer(Self.healthInterval) { [weak self] in self?.healthCheck() }
        pollTimer = timer(Self.pollInterval) { [weak self] in self?.pollFiles() }
        scheduleReconcile()
        if pause.isPaused { enterGap("paused") } else { reconcile(reason: "시작 대조") }
        healthCheck()
    }

    func stop() {
        socket?.stop(); socket = nil
        for w in watchers.values { w.stop() }
        watchers = [:]
        healthTimer?.cancel(); pollTimer?.cancel(); reconcileTimer?.cancel()
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers = []
        running = false
    }

    /// G1 검사 게임: 변경 확률 추정으로 다음 대조 간격을 정하고 무작위 곱을 섞는다.
    func scheduleReconcile() {
        reconcileTimer?.cancel()
        let est = decision.estimate(.changeSoon, subject: "reconcile", input: decisionInput(), context: [:])
        let interval = InspectionPolicy.nextInterval(changeSoon: est.p)
        nextReconcileAt = Date().addingTimeInterval(interval)
        reconcileBasis = "변경 확률 \(Int(est.p * 100))% (\(est.basis)) → \(Int(interval / 60))분 뒤"
        try? EstimateRepo.record(db, est)
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.reconcile(reason: "주기 대조"); self?.scheduleReconcile() }
        t.resume()
        reconcileTimer = t
    }

    private func timer(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        t.setEventHandler { body() }
        t.resume()
        return t
    }

    /// 범위 변경 시 감시 대상 재구성.
    func rebuild(scopes: [Scope]) {
        for w in watchers.values { w.stop() }
        watchers = [:]; dirScope = [:]; fileScope = [:]; failedDirs = []
        var files: [String] = []
        let home = NSHomeDirectory()
        for s in scopes where !s.excluded {
            var dirs: [String] = []
            for a: Adapter in [ClaudeCodeAdapter(), CodexAdapter(), CursorAdapter()] {
                let t = a.watchTargets(scope: s, home: home)
                dirs += t.dirs; files += t.files
                for f in t.files { fileScope[f] = s.scopeID }
            }
            let existing = dirs.filter { FileManager.default.fileExists(atPath: $0) }
            for d in existing { dirScope[d] = s.scopeID }
            guard !existing.isEmpty else { continue }
            let sid = s.scopeID
            let w = FSEventsWatcher(paths: existing, latency: 1.0) { [weak self] sig in
                Task { @MainActor in self?.handle(sig, scopeID: sid) }
            }
            if pause.isPaused || w.start() { watchers[sid] = w } else { failedDirs += existing }
        }
        poller.reset(files: files)
        watchedDirs = dirScope.keys.sorted().map { Self.alias($0) }
        polledFiles = files.sorted().map { Self.alias($0) }
        if !failedDirs.isEmpty {
            _ = try? CoverageGapRepo.open(db, surface: "config_watch", reason: "watch_failed")
            onGapChange(NotificationPolicy.forGap(reason: "watch_failed", surface: "config_watch"))
        }
        refreshGaps()
    }

    static func alias(_ p: String) -> String { let h = NSHomeDirectory(); return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p }


    private func handle(_ sig: FSEventsWatcher.Signal, scopeID: String) {
        guard !pause.isPaused else { return }
        switch sig {
        case .overflow(let reason):
            _ = try? CoverageGapRepo.open(db, surface: "config_watch", reason: "fs_overflow")
            health.detail = "파일 활동 기록 유실(\(reason)) → 현재 상태 대조로 복구"
            reconcile(reason: "활동 기록 유실 복구")
        case .changed(let paths):
            let interesting = paths.filter { p in
                let n = (p as NSString).lastPathComponent
                return n.hasSuffix(".json") || n.hasSuffix(".toml") || n.hasSuffix(".md") || p.contains("/.claude/skills") || p.contains("/.claude/agents") || p.contains("/.claude/commands") || p.contains("/.claude/hooks")
            }
            guard !interesting.isEmpty else { return }
            pendingScopes.insert(scopeID)
            scheduleRescan()
        }
    }

    private func pollFiles() {
        guard !pause.isPaused else { return }
        let changed = poller.poll()
        guard !changed.isEmpty else { return }
        for f in changed { if let s = fileScope[f] { pendingScopes.insert(s) } }
        scheduleRescan()
    }

    private func scheduleRescan() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.pendingScopes.isEmpty else { return }
            let ids = self.pendingScopes; self.pendingScopes = []
            self.trigger("event", ids)
        }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: w)
    }

    func reconcile(reason: String) {
        guard !pause.isPaused else { return }
        health.lastReconcileAt = Date()
        health.detail = reason
        trigger("reconcile", nil)
    }


    private func enterGap(_ reason: String) {
        _ = try? CoverageGapRepo.open(db, surface: "config_watch", reason: reason)
        refreshGaps()
        if reason != "sleep" && reason != "session_inactive" { onGapChange(NotificationPolicy.forGap(reason: reason, surface: "config_watch")) }
        healthCheck()
    }

    private func recover(from reason: String) {
        guard !pause.isPaused else { return }
        try? CoverageGapRepo.close(db, surface: "config_watch", reason: reason, evidence: "복귀 후 현재 상태 대조 (확인 못 한 구간 중 변경은 확인 안 됨)")
        refreshGaps()
        reconcile(reason: "\(reason) 복귀 대조")
        healthCheck()
    }

    private func recordNotRunningGap() {
        if let last = Settings.get(db, "last_alive_at"), let d = Clock.parse(last), Date().timeIntervalSince(d) > 30 {
            _ = try? CoverageGapRepo.open(db, surface: "config_watch", reason: "not_running", startedAt: last)
            try? CoverageGapRepo.close(db, surface: "config_watch", reason: "not_running", evidence: "앱 시작 후 대조")
        }
    }

    func refreshGaps() {
        openGaps = (try? CoverageGapRepo.openGaps(db)) ?? []
        recentGaps = (try? CoverageGapRepo.recent(db, limit: 30)) ?? []
    }


    func healthCheck() {
        let now = Date()
        try? Settings.set(db, "last_alive_at", Clock.utc(now))
        if pause.expired { resume(auto: true) }
        var cw: SurfaceStatus
        if pause.isPaused { cw = .paused }
        else if !failedDirs.isEmpty && watchers.isEmpty { cw = .failed }
        else if !failedDirs.isEmpty || openGaps.contains(where: { $0.reason == "fs_overflow" || $0.reason == "watch_failed" }) { cw = .partial }
        else if !watchers.values.allSatisfy({ $0.isRunning }) { cw = .failed }
        else { cw = .watching }
        let spoolOK = FileManager.default.isWritableFile(atPath: Paths.spoolDir.path)
        if !spoolOK && cw == .watching { cw = .partial }
        health.configWatch = cw
        if !hookInstalled { health.activity = .notConnected }
        else if socket?.isListening != true { health.activity = .failed; _ = try? CoverageGapRepo.open(db, surface: "activity", reason: "socket_down"); if now.timeIntervalSince(lastSocketRetry) > 30 { lastSocketRetry = now; startSocket() } }
        else if pause.isPaused { health.activity = .paused }
        else { health.activity = .watching }
        health.lastCheckAt = now
        if cw == .watching || cw == .partial { health.lastOKAt = now }
        if cw == .failed {
            _ = try? CoverageGapRepo.open(db, surface: "config_watch", reason: "watch_failed")
        } else if cw == .watching {
            try? CoverageGapRepo.close(db, surface: "config_watch", reason: "watch_failed", evidence: "감시 다시 시작 확인")
        }
        refreshGaps()
    }


    func pauseWatching(minutes: Int?) {
        pause = minutes.map { PauseState(mode: .timed, until: Date().addingTimeInterval(Double($0) * 60)) } ?? PauseState(mode: .manual)
        try? pause.save(db)
        for w in watchers.values { w.stop() }
        debounce?.cancel(); pendingScopes = []
        enterGap("paused")
        try? Audit.record(db, kind: "watch_paused", detail: ["mode": pause.mode.rawValue, "until": pause.until.map { Clock.utc($0) } ?? ""])
    }

    func resume(auto: Bool = false) {
        pause = PauseState()
        try? pause.save(db)
        var failed = false
        for w in watchers.values where !w.isRunning { if !w.start() { failed = true } }
        if failed { failedDirs = ["(재시작 실패)"] } else { failedDirs = [] }
        try? CoverageGapRepo.close(db, surface: "config_watch", reason: "paused", evidence: auto ? "기한 만료 → 동작 확인, 대조" : "사용자 다시 시작 → 동작 확인, 대조")
        try? Audit.record(db, kind: "watch_resumed", detail: ["auto": auto ? "true" : "false"])
        refreshGaps()
        healthCheck()
        if health.configWatch != .failed { reconcile(reason: auto ? "잠시 멈춤 만료 대조" : "다시 시작 대조") }
        else { health.detail = "다시 시작 실패: 감시 장애 상태를 유지함 (확인 못 한 구간 유지)" }
    }
}
