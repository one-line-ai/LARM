import Testing
import Foundation
@testable import LARMCore

@Suite struct MonitoringTests {
    @Test func fsEventsDeliversChangeAndPollerDetectsRootFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("larm-fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let got = Box()
        let w = FSEventsWatcher(paths: [dir.appendingPathComponent(".claude").path], latency: 0.2) { sig in
            if case .changed(let p) = sig { got.append(p) }
        }
        #expect(w.start())
        try await Task.sleep(nanoseconds: 300_000_000)
        var waited = 0
        while !got.paths.contains(where: { $0.hasSuffix("settings.json") }) && waited < 100 {
            if waited % 10 == 0 { try "{\"n\":\(waited)}".write(to: dir.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8) }
            try await Task.sleep(nanoseconds: 100_000_000); waited += 1
        }
        #expect(got.paths.contains { $0.hasSuffix("settings.json") }, "paths=\(got.paths)")
        w.stop()
        #expect(!w.isRunning)

        let root = dir.appendingPathComponent(".mcp.json").path
        let poller = PathPoller(files: [root])
        #expect(poller.poll().isEmpty)
        try "{\"mcpServers\":{}}".write(toFile: root, atomically: true, encoding: .utf8)
        #expect(poller.poll() == [root])
        #expect(poller.poll().isEmpty)
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock(); private var _paths: [String] = []
        var paths: [String] { lock.lock(); defer { lock.unlock() }; return _paths }
        func append(_ p: [String]) { lock.lock(); _paths += p; lock.unlock() }
    }

    @Test func notificationDedupeAndQuietHours() throws {
        let db = try Fx.tempDB()
        let q = QuietHours(enabled: false, startHour: 22, endHour: 7)
        let req = NotificationPolicy.forNewHigh(ruleID: "R03", count: 1)
        #expect(try NotificationPolicy.decide(db, req, quiet: q) == .send)
        for _ in 0..<100 { #expect(try NotificationPolicy.decide(db, req, quiet: q) == .suppressedDuplicate) }
        let row = try db.query("SELECT suppressed_count, source_count FROM notification_log WHERE dedupe_key=?", [.text(req.dedupeKey)]).first!
        #expect(row["suppressed_count"]?.int == 100)
        #expect(row["source_count"]?.int == 101)
        #expect(try NotificationPolicy.decide(db, req, quiet: q, now: Date().addingTimeInterval(25 * 3600)) == .send)
        #expect(try NotificationPolicy.decide(db, NotificationPolicy.forGap(reason: "sleep", surface: "config_watch"), quiet: q) == .send)
        let quiet = QuietHours(enabled: true, startHour: 0, endHour: 24)
        let r2 = NotificationPolicy.forNewHigh(ruleID: "R01", count: 2)
        #expect(try NotificationPolicy.decide(db, r2, quiet: quiet) == .quietHours)
        #expect(try db.query("SELECT * FROM notification_log WHERE dedupe_key=?", [.text(r2.dedupeKey)]).count == 1)
        #expect(!req.body.contains("/") && !req.title.contains("/"))
        #expect(QuietHours(enabled: true, startHour: 22, endHour: 7).contains(Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!))
        #expect(!QuietHours(enabled: true, startHour: 22, endHour: 7).contains(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!))
    }

    @Test func pauseAndGaps() throws {
        let db = try Fx.tempDB()
        var p = PauseState(mode: .timed, until: Date().addingTimeInterval(60))
        #expect(p.isPaused)
        try p.save(db)
        #expect(PauseState.load(db).isPaused)
        p = PauseState(mode: .timed, until: Date().addingTimeInterval(-1))
        #expect(!p.isPaused && p.expired)
        #expect(PauseState(mode: .manual).isPaused)
        let id = try CoverageGapRepo.open(db, surface: "config_watch", reason: "paused")
        #expect(try CoverageGapRepo.open(db, surface: "config_watch", reason: "paused") == id)
        #expect(try CoverageGapRepo.openGaps(db).count == 1)
        try CoverageGapRepo.close(db, surface: "config_watch", reason: "paused", evidence: "resume+reconcile")
        #expect(try CoverageGapRepo.openGaps(db).isEmpty)
        #expect(try CoverageGapRepo.recent(db).first?.recoveryEvidence == "resume+reconcile")
    }
}
