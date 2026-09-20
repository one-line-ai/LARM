import Testing
import Foundation
@testable import LARMCore

@Suite struct LifecycleTests {
    @Test func rescanResolvesOnlyWhenReadable() throws {
        let db = try Fx.tempDB()
        let home = try Fx.copyToTemp("home-risky")
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        _ = try ScanRepo.store(db, result: scanner.run(scopes: scopes), kind: "full")
        let first = try FindingRepo.list(db)
        let codexR01 = first.first { $0.ruleID == "R01" && $0.objectID == "acfg:codex:scope_user" }!
        #expect(codexR01.state == .open)

        try FindingRepo.userTransition(db, findingID: codexR01.findingID, to: .inProgress, note: "고치는 중")
        #expect(try FindingRepo.get(db, findingID: codexR01.findingID)?.state == .inProgress)

        let cfg = home + "/.codex/config.toml"
        var text = try String(contentsOfFile: cfg, encoding: .utf8)
        text = text.replacingOccurrences(of: "approval_policy = \"never\"", with: "approval_policy = \"on-request\"")
            .replacingOccurrences(of: "sandbox_mode = \"danger-full-access\"", with: "sandbox_mode = \"workspace-write\"")
        try text.write(toFile: cfg, atomically: true, encoding: .utf8)
        _ = try ScanRepo.store(db, result: scanner.run(scopes: scopes), kind: "rescan")
        #expect(try FindingRepo.get(db, findingID: codexR01.findingID)?.state == .resolvedByRescan)
        let second = try FindingRepo.list(db)
        #expect(second.filter { $0.ruleID == "R01" && $0.objectID == "acfg:codex:scope_user" }.count == 1)

        let settings = home + "/.claude/settings.json"
        let claudeR01 = second.first { $0.ruleID == "R01" && $0.objectID == "acfg:claude-code:scope_user" }!
        #expect(claudeR01.state == .open)
        chmod(settings, 0o000)
        defer { chmod(settings, 0o644) }
        let r3 = scanner.run(scopes: scopes)
        #expect(r3.status == .partial)
        _ = try ScanRepo.store(db, result: r3, kind: "rescan")
        let after = try FindingRepo.get(db, findingID: claudeR01.findingID)!
        #expect(after.state == .open)
        #expect(after.verifyStatus == "unverifiable")
        #expect(try FindingRepo.list(db).contains { $0.ruleID == "R08" && $0.state == .open })
        chmod(settings, 0o644)
        let proj = try Fx.copyToTemp("project-risky")
        try ScopeRepo.ensureUserRoot(db)
        let ps = try ScopeRepo.addProject(db, path: proj)
        _ = try ScanRepo.store(db, result: scanner.run(scopes: scopes + [ps]), kind: "full")
        let pf = try FindingRepo.list(db).first { $0.scopeID == ps.scopeID && $0.ruleID == "R02" }!
        try ScopeRepo.remove(db, scopeID: ps.scopeID)
        _ = try ScanRepo.store(db, result: scanner.run(scopes: scopes), kind: "full")
        let after2 = try FindingRepo.get(db, findingID: pf.findingID)!
        #expect(after2.state == .open && after2.verifyStatus == "scope_removed")
    }
}
