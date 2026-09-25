import Foundation
import Combine
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LARMCore

@MainActor
final class AppState: ObservableObject {
    enum Boot: Equatable { case starting, ready, failed(String) }
    enum Section: String, CaseIterable, Identifiable {
        case graph, overview, findings, changes, coverage, activity, games, evidence
        var id: String { rawValue }
        var title: String {
            switch self { case .overview: return "개요"; case .findings: return "발견 사항"; case .activity: return "AI 도구 활동"; case .games: return "사용자와 AI 도구"; case .changes: return "바뀐 설정"; case .coverage: return "점검한 파일"
            case .graph: return "한눈에 보기"; case .evidence: return "보고서와 설정" }
        }
        var symbol: String {
            switch self { case .overview: return "gauge"; case .findings: return "exclamationmark.triangle"; case .activity: return "waveform.path.ecg"; case .games: return "person.2"; case .changes: return "arrow.left.arrow.right"; case .coverage: return "checklist"
            case .graph: return "sparkles.rectangle.stack"; case .evidence: return "doc.badge.gearshape" }
        }
    }

    @Published var boot: Boot = .starting
    @Published var installation: Installation?
    @Published var section: Section = .graph
    @Published var scopes: [Scope] = []
    @Published var findings: [Finding] = []
    @Published var lastScan: ScanSummary?
    @Published var lastCoverage: [Coverage] = []
    @Published var scanning = false
    @Published var scanError: String?
    @Published var selectedFindingID: String?
    @Published var rulesVersion: String = "-"
    @Published var rulesError: String?
    @Published var installStatus: [String: (status: String, version: String, support: String)] = [:]
    @Published var baseline: Decision?
    @Published var baselineSummary: ScanSummary?
    @Published var diff: [DiffEntry] = []
    @Published var decisions: [Decision] = []
    @Published var retentionDays: Int = 30
    @Published var lastExportMessage: String?
    @Published var verifyMessage: String?
    @Published var autoStartStatus: String = LoginItem.statusLabel
    @Published var notificationsEnabled = false
    @Published var notifierReason = ""
    @Published var quietHours = QuietHours(enabled: false, startHour: 22, endHour: 7)
    @Published var lastSkippedReconcileAt: String?
    private var keyID: String = ""
    private(set) var monitor: Monitor?
    let notifier = Notifier()
    private var pendingRescan: (String, Set<String>?)?
    @Published var alertResponseRate: Double? = nil
    @Published var alertSamples = 0
    @Published var lastGateNote = ""
    let decision: DecisionLayer = HeuristicDecisionLayer()
    @Published var events: [RuntimeEvent] = []
    @Published var hookPlan: HookInstaller.Plan?
    @Published var hookPlanIsRemoval = false
    @Published var hookMessage: String?
    @Published var eventRetentionDays: Int = 7
    private var activityRules: ActivityRuleSet?

    private(set) var db: SQLiteDB?
    private var redactor: Redactor?
    private var rules: RuleSet?
    private var cancelFlag = CancelFlag()

    final class CancelFlag: @unchecked Sendable { var cancelled = false }
    private var cancellables = Set<AnyCancellable>()

    var menuBarSymbol: String {
        switch boot {
        case .ready:
            if let m = monitor, m.health.overall == .paused { return "shield.slash" }
            if let m = monitor, m.health.overall == .failed || m.health.overall == .partial { return "shield.lefthalf.filled.badge.checkmark" }
            return openHighCount > 0 ? "shield.lefthalf.filled.trianglebadge.exclamationmark" : "shield.lefthalf.filled"
        case .starting: return "shield"
        case .failed: return "shield.slash"
        }
    }
    var openFindings: [Finding] { findings.filter { $0.state == .open || $0.state == .inProgress } }
    var openHighCount: Int { openFindings.filter { $0.severity == .high }.count }
    var gapCount: Int { lastCoverage.filter { $0.status != .success && $0.status != .absent }.count }
    var watchGapCount: Int { monitor?.openGaps.count ?? 0 }
    var healthLabel: String {
        guard let m = monitor else { return "준비 중" }
        return m.health.overall.label
    }

    init() {
        if let s = ProcessInfo.processInfo.environment["LARM_SECTION"].flatMap({ Section(rawValue: $0) }) { section = s }
        Task { await start() }
    }

