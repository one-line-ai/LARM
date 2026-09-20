import Testing
import Foundation
@testable import LARMCore

@Suite struct EvidenceTests {
    func makeInput(db: SQLiteDB, home: String) throws -> ExportInput {
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        let r = scanner.run(scopes: scopes)
        let sum = try ScanRepo.store(db, result: r, kind: "full", keyID: "k1")
        return ExportInput(scanID: r.scanID, scanSummary: sum, scopes: scopes, coverage: r.coverage, observations: r.observations,
                           findings: try FindingRepo.list(db), decisions: try DecisionRepo.all(db), diff: [], baselineScanID: nil,
                           versions: ["app": "test", "rules": Fx.rules.version], filters: ["scopes": "user"], installationID: "inst_test")
    }

    @Test func exportThenVerifyOK() throws {
        let db = try Fx.tempDB()
        let (zip, _, msha) = try Exporter.build(try makeInput(db: db, home: Fx.path("home-risky")))
        let rep = Verifier.verify(zip: zip, expectedManifestSHA256: msha)
        #expect(rep.ok, Comment(rawValue: Verifier.render(rep)))
        #expect(rep.fileCount == 13)
        let text = String(decoding: zip, as: UTF8.self)
        #expect(!text.contains("LARM_CANARY_"))
        #expect(!text.contains("LARMFIXTURE"))
        #expect(!text.contains("token=LARM"))
        #expect(!text.contains(Fx.path("home-risky")))
        #expect(!text.contains(NSHomeDirectory()))
        let headers = try ZipReader.centralDirectory(zip)
        let inv = try ZipReader.extract(zip, headers.first { $0.path == "inventory.json" }!)
        #expect(!String(decoding: inv, as: UTF8.self).contains("fingerprint"))
    }

    @Test func tamperedMissingExtraAndPathAttacksFail() throws {
        let db = try Fx.tempDB()
        let (zip, _, _) = try Exporter.build(try makeInput(db: db, home: Fx.path("home-risky")))
        let headers = try ZipReader.centralDirectory(zip)
        var entries = try headers.map { ZipEntry(path: $0.path, data: try ZipReader.extract(zip, $0)) }
        var t1 = entries; let i = t1.firstIndex { $0.path == "findings.json" }!
        t1[i] = ZipEntry(path: "findings.json", data: t1[i].data + Data(" ".utf8))
        #expect(!Verifier.verify(zip: try ZipWriter.write(t1)).ok)
        #expect(!Verifier.verify(zip: try ZipWriter.write(entries.filter { $0.path != "coverage.json" })).ok)
        #expect(!Verifier.verify(zip: try ZipWriter.write(entries + [ZipEntry(path: "extra.txt", data: Data("x".utf8))])).ok)
        var dup = entries; dup.append(entries[i])
        #expect(!Verifier.verify(zip: try ZipWriter.write(dup)).ok)
        var raw = try ZipWriter.write(entries)
        if let r = raw.range(of: Data("README.txt".utf8)) { raw.replaceSubrange(r, with: Data("../EADME.txt".utf8)) }
        #expect(!Verifier.verify(zip: raw).ok)
        let mi = entries.firstIndex { $0.path == "manifest.json" }!
        var mtext = String(decoding: entries[mi].data, as: UTF8.self)
        mtext = mtext.replacingOccurrences(of: "\"export_id\"", with: "\"export_id\" : \"dup\", \"export_id\"", options: [], range: mtext.range(of: "\"export_id\""))
        entries[mi] = ZipEntry(path: "manifest.json", data: Data(mtext.utf8))
        let rep = Verifier.verify(zip: try ZipWriter.write(entries))
        #expect(!rep.ok)
        #expect(rep.checks.contains { $0.name.contains("중복 키") && !$0.pass })
        let (zip2, _, msha2) = try Exporter.build(try makeInput(db: db, home: Fx.path("home-clean")))
        #expect(Verifier.verify(zip: zip2).ok)
        #expect(!Verifier.verify(zip: zip2, expectedManifestSHA256: "00" + msha2.dropFirst(2)).ok)
    }

