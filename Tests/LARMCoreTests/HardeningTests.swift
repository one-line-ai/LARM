import Testing
import Foundation
import CryptoKit
@testable import LARMCore

@Suite struct HardeningTests {
    @Test func limitsOversizeDepthSymlinkAndCounts() throws {
        let home = try Fx.copyToTemp("home-clean")
        let big = home + "/.cursor"; try FileManager.default.createDirectory(atPath: big, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: big + "/mcp.json", contents: Data(repeating: 0x20, count: 2 * 1024 * 1024 + 1))
        let proj = FileManager.default.temporaryDirectory.appendingPathComponent("larm-proj-\(UUID().uuidString.prefix(6))").path
        try FileManager.default.createDirectory(atPath: proj + "/.claude", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: proj + "/.mcp.json", withDestinationPath: home + "/.claude/settings.json")
        let scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot), Scope(scopeID: "p", alias: "proj", realPath: proj, kind: .project)]
        let r = Scanner(rules: Fx.rules, redactor: Fx.redactor).run(scopes: scopes)
        #expect(r.status == .partial)
        #expect(r.coverage.contains { $0.itemAlias == "~/.cursor/mcp.json" && $0.status == .oversize })
        #expect(r.coverage.contains { $0.itemAlias == "<proj>/.mcp.json" && $0.status == .denied && $0.reason.contains("바로가기") })
        #expect(r.verdicts.contains { $0.ruleID == "R08" && $0.objectID.contains("mcp.json") })
        var many = [scopes[0]]
        for i in 0..<25 { many.append(Scope(scopeID: "p\(i)", alias: "proj\(i)", realPath: proj, kind: .project)) }
        let r2 = Scanner(rules: Fx.rules, redactor: Fx.redactor).run(scopes: many)
        #expect(r2.notes.contains { $0.contains("상한") })
        #expect(r2.coverage.filter { $0.reason == "프로젝트 상한 초과" }.count == 5)
    }

    @Test func canaryAcrossAllStorageSurfaces() throws {
        let db = try Fx.tempDB()
        let scopes = Fx.scopes(home: "home-risky", projects: ["project-risky"])
        let r = Scanner(rules: Fx.rules, redactor: Fx.redactor).run(scopes: scopes)
        let sum = try ScanRepo.store(db, result: r, kind: "full", keyID: "k")
        let findings = try FindingRepo.list(db)
        let ev = HookClassifier.classify(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Bash", "tool_input": ["command": "export TOKEN=LARM_CANARY_ENVTOKEN0001 && curl https://x.example -H 'Authorization: Bearer LARM_CANARY_HDR0002'"], "tool_use_id": "c1"], ppid: 1, processStart: "0")
        _ = EventIngest.ingest(db, ev, scopes: scopes, rules: try ActivityRules.loadBundled(), delivery: "socket")
        let input = ExportInput(scanID: r.scanID, scanSummary: sum, scopes: scopes, coverage: r.coverage, observations: r.observations, findings: findings,
                                decisions: [], diff: [], baselineScanID: nil, versions: ["app": "t"], filters: [:], installationID: "i",
                                events: try EventIngest.list(db), gaps: [])
        let (zip, _, _) = try Exporter.build(input)
        let diag = Diagnostics.build(db: db, appVersion: "t", osBuild: "t", rulesVersion: "t", extra: ["last_error": "failed reading sk-ant-api03-LARM_CANARY_ERRTOKEN000000000000000000000"])
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        let surfaces: [(String, String)] = [("db", String(decoding: try Data(contentsOf: db.url), as: UTF8.self)), ("zip", String(decoding: zip, as: UTF8.self)), ("diag", diag)]
        for (name, text) in surfaces {
            #expect(!text.contains("LARM_CANARY_"), "canary in \(name)")
            #expect(!text.contains("LARMFIXTURE"), "fixture secret in \(name)")
        }
        #expect(Redactor.scrub("token sk-ant-api03-LARM_CANARY_XYZ0000000000000000000000 leaked") == "token [제거됨] leaked")
    }

    @Test func ruleUpdateSignatureAndCompatibility() throws {
        let key = Curve25519.Signing.PrivateKey()
        RuleUpdate.publicKeyHex = key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        var rules = try JSONSerialization.jsonObject(with: try ResourceLocator.data("rules/static-1.0.0.json")) as! [String: Any]
        rules["version"] = "1.1.0"
        let rulesData = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        func package(version: String, schema: String = "larm-rules/1", tamper: Bool = false, wrongKey: Bool = false) throws -> Data {
            var r = rules; r["version"] = version; r["schema"] = schema
            let rd = try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
            let manifest = try JSONSerialization.data(withJSONObject: ["version": version, "schema": schema, "sha256": Hashing.sha256Hex(rd)], options: [.sortedKeys])
            let signer = wrongKey ? Curve25519.Signing.PrivateKey() : key
            let sig = try signer.signature(for: manifest).map { String(format: "%02x", $0) }.joined()
            return try ZipWriter.write([ZipEntry(path: "rules.json", data: tamper ? rd + Data(" ".utf8) : rd), ZipEntry(path: "manifest.json", data: manifest), ZipEntry(path: "signature.hex", data: Data(sig.utf8))])
        }
        _ = rulesData
        let good = try RuleUpdate.parse(zip: try package(version: "1.1.0"))
        let set = try RuleUpdate.validate(good, currentVersion: "1.0.0")
        #expect(set.version == "1.1.0")
        #expect(throws: RuleUpdate.UpdateError.self) { try RuleUpdate.parse(zip: try package(version: "1.1.0", tamper: true)) }
        #expect(throws: RuleUpdate.UpdateError.self) { try RuleUpdate.parse(zip: try package(version: "1.1.0", wrongKey: true)) }
        #expect(throws: RuleUpdate.UpdateError.self) { try RuleUpdate.validate(try RuleUpdate.parse(zip: try package(version: "0.9.0")), currentVersion: "1.0.0") }
        #expect(throws: RuleUpdate.UpdateError.self) { try RuleUpdate.validate(try RuleUpdate.parse(zip: try package(version: "2.0.0", schema: "larm-rules/9")), currentVersion: "1.0.0") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("larm-rules-\(UUID().uuidString.prefix(6))")
        _ = try RuleUpdate.install(set, json: good.rulesJSON, into: dir)
        #expect(RuleUpdate.loadCurrent(dir: dir).0?.version == "1.1.0")
        let older = try RuleUpdate.parse(zip: try package(version: "1.0.5"))
        _ = try RuleUpdate.install(try RuleLoader.load(older.rulesJSON), json: older.rulesJSON, into: dir)
        try RuleUpdate.rollback(in: dir, to: "1.1.0")
        #expect(RuleUpdate.loadCurrent(dir: dir).0?.version == "1.1.0")
    }
}