    func start() async {
        do {
            try Paths.ensureDirs()
            let db = try SQLiteDB(url: Paths.dbURL)
            try Schema.migrate(db)
            self.db = db
            let material: KeychainKey.Material
            do { material = try KeychainKey.loadOrCreate() } catch {
                boot = .failed("설치 키를 Keychain에서 준비하지 못했음. 약한 임시 키로 대체하지 않음 \(error)")
                return
            }
            redactor = Redactor(hmacKey: material.key)
            keyID = material.keyID
            installation = try InstallationStore.loadOrCreate(db: db, keyID: material.keyID, appVersion: AppInfo.version, osBuild: AppInfo.osBuild)
            _ = try Retention.apply(db)
            _ = try DecisionRepo.reviewExceptions(db)
            do {
                let bundled = try RuleLoader.loadBundled()
                let (installed, note) = RuleUpdate.loadCurrent(dir: Paths.supportDir.appendingPathComponent("rules", isDirectory: true))
                if let installed, RuleUpdate.isNewer(installed.version, than: bundled.version) { rules = installed } else { rules = bundled }
                rulesVersion = rules!.version
                if installed == nil, note.contains("손상") { rulesError = "\(note). 마지막 검증 버전(번들 \(bundled.version))을 사용함" }
            } catch {
                rulesError = "점검 규칙 로딩 실패: \(error). 점검 불가 상태임. 무탐지로 종료하지 않음"
            }
            try ScopeRepo.ensureUserRoot(db)
            try reload()
            refreshInstallStatus()
            notificationsEnabled = Settings.get(db, "notifications_enabled") == "true"
            quietHours = QuietHours(enabled: Settings.get(db, "quiet_enabled") == "true", startHour: Int(Settings.get(db, "quiet_start") ?? "") ?? 22, endHour: Int(Settings.get(db, "quiet_end") ?? "") ?? 7)
            await notifier.refreshAuthorization()
            notifierReason = notifier.reason
            activityRules = try? ActivityRules.loadBundled()
            eventRetentionDays = Int(Settings.get(db, "event_retention_days") ?? "") ?? 7
            _ = try? EventIngest.purge(db, olderThanDays: eventRetentionDays)
            let drained = EventIngest.drainSpool(db, dir: Paths.spoolDir, scopes: scopes, rules: activityRules)
            if drained.0 + drained.1 > 0 {
                try? CoverageGapRepo.close(db, surface: "activity", reason: "not_running", evidence: "spool \(drained.0)건 수집, 실패 \(drained.1)건", lostCount: drained.1)
            }
            events = (try? EventIngest.list(db)) ?? []
            let m = Monitor(db: db, trigger: { [weak self] kind, ids in self?.runScan(kind: kind, onlyScopeIDs: ids) },
                            onGapChange: { [weak self] req in self?.notify(req) },
                            onHookData: { [weak self] data in self?.ingestHook(data) })
            m.decisionInput = { [weak self] in self?.decisionInput() ?? DecisionInput() }
            monitor = m
            loadAlertStats()
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == AppInfo.bundleID { Task { @MainActor in self?.markAlertResponses() } }
            }
            m.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
            boot = .ready
            m.start(scopes: scopes)
            if Settings.get(db, "autostart_enabled") == "true", LoginItem.status != "enabled" { _ = LoginItem.setEnabled(true) }
            autoStartStatus = LoginItem.statusLabel
        } catch {
            boot = .failed("\(error)")
        }
    }

    func reload() throws {
        guard let db else { return }
        scopes = try ScopeRepo.all(db)
        findings = try FindingRepo.list(db)
        lastScan = try ScanRepo.latest(db)
        if let s = try ScanRepo.latestCompletedOrPartial(db) { lastCoverage = try ScanRepo.coverage(db, scanID: s.scanID) }
        baseline = try DecisionRepo.currentBaseline(db)
        baselineSummary = try baseline?.scanID.flatMap { try ScanRepo.get(db, scanID: $0) }
        decisions = try DecisionRepo.all(db)
        retentionDays = Settings.retentionDays(db)
        diff = try computeDiff()
        rebuildGalaxy()
        rebuildGames()
    }

    /// 갤럭시 지도용 그래프 JSON (마지막 점검 기준). 점검이 바뀔 때만 다시 만든다.
    @Published var galaxyJSON: String?
    func rebuildGalaxy() {
        guard let db, let s = try? ScanRepo.latestCompletedOrPartial(db), let obs = try? ScanRepo.observations(db, scanID: s.scanID) else { galaxyJSON = nil; return }
        let g = GraphBuilder().build(observations: obs, findings: findings, scopes: scopes, scanID: s.scanID)
        galaxyJSON = try? GraphExport.json(g, scopes: scopes, findings: findings)
        larmHookNodeIDs = g.nodes.filter { $0.type == .hook && $0.attrs["owner"] == "larm" }.map(\.id)
        refreshActive()
    }

    /// 최근 15분 안에 활동이 기록된 별: AI 도구, 활동이 있었던 프로젝트, LARM 연결(hook).
    @Published var activeNodeIDs: [String] = []
    private var larmHookNodeIDs: [String] = []
    func refreshActive() {
        let cutoff = Date().addingTimeInterval(-15 * 60)
        let recent = events.filter { Clock.parse($0.receivedAt).map { $0 > cutoff } ?? false }
        var ids = Set<String>()
        if !recent.isEmpty { ids.insert("agent:claude-code"); ids.formUnion(larmHookNodeIDs) }
        for e in recent { if let s = e.scopeID { ids.insert(s == "scope_user" ? "device:local" : "project:\(s)") } }
        let sorted = ids.sorted()
        if sorted != activeNodeIDs { activeNodeIDs = sorted }
    }
    var moodMessage: String {
        switch mood {
        case .paused: return "쉬는 중: 감시를 잠시 멈춘 상태. 메뉴바에서 다시 시작 가능"
        case .risk: return "확인 필요: 높은 위험 \(openHighCount)건이 아직 조치되지 않음. '발견 사항'에서 확인"
        case .empty: return "기록 없음: 아직 점검하지 않았음. 오른쪽 위 '점검'으로 시작"
        case .clear: return "이상 없음: 발견된 위험이 없고 감시가 켜져 있음"
        case .watching: return "지켜보는 중: 중간 위험 \(openFindings.count)건을 두고 설정 변화를 감시함"
        }
    }

    func computeDiff() throws -> [DiffEntry] {
        guard let db, let b = baseline?.scanID, let cur = try ScanRepo.latestCompletedOrPartial(db), cur.scanID != b else { return [] }
        let from = try ScanRepo.observations(db, scanID: b), to = try ScanRepo.observations(db, scanID: cur.scanID)
        return Differ.diff(from: from, fromCoverage: try ScanRepo.coverage(db, scanID: b), to: to, toCoverage: try ScanRepo.coverage(db, scanID: cur.scanID),
                           fromScopes: try ScanRepo.scopeIDs(db, scanID: b), toScopes: try ScanRepo.scopeIDs(db, scanID: cur.scanID))
    }

    func refreshInstallStatus() {
        let home = NSHomeDirectory()
        var m: [String: (String, String, String)] = [:]
        for a: Adapter in [ClaudeCodeAdapter(), CodexAdapter(), CursorAdapter()] {
            let i = a.detectInstall(home: home)
            m[a.id] = (i.status.rawValue, i.version ?? "불명", i.supportLevel)
        }
        installStatus = m
    }


    func runScan(kind: String = "full", onlyScopeIDs: Set<String>? = nil) {
        guard let db, let redactor, let rules else {
            if rules == nil { scanError = rulesError ?? "룰이 없어 점검할 수 없음" }
            return
        }
        if scanning {
            let merged: Set<String>? = (pendingRescan?.1 == nil || onlyScopeIDs == nil) ? nil : pendingRescan!.1!.union(onlyScopeIDs!)
            pendingRescan = (kind == "full" || pendingRescan?.0 == "full" ? "full" : kind, merged)
            return
        }
        scanning = true; scanError = nil
        let flag = CancelFlag(); cancelFlag = flag
        var target = scopes.filter { !$0.excluded }
        if let only = onlyScopeIDs { target = target.filter { only.contains($0.scopeID) || $0.kind == .userRoot } }
        let scanner = Scanner(rules: rules, redactor: redactor)
        let scopesSnapshot = target
        let ctx = Scanner.Context(baselineObservations: try? baseline?.scanID.flatMap { try ScanRepo.observations(db, scanID: $0) },
                                  reviewedEndpoints: (try? DecisionRepo.reviewedEndpoints(db)) ?? [])
        let keyID = self.keyID
        Task.detached(priority: .userInitiated) {
            let result = scanner.run(scopes: scopesSnapshot, context: ctx, isCancelled: { flag.cancelled })
            await MainActor.run { [weak self] in
                guard let self else { return }
                do {
                    let beforeHigh = Set(self.findings.filter { $0.severity == .high && $0.state == .open }.map { $0.findingID })
                    var stored = true
                    if (kind == "event" || kind == "reconcile"), onlyScopeIDs == nil || kind == "reconcile", result.status == .complete,
                       let last = try ScanRepo.latestCompletedOrPartial(db), let snap = try ScanRepo.snapshotDigest(db, scanID: last.scanID),
                       snap.content == Digest.content(result.observations, scopes: result.scopes, adapterVersions: result.adapterVersions),
                       snap.secret == Digest.secrets(result.observations) {
                        stored = false
                        self.lastSkippedReconcileAt = Clock.nowUTC()
                        try? Settings.set(db, "last_reconcile_unchanged_at", Clock.nowUTC())
                    }
                    if stored {
                        _ = try ScanRepo.store(db, result: result, kind: kind, keyID: keyID)
                        try self.reload()
                        if result.status == .partial { self.scanError = "일부 항목을 확인하지 못했음. 'coverage'에서 사유를 확인하기" }
                        if result.status == .cancelled { self.scanError = "점검을 취소했음. 이전 성공 결과를 유지함" }
                        let newHigh = self.findings.filter { $0.severity == .high && $0.state == .open && !beforeHigh.contains($0.findingID) }
                        for (rule, items) in Dictionary(grouping: newHigh, by: { $0.ruleID }) { self.notify(NotificationPolicy.forNewHigh(ruleID: rule, count: items.count)) }
                    }
                } catch {
                    self.scanError = "결과 저장 실패: \(Redactor.scrub("\(error)"))"
                }
                self.scanning = false
                if let p = self.pendingRescan { self.pendingRescan = nil; self.runScan(kind: p.0, onlyScopeIDs: p.1) }
            }
        }
    }

    func cancelScan() { cancelFlag.cancelled = true }


    func addProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = "프로젝트 추가"
        panel.message = "점검할 프로젝트 폴더를 선택하기. 폴더 선택은 코드 실행이나 전체 수집 동의가 아님. 지원 설정 파일만 읽음."
        guard panel.runModal() == .OK, let db else { return }
        do {
            for u in panel.urls { _ = try ScopeRepo.addProject(db, path: u.path) }
            try reload(); monitor?.rebuild(scopes: scopes)
        } catch { scanError = "프로젝트 추가 실패: \(error)" }
    }

    func removeScope(_ s: Scope) {
        guard let db, s.kind == .project else { return }
        do { try ScopeRepo.remove(db, scopeID: s.scopeID); try reload(); monitor?.rebuild(scopes: scopes) } catch { scanError = "\(error)" }
    }

    func toggleExcluded(_ s: Scope) {
        guard let db else { return }
        do { try ScopeRepo.setExcluded(db, scopeID: s.scopeID, !s.excluded); try reload(); monitor?.rebuild(scopes: scopes) } catch { scanError = "\(error)" }
    }


    func transition(_ f: Finding, to: FindingState, note: String) {
        guard let db else { return }
        do { try FindingRepo.userTransition(db, findingID: f.findingID, to: to, note: note); try reload() } catch { scanError = "\(error)" }
    }

    func observations(for f: Finding) -> [Observation] {
        guard let db else { return [] }
        return (try? ScanRepo.observations(db, scanID: f.lastScanID, objectID: f.objectID)) ?? []
    }

    func events(for f: Finding) -> [(at: String, kind: String, from: String?, to: String?, actor: String, note: String)] {
        guard let db else { return [] }
        return (try? FindingRepo.events(db, findingID: f.findingID)) ?? []
    }

    func guidance(for ruleID: String) -> String {
        (try? ResourceLocator.data("guidance/ko/\(ruleID).md")).map { String(decoding: $0, as: UTF8.self) } ?? "안내 문서를 찾을 수 없음"
    }

    func scopeAlias(_ id: String) -> String { scopes.first { $0.scopeID == id }?.alias ?? id }


    func setBaseline(reason: String) -> String? {
        guard let db, let s = lastScan else { return "점검 기록이 없음" }
        do { try DecisionRepo.setBaseline(db, scanID: s.scanID, reason: reason); try reload(); return nil } catch { return "\(error)" }
    }

    func addException(_ f: Finding, days: Int, reason: String) -> String? {
        guard let db else { return nil }
        let obs = observations(for: f)
        let digest = FindingRepo.evidenceDigest(f.evidence, Dictionary(obs.map { ($0.observationID, $0) }, uniquingKeysWith: { a, _ in a }))
        do { try DecisionRepo.addException(db, finding: f, days: days, reason: reason, evidenceDigest: digest); try reload(); return nil } catch { return "\(error)" }
    }

    func exception(for f: Finding) -> Decision? { guard let db else { return nil }; return try? DecisionRepo.activeException(db, findingID: f.findingID) }

    func markEndpointReviewed(_ f: Finding, reason: String) -> String? {
        guard let db else { return nil }
        do { try DecisionRepo.markEndpointReviewed(db, objectID: f.objectID, reason: reason); try reload(); return nil } catch { return "\(error)" }
    }

    func setRetention(_ days: Int) {
        guard let db else { return }
        try? Settings.set(db, "retention_days", "\(days)"); retentionDays = days
        _ = try? Retention.apply(db); try? reload()
    }

    func purgeNow() -> String {
        guard let db else { return "" }
        let n = (try? Retention.apply(db)) ?? 0; try? reload()
        return "만료 점검 기록 \(n)건을 삭제했음. 기준 상태, 최신 점검, 내보낸 사본은 유지됨"
    }

    /// 전체 초기화: 기록·기준점·설치 키·임시 파일 삭제 후 종료.
    func fullReset() {
        let alert = NSAlert()
        alert.messageText = "전체 초기화"
        alert.informativeText = "점검 기록, 기준 상태, 예외, 설치 키(Keychain), 보관 중인 활동 기록를 삭제하고 앱을 종료함. 내보낸 보고서 파일은 그대로 남음. 디스크, 백업, 클라우드에 남은 사본까지 지워지지는 않음"
        alert.addButton(withTitle: "삭제하고 종료"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        db = nil
        try? FileManager.default.removeItem(at: Paths.supportDir)
        try? KeychainKey.delete()
        NSApp.terminate(nil)
    }


    /// G2 늑대소년 게임: 높은 위험·감시 장애는 항상 보내고, 나머지는 조치 필요 확률 × 반응 확률로 게이트한다.
    func notify(_ req: NotificationRequest) {
        guard let db else { return }
        if req.kind == .newGap || req.kind == .recovered {
            let a = decision.estimate(.actionNeeded, subject: req.dedupeKey, input: decisionInput(), context: ["severity": "medium", "seen": "1"])
            let b = decision.estimate(.willRespond, subject: req.dedupeKey, input: decisionInput(), context: [:])
            try? EstimateRepo.record(db, b)
            let g = AlertGate.shouldSend(actionNeeded: a.p, willRespond: b.p, weight: 1.0)
            lastGateNote = "\(req.kind == .newGap ? "감시 공백" : "복구") 알림: 가치 \(String(format: "%.2f", g.value)) → \(g.send ? "전송" : "배지만") · 반응 확률 \(Int(b.p * 100))% (\(b.basis))"
            if !g.send { return }
        }
        let d = notifier.send(req, db: db, quiet: quietHours, enabled: notificationsEnabled)
        if d == .send { try? Settings.set(db, "alert_last_sent", Clock.nowUTC()); try? Settings.set(db, "alert_pending", "1"); recordAlertSent() }
    }

    // MARK: 알림 반응 기록 (G2)
    func recordAlertSent() {
        guard let db else { return }
        var log = alertLog(); log.append([Clock.nowUTC(), "0"]); if log.count > 30 { log.removeFirst(log.count - 30) }
        saveAlertLog(log)
        _ = db
    }
    func markAlertResponses() {
        guard let db else { return }
        var log = alertLog(); var changed = false
        for i in log.indices where log[i][1] == "0" {
            if let t = Clock.parse(log[i][0]), Date().timeIntervalSince(t) < 86400 { log[i][1] = "1"; changed = true; try? EstimateRepo.outcome(db, question: .willRespond, subject: "*", value: 1) }
        }
        if changed { saveAlertLog(log) }
    }
    func alertLog() -> [[String]] {
        guard let db, let s = Settings.get(db, "alert_log"), let d = try? JSONDecoder().decode([[String]].self, from: Data(s.utf8)) else { return [] }
        return d
    }
    func saveAlertLog(_ log: [[String]]) {
        guard let db, let d = try? JSONEncoder().encode(log) else { return }
        try? Settings.set(db, "alert_log", String(decoding: d, as: UTF8.self)); loadAlertStats()
    }
    func loadAlertStats() {
        let log = alertLog().filter { Clock.parse($0[0]).map { Date().timeIntervalSince($0) < 30 * 86400 } ?? false }
        alertSamples = log.count
        alertResponseRate = log.isEmpty ? nil : Double(log.filter { $0[1] == "1" }.count) / Double(log.count)
    }
    func decisionInput() -> DecisionInput {
        var i = DecisionInput()
        i.openHigh = openHighCount
        i.recentEventCount15m = events.filter { Clock.parse($0.receivedAt).map { Date().timeIntervalSince($0) < 900 } ?? false }.count
        if let s = lastScan, s.kind == "event", let d = Clock.parse(s.endedAt) { i.lastChangeMinutesAgo = Date().timeIntervalSince(d) / 60 }
        i.responseRate30d = alertResponseRate; i.responseSamples = alertSamples
        i.quietHours = quietHours.contains(Date())
        return i
    }

    // MARK: 예외 연장 (G5)
    func exceptionRenewals(_ f: Finding) -> Int {
        guard let db, let n = try? db.scalar("SELECT COUNT(*) FROM decision WHERE kind='exception' AND finding_id=?", [.text(f.findingID)]).int else { return 0 }
        return Int(n)
    }

    // MARK: 게임 계산 (설계 10장)
    @Published var trustRecords: [PlayerGames.TrustRecord] = []
    @Published var sessionSignals: [PlayerGames.SessionSignal] = []
    var baselineSuggestion: String? {
        PlayerGames.baselineSuggestion(hasBaseline: baseline != nil, baselineAt: baseline?.createdAt, diffCount: diff.count, openHigh: openHighCount, lastScanAt: lastScan?.endedAt)
    }
    func rebuildGames() {
        sessionSignals = PlayerGames.sessionSignals(events: events)
        if let db { trustRecords = (try? PlayerGames.trust(db, findings: findings)) ?? [] }
    }
    func delegation(for f: Finding) -> PlayerGames.Delegation? {
        guard f.ruleID == "R02", let b = observations(for: f).first(where: { $0.field == "breadth" })?.safeValue else { return nil }
        return PlayerGames.delegation(breadth: b, scopeID: f.scopeID, events: events)
    }
    /// 게임 2: 세션을 살펴본 결과를 기록해 추정을 검증한다.
    func reviewSession(_ s: PlayerGames.SessionSignal, problem: Bool) {
        guard let db else { return }
        for e in events where e.sessionRef == s.sessionRef && e.riskRule != nil && e.ackState == "observed" {
            try? EventIngest.acknowledge(db, eventID: e.eventID, state: problem ? "acknowledged" : "false_positive_review")
        }
        try? EstimateRepo.record(db, Estimate(question: .evasion, subject: s.sessionRef, p: s.p, basis: s.basis, model: decision.model))
        try? EstimateRepo.outcome(db, question: .evasion, subject: s.sessionRef, value: problem ? 1 : 0)
        events = (try? EventIngest.list(db)) ?? []
        rebuildGames()
    }
    var calibration: [(String, String)] {
        guard let db else { return [] }
        return DecisionQuestion.allCases.map { q in
            let name = q == .actionNeeded ? "조치 필요" : q == .willRespond ? "알림 반응" : q == .changeSoon ? "60분 내 변경" : "세션 살펴볼 필요"
            if let b = try? EstimateRepo.brier(db, question: q) { return (q.rawValue, "\(name): 브라이어 \(String(format: "%.2f", b.score)) (표본 \(b.n)건)") }
            return (q.rawValue, "\(name): 표본 5건 미만, 검증 전")
        }
    }
    var mood: Mascot.Mood {
        if let m = monitor, m.pause.isPaused { return .paused }
        if openHighCount > 0 { return .risk }
        if lastScan == nil { return .empty }
        if openFindings.isEmpty { return .clear }
        return .watching
    }

    // MARK: 오늘 확인할 항목 (G6)
    var todayItems: [Finding] {
        openFindings.sorted { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            if (a.verifyStatus == "verified") != (b.verifyStatus == "verified") { return a.verifyStatus == "verified" }
            if a.seenCount != b.seenCount { return a.seenCount > b.seenCount }
            return a.openedAt < b.openedAt
        }
    }

    func setNotifications(_ on: Bool) {
        guard let db else { return }
        Task {
            if on { _ = await notifier.requestAuthorization() }
            notificationsEnabled = on
            try? Settings.set(db, "notifications_enabled", on ? "true" : "false")
            notifierReason = notifier.reason
        }
    }

    func setQuietHours(_ q: QuietHours) {
        guard let db else { return }
        quietHours = q
        try? Settings.set(db, "quiet_enabled", q.enabled ? "true" : "false")
        try? Settings.set(db, "quiet_start", "\(q.startHour)"); try? Settings.set(db, "quiet_end", "\(q.endHour)")
    }

    func setAutoStart(_ on: Bool) -> String? {
        guard let db else { return nil }
        let err = LoginItem.setEnabled(on)
        try? Settings.set(db, "autostart_enabled", on && err == nil ? "true" : "false")
        try? Audit.record(db, kind: "autostart", detail: ["enabled": on ? "true" : "false", "error": err ?? ""])
        autoStartStatus = LoginItem.statusLabel
        return err
    }

    var autoStartEnabled: Bool { LoginItem.status == "enabled" }


    func ingestHook(_ data: Data) {
        guard let db else { return }
        let r = EventIngest.ingest(db, raw: data, scopes: scopes, rules: activityRules, delivery: "socket")
        if case .stored(let id) = r, let e = try? EventIngest.list(db, limit: 1).first, e.eventID == id, e.riskSeverity == "high", let rule = e.riskRule {
            notify(NotificationPolicy.forNewHigh(ruleID: rule, count: 1))
        }
        events = (try? EventIngest.list(db)) ?? []
        refreshActive()
    }

    func prepareHookInstall(remove: Bool) {
        let text = (try? String(contentsOfFile: Monitor.claudeSettingsPath, encoding: .utf8)) ?? ""
        do {
            hookPlanIsRemoval = remove
            hookPlan = remove ? try HookInstaller.planRemove(settingsText: text)
                              : try HookInstaller.planInstall(settingsText: text, hookPath: "/Applications/LARM.app/Contents/MacOS/larm-hook")
            if hookPlan?.changed == false { hookMessage = remove ? "제거할 LARM hook 항목이 없음" : "이미 등록되어 있음."; hookPlan = nil }
        } catch { hookMessage = "설정 파일을 읽지 못했슴: \(error)"; hookPlan = nil }
    }

    func applyHookPlan() {
        guard let plan = hookPlan, let db else { return }
        do {
            let before = Hashing.sha256Hex(plan.before)
            try HookInstaller.apply(plan, to: Monitor.claudeSettingsPath)
            try Audit.record(db, kind: hookPlanIsRemoval ? "hook_removed" : "hook_installed", detail: ["settings_sha256_before": before, "settings_sha256_after": Hashing.sha256Hex(plan.after)])
            hookMessage = hookPlanIsRemoval ? "LARM hook 항목을 제거했음. 다른 hook과 설정은 그대로임" : "연결을 등록했음. 새 Claude Code 작업 세션부터 기록됨. '연결 확인 신호 보내기'로 연결을 확인하기"
            hookPlan = nil
            monitor?.refreshHookInstalled(); monitor?.healthCheck()
            runScan(kind: "rescan", onlyScopeIDs: [])
        } catch { hookMessage = "적용 실패: \(error.localizedDescription)" }
    }

    func sendTestEvent() { hookMessage = monitor?.sendTestEvent() }

    func acknowledge(_ e: RuntimeEvent, state: String) {
        guard let db else { return }
        try? EventIngest.acknowledge(db, eventID: e.eventID, state: state)
        events = (try? EventIngest.list(db)) ?? []
    }

    func setEventRetention(_ days: Int) {
        guard let db else { return }
        eventRetentionDays = days
        try? Settings.set(db, "event_retention_days", "\(days)")
        _ = try? EventIngest.purge(db, olderThanDays: days)
        events = (try? EventIngest.list(db)) ?? []
    }

    func linkedEvents(_ e: RuntimeEvent) -> [RuntimeEvent] { events.filter { $0.sourceEventID == e.sourceEventID }.sorted { $0.seq < $1.seq } }


    func exportInput() throws -> ExportInput? {
        guard let db, let s = try ScanRepo.latestCompletedOrPartial(db) else { return nil }
        let obs = try ScanRepo.observations(db, scanID: s.scanID)
        let cov = try ScanRepo.coverage(db, scanID: s.scanID)
        let ids = try ScanRepo.scopeIDs(db, scanID: s.scanID)
        let versions: [String: String] = ["app": AppInfo.version, "os": AppInfo.osBuild, "rules": rulesVersion,
                                          "adapter.claude-code": "1.0.0", "adapter.codex": "1.0.0", "adapter.cursor": "1.0.0"]
        return ExportInput(scanID: s.scanID, scanSummary: s, scopes: scopes.filter { ids.contains($0.scopeID) }, coverage: cov, observations: obs,
                           findings: findings, decisions: decisions, diff: diff, baselineScanID: baseline?.scanID, versions: versions,
                           filters: ["scan": "latest", "scopes": scopes.filter { ids.contains($0.scopeID) }.map { $0.alias }.joined(separator: ",")],
                           installationID: installation?.installationID ?? "", events: events, gaps: (try? CoverageGapRepo.recent(db, limit: 500)) ?? [])
    }

    func exportPreview() -> ExportPreview? { (try? exportInput())?.map { Exporter.preview($0) } ?? nil }

    func exportEvidence() {
        guard let db else { return }
        do {
            guard let input = try exportInput() else { lastExportMessage = "내보낼 점검 결과가 없음 먼저 점검하기"; return }
            let (zip, exportID, msha) = try Exporter.build(input)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "LARM-evidence-\(String(input.scanSummary.endedAt.prefix(10))).zip"
            panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try zip.write(to: url, options: .atomic)
            try db.run("INSERT INTO export VALUES(?,?,?,?,?,?,?,?)", [.text(exportID), .text(Clock.nowUTC()), .text("[\"\(input.scanID)\"]"), .text("{}"),
                                                                  .text(Exporter.schema), .text(msha), .int(Int64(Exporter.fileOrder.count + 1)), .text(url.lastPathComponent)])
            try Audit.record(db, kind: "export", detail: ["export_id": exportID, "manifest_sha256": msha])
            lastExportMessage = "내보냈슴: \(url.lastPathComponent)\nmanifest SHA-256: \(msha)\n이 해시를 별도 매체에 보관하면 manifest 재작성 위조를 검출할 수 있음."
        } catch { lastExportMessage = "내보내기 실패: \(Redactor.scrub("\(error)"))" }
    }

    /// 진단 파일 미리보기·저장.
    func diagnosticsText() -> String {
        guard let db else { return "" }
        return Diagnostics.build(db: db, appVersion: AppInfo.version, osBuild: AppInfo.osBuild, rulesVersion: rulesVersion,
                                 extra: ["last_error": scanError ?? "", "boot": "\(boot)", "watch": healthLabel, "autostart": autoStartStatus])
    }
    func saveDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "LARM-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? diagnosticsText().write(to: url, atomically: true, encoding: .utf8)
    }

    /// 서명된 룰 갱신 패키지 가져오기.
    @Published var ruleUpdateMessage: String?
    func importRuleUpdate() {
        guard let db else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do {
            let pkg = try RuleUpdate.parse(zip: data)
            let set = try RuleUpdate.validate(pkg, currentVersion: rulesVersion)
            let dir = Paths.supportDir.appendingPathComponent("rules", isDirectory: true)
            _ = try RuleUpdate.install(set, json: pkg.rulesJSON, into: dir)
            try Audit.record(db, kind: "rules_updated", detail: ["from": rulesVersion, "to": set.version])
            rules = set; rulesVersion = set.version
            ruleUpdateMessage = "점검 규칙 \(set.version)으로 전환했음. 기존 발견 사항은 이전 점검 규칙 버전을 유지하며 다음 점검부터 새 룰로 평가함"
        } catch { ruleUpdateMessage = "갱신 거부: \(error). 현재 점검 규칙 \(rulesVersion)을 유지함" }
    }
    func rollbackRules() {
        guard let db else { return }
        do {
            let dir = Paths.supportDir.appendingPathComponent("rules", isDirectory: true)
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("current.json"))
            let bundled = try RuleLoader.loadBundled()
            rules = bundled; rulesVersion = bundled.version
            try Audit.record(db, kind: "rules_rolled_back", detail: ["to": bundled.version])
            ruleUpdateMessage = "번들 점검 규칙 \(bundled.version)으로 되돌렸음."
        } catch { ruleUpdateMessage = "\(error)" }
    }

    func verifyEvidenceFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        verifyMessage = Verifier.render(Verifier.verify(zip: data))
    }
}

enum Fmt {
    static func local(_ iso: String) -> String {
        guard let d = Clock.parse(iso) else { return iso }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: d)
    }
    static func elapsed(_ iso: String) -> String {
        guard let d = Clock.parse(iso) else { return "" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "방금" }; if s < 3600 { return "\(s / 60)분 전" }; if s < 86400 { return "\(s / 3600)시간 전" }
        return "\(s / 86400)일 전"
    }
}