    @Test func stableDigestAndSecretChange() throws {
        let home = try Fx.copyToTemp("home-risky")
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        let a = scanner.run(scopes: scopes), b = scanner.run(scopes: scopes)
        #expect(Digest.content(a.observations, scopes: scopes, adapterVersions: a.adapterVersions) == Digest.content(b.observations, scopes: scopes, adapterVersions: b.adapterVersions))
        #expect(a.scanID != b.scanID)
        let f = home + "/.cursor/mcp.json"
        var t = try String(contentsOfFile: f, encoding: .utf8)
        t = t.replacingOccurrences(of: "ghp_LARMFIXTURE0123456789abcdefghijklmnopqrstuv", with: "ghp_LARMFIXTURE0123456789abcdefghijklmnopqrstuX")
        try t.write(toFile: f, atomically: true, encoding: .utf8)
        let c = scanner.run(scopes: scopes)
        #expect(Digest.content(a.observations, scopes: scopes, adapterVersions: a.adapterVersions) == Digest.content(c.observations, scopes: scopes, adapterVersions: c.adapterVersions))
        #expect(Digest.secrets(a.observations) != Digest.secrets(c.observations))
        let other = Scanner(rules: Fx.rules, redactor: Redactor(hmacKey: Data(repeating: 9, count: 32))).run(scopes: scopes)
        #expect(Digest.secrets(c.observations) != Digest.secrets(other.observations))
        let diff = Differ.diff(from: a.observations, fromCoverage: a.coverage, to: c.observations, toCoverage: c.coverage, fromScopes: ["scope_user"], toScopes: ["scope_user"])
        #expect(diff.count == 1)
        #expect(diff.first?.secretChanged == true)
        #expect(diff.first?.before == "[제거됨]")
    }

    @Test func diffDistinguishesRemovedFromIncomparable() throws {
        let home = try Fx.copyToTemp("home-risky")
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        let a = scanner.run(scopes: scopes)
        try FileManager.default.removeItem(atPath: home + "/.cursor/mcp.json")
        let b = scanner.run(scopes: scopes)
        let d1 = Differ.diff(from: a.observations, fromCoverage: a.coverage, to: b.observations, toCoverage: b.coverage, fromScopes: ["scope_user"], toScopes: ["scope_user"])
        #expect(d1.contains { $0.change == .removed && $0.objectID.contains("cursor") })
        #expect(!d1.contains { $0.change == .incomparable && $0.objectID.contains("cursor") })
        chmod(home + "/.codex/config.toml", 0o000); defer { chmod(home + "/.codex/config.toml", 0o644) }
        let c = scanner.run(scopes: scopes)
        let d2 = Differ.diff(from: a.observations, fromCoverage: a.coverage, to: c.observations, toCoverage: c.coverage, fromScopes: ["scope_user"], toScopes: ["scope_user"])
        #expect(d2.contains { $0.change == .incomparable && $0.locationAlias == "~/.codex/config.toml" })
        #expect(!d2.contains { $0.change == .removed && $0.locationAlias == "~/.codex/config.toml" })
    }

