import Testing
import Foundation
@testable import LARMCore

@Suite struct RulesGoldenTests {
    func positives(_ r: ScanResult) -> [Verdict] { r.verdicts.filter { $0.outcome == .positive } }
    func ids(_ r: ScanResult, _ rule: String) -> [String] { positives(r).filter { $0.ruleID == rule }.map { $0.objectID }.sorted() }

    @Test func riskyHomeAndProjectProduceExpectedVerdicts() {
        let r = Fx.scan(home: "home-risky", projects: ["project-risky"])
        let p = positives(r)
        let r01 = p.filter { $0.ruleID == "R01" }
        #expect(r01.contains { $0.objectID == "acfg:codex:scope_user" && $0.severity == .high })
        #expect(r01.contains { $0.objectID == "acfg:claude-code:scope_user" && $0.severity == .medium })
        let r02 = p.filter { $0.ruleID == "R02" }
        #expect(r02.filter { $0.severity == .high }.count == 3)
        #expect(r02.filter { $0.severity == .medium }.count == 2)
        let unknownR02 = r.verdicts.filter { $0.ruleID == "R02" && $0.outcome == .unknown }
        #expect(unknownR02.count == 1)   // "weird rule ???"
        let r03 = p.filter { $0.ruleID == "R03" }
        #expect(r03.filter { $0.severity == .high }.count >= 5)
        #expect(!r03.contains { $0.objectID.contains("OPENAI_API_KEY") })
        let r04 = p.filter { $0.ruleID == "R04" }
        #expect(r04.contains { $0.objectID.hasSuffix("/.codex/auth.json") && $0.severity == .high })
        let r06 = p.filter { $0.ruleID == "R06" }
        #expect(r06.filter { $0.severity == .high }.count == 3)
        #expect(!r06.contains { $0.objectID.contains("127.0.0.1") })
        #expect(p.filter { $0.ruleID == "R07" }.count == 3)
        #expect(p.contains { $0.ruleID == "R05" && $0.objectID.contains("npx-unpinned") })
        #expect(r.status == .complete, "notes: \(r.notes) gaps: \(r.coverage.filter { $0.status != .success })")
    }

    @Test func cleanHomeIsQuiet() {
        let r = Fx.scan(home: "home-clean", projects: ["project-clean"])
        let p = positives(r).filter { $0.severity == .high }
        #expect(p.isEmpty, "\(p.map { "\($0.ruleID) \($0.objectID)" })")
        #expect(!positives(r).contains { $0.ruleID == "R01" })
        #expect(!positives(r).contains { $0.ruleID == "R02" })
        #expect(!positives(r).contains { $0.ruleID == "R03" })
    }

    @Test func deterministicAcrossRuns() {
        let a = Fx.scan(home: "home-risky", projects: ["project-risky"])
        let b = Fx.scan(home: "home-risky", projects: ["project-risky"])
        let fa = Set(a.verdicts.map { "\($0.ruleID)|\($0.targetFingerprint)|\($0.severity.rawValue)|\($0.outcome.rawValue)" })
        let fb = Set(b.verdicts.map { "\($0.ruleID)|\($0.targetFingerprint)|\($0.severity.rawValue)|\($0.outcome.rawValue)" })
        #expect(fa == fb)
        #expect(a.observations.count == b.observations.count)
    }

    @Test func noRawSecretsAnywhere() throws {
        let r = Fx.scan(home: "home-risky", projects: ["project-risky"])
        let blob = r.observations.map { $0.safeValue + $0.field + $0.objectID + $0.provenance.locationAlias }.joined()
            + r.verdicts.map { $0.summary + $0.objectID }.joined() + r.coverage.map { $0.reason + $0.itemAlias }.joined()
        #expect(!blob.contains("LARM_CANARY_"))
        #expect(!blob.contains("sk-ant-api03-LARMFIXTURE"))
        #expect(!blob.contains("ghp_LARMFIXTURE"))
        #expect(!blob.contains("token=LARM"))
        #expect(!blob.contains("should-not-be-copied"))
        #expect(r.observations.contains { $0.secretFingerprint != nil })
        let db = try Fx.tempDB()
        _ = try ScanRepo.store(db, result: r, kind: "full")
        let bytes = try Data(contentsOf: db.url)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("LARM_CANARY_"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("LARMFIXTURE"))
    }

    @Test func secretCanarySet() throws {
        let red = Fx.redactor
        let pos = Canary.positives
        #expect(pos.count == 40)
        var missed: [String] = []
        for v in pos where red.redact(value: v, key: "value").kind != .redacted { missed.append(String(v.prefix(12))) }
        #expect(missed.isEmpty, "missed: \(missed)")
        let fp = Canary.negatives.filter { red.redact(value: $0, key: "value").kind == .redacted }
        #expect(fp.count <= 5, "false positives: \(fp)")
    }

    @Test func noExecutionOfDiscoveredBinaries() throws {
        let home = try Fx.copyToTemp("home-risky")
        try FileManager.default.createDirectory(atPath: home + "/.local/bin", withIntermediateDirectories: true)
        let marker = home + "/EXECUTED"
        try "#!/bin/sh\ntouch \(marker)\n".write(toFile: home + "/.local/bin/claude", atomically: true, encoding: .utf8)
        chmod(home + "/.local/bin/claude", 0o755)
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let r = Scanner(rules: Fx.rules, redactor: Fx.redactor).run(scopes: scopes)
        #expect(!FileManager.default.fileExists(atPath: marker))
        let agent = r.observations.first { $0.objectID == "agent:claude-code" && $0.field == "version" }
        #expect(agent?.valueKind == .unknown)
        let st = r.observations.first { $0.objectID == "agent:claude-code" && $0.field == "install_status" }
        #expect(st?.safeValue == "installed")
    }
}