    @Test func baselineAndExceptions() throws {
        let db = try Fx.tempDB()
        let home = try Fx.copyToTemp("home-risky")
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        let r1 = scanner.run(scopes: scopes)
        _ = try ScanRepo.store(db, result: r1, kind: "full", keyID: "k")
        let before = try FindingRepo.list(db)
        let highBefore = before.filter { $0.severity == .high && $0.state == .open }.count
        #expect(before.contains { $0.ruleID == "R05" && $0.state == .open })
        chmod(home + "/.codex/config.toml", 0o000)
        let partial = scanner.run(scopes: scopes)
        #expect(partial.status == .partial)
        _ = try ScanRepo.store(db, result: partial, kind: "full", keyID: "k")
        #expect(throws: DecisionError.self) { try DecisionRepo.setBaseline(db, scanID: partial.scanID, reason: "x") }
        chmod(home + "/.codex/config.toml", 0o644)
        try DecisionRepo.setBaseline(db, scanID: r1.scanID, reason: "초기 검토 완료")
        #expect(try DecisionRepo.currentBaseline(db)?.scanID == r1.scanID)
        let baseObs = try ScanRepo.observations(db, scanID: r1.scanID)
        let r2 = scanner.run(scopes: scopes, context: .init(baselineObservations: baseObs, reviewedEndpoints: []))
        _ = try ScanRepo.store(db, result: r2, kind: "rescan", keyID: "k")
        let after = try FindingRepo.list(db)
        #expect(after.filter { $0.severity == .high && $0.state == .open }.count == highBefore)
        #expect(!after.contains { $0.ruleID == "R05" && $0.summary.contains("기준점이 없어") && $0.state == .open })
        let hf = after.first { $0.severity == .high && $0.state == .open }!
        #expect(throws: DecisionError.self) { try DecisionRepo.addException(db, finding: hf, days: 0, reason: "r", evidenceDigest: "d") }
        #expect(throws: DecisionError.self) { try DecisionRepo.addException(db, finding: hf, days: 31, reason: "r", evidenceDigest: "d") }
        try DecisionRepo.addException(db, finding: hf, days: 7, reason: "테스트 환경", evidenceDigest: "d")
        #expect(try FindingRepo.get(db, findingID: hf.findingID)?.state == .excepted)
        let n = try DecisionRepo.reviewExceptions(db, now: Date().addingTimeInterval(8 * 86400))
        #expect(n == 1)
        #expect(try FindingRepo.get(db, findingID: hf.findingID)?.state == .open)
        let ep = after.first { $0.ruleID == "R06" && $0.severity == .medium }!
        try DecisionRepo.markEndpointReviewed(db, objectID: ep.objectID, reason: "사내 프록시")
        let r3 = scanner.run(scopes: scopes, context: .init(baselineObservations: baseObs, reviewedEndpoints: try DecisionRepo.reviewedEndpoints(db)))
        _ = try ScanRepo.store(db, result: r3, kind: "rescan", keyID: "k")
        #expect(try FindingRepo.get(db, findingID: ep.findingID)?.state == .resolvedByRescan)
        #expect(try FindingRepo.list(db).contains { $0.ruleID == "R06" && $0.severity == .high && $0.state == .open })
        try Settings.set(db, "retention_days", "7")
        try db.run("UPDATE scan SET ended_at='2020-01-01T00:00:00.000Z' WHERE scan_id=?", [.text(partial.scanID)])
        try db.run("UPDATE scan SET ended_at='2020-01-01T00:00:00.000Z' WHERE scan_id=?", [.text(r1.scanID)])
        let deleted = try Retention.apply(db)
        #expect(deleted == 1)
        #expect(try ScanRepo.get(db, scanID: r1.scanID) != nil)
        #expect(try ScanRepo.get(db, scanID: partial.scanID) == nil)
        #expect(try db.scalar("SELECT COUNT(*) FROM observation WHERE scan_id=?", [.text(partial.scanID)]).int == 0)
    }

    @Test func graphRejectsInvalidEdgesAndKeepsSecretsOut() throws {
        let r = Fx.scan(home: "home-risky", projects: ["project-risky"])
        let db = try Fx.tempDB()
        _ = try ScanRepo.store(db, result: r, kind: "full")
        let g = GraphBuilder().build(observations: r.observations, findings: try FindingRepo.list(db), scopes: Fx.scopes(home: "home-risky", projects: ["project-risky"]), scanID: r.scanID)
        #expect(g.edges.allSatisfy { !$0.evidenceRef.isEmpty })
        #expect(g.edges.contains { $0.type == .declaresMCP })
        #expect(g.edges.contains { $0.type == .pointsTo })
        #expect(g.edges.contains { $0.type == .hasFinding })
        let mcpNames = g.nodes.filter { $0.type == .mcpServer }.map { $0.id }
        #expect(Set(mcpNames).count == mcpNames.count)
        for n in g.nodes where n.type == .secretCandidate {
            #expect(n.attrs["in_file"] == nil)
            #expect(!n.attrs.values.contains { $0.count == 64 })
        }
        #expect(!Ontology.isAllowed(.declaresMCP, from: .agent, to: .mcpServer))
        #expect(Ontology.isAllowed(.declaresMCP, from: .configuration, to: .mcpServer))
    }
}
