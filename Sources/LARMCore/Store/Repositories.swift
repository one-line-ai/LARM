import Foundation

public enum ScopeRepo {
    public static func all(_ db: SQLiteDB) throws -> [Scope] {
        try db.query("SELECT * FROM scope ORDER BY kind DESC, alias").map {
            Scope(scopeID: $0["scope_id"]?.string ?? "", alias: $0["alias"]?.string ?? "", realPath: $0["real_path"]?.string ?? "",
                  kind: Scope.Kind(rawValue: $0["kind"]?.string ?? "") ?? .project, excluded: ($0["excluded"]?.int ?? 0) == 1)
        }
    }

    /// 사용자 루트 scope는 항상 하나 존재한다.
    @discardableResult
    public static func ensureUserRoot(_ db: SQLiteDB) throws -> Scope {
        if let s = try all(db).first(where: { $0.kind == .userRoot }) { return s }
        let s = Scope(scopeID: "scope_user", alias: "user", realPath: NSHomeDirectory(), kind: .userRoot)
        try insert(db, s)
        return s
    }

    public static func insert(_ db: SQLiteDB, _ s: Scope) throws {
        try db.run("INSERT INTO scope VALUES(?,?,?,?,?,?)", [.text(s.scopeID), .text(s.alias), .text(s.realPath), .text(s.kind.rawValue),
                                                            .from(s.excluded), .text(Clock.nowUTC())])
        try Audit.record(db, kind: "scope_added", detail: ["scope_id": s.scopeID, "alias": s.alias])
    }

    /// 프로젝트 추가.
    public static func addProject(_ db: SQLiteDB, path: String) throws -> Scope {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        if let ex = try all(db).first(where: { $0.realPath == std }) { return ex }
        var alias = (std as NSString).lastPathComponent
        let existing = Set(try all(db).map { $0.alias })
        var n = 2
        while existing.contains(alias) { alias = "\((std as NSString).lastPathComponent)-\(n)"; n += 1 }
        let s = Scope(scopeID: Ids.new("scope"), alias: alias, realPath: std, kind: .project)
        try insert(db, s)
        return s
    }

    public static func remove(_ db: SQLiteDB, scopeID: String) throws {
        try db.run("DELETE FROM scope WHERE scope_id=? AND kind='project'", [.text(scopeID)])
        try Audit.record(db, kind: "scope_removed", detail: ["scope_id": scopeID])
    }

    public static func setExcluded(_ db: SQLiteDB, scopeID: String, _ ex: Bool) throws {
        try db.run("UPDATE scope SET excluded=? WHERE scope_id=?", [.from(ex), .text(scopeID)])
    }
}

public struct ScanSummary: Identifiable, Sendable {
    public var id: String { scanID }
    public let scanID: String
    public let sequence: Int
    public let kind: String
    public let status: ScanStatus
    public let startedAt: String
    public let endedAt: String
    public let rulesVersion: String
    public let counts: [String: Int]
    public let notes: [String]
}

public enum ScanRepo {
    static func json<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return String(decoding: (try? e.encode(v)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// 점검 결과 저장 + finding 생명주기 반영.
    /// 일부 범위만 다시 읽은 결과에 나머지 범위의 마지막 결과를 합친다. 다시 읽지 않은 범위의 coverage와 값은 그대로 유지된다.
    public static func merged(_ db: SQLiteDB, result: ScanResult) throws -> ScanResult {
        let registered = try ScopeRepo.all(db).filter { !$0.excluded }
        let scanned = Set(result.scopes.map { $0.scopeID })
        let missing = registered.filter { !scanned.contains($0.scopeID) }
        guard !missing.isEmpty, let last = try latestCompletedOrPartial(db) else { return result }
        let missingIDs = Set(missing.map { $0.scopeID })
        let obs = try observations(db, scanID: last.scanID).filter { missingIDs.contains($0.provenance.scopeID) }
        let cov = try coverage(db, scanID: last.scanID).filter { missingIDs.contains($0.scopeID) }
        guard !obs.isEmpty || !cov.isEmpty else { return result }
        return ScanResult(scanID: result.scanID, status: result.status, startedAt: result.startedAt, endedAt: result.endedAt,
                          scopes: result.scopes + missing, coverage: result.coverage + cov, observations: result.observations + obs,
                          verdicts: result.verdicts, adapterVersions: result.adapterVersions, rulesVersion: result.rulesVersion,
                          notes: result.notes + ["\(missing.map { $0.alias }.joined(separator: ", ")) 범위는 이전 점검 결과를 유지했습니다."])
    }

    public static func store(_ db: SQLiteDB, result partial: ScanResult, kind: String, keyID: String = "") throws -> ScanSummary {
        let result = try merged(db, result: partial)
        return try db.transaction {
            let seq = (try db.scalar("SELECT COALESCE(MAX(sequence),0)+1 FROM scan").int).map(Int.init) ?? 1
            let scopeDigest = Hashing.sha256Hex(result.scopes.map { $0.scopeID }.sorted().joined(separator: ",")).prefix(16).description
            let positives = result.verdicts.filter { $0.outcome == .positive && $0.severity != .gap }
            let counts: [String: Int] = [
                "observations": result.observations.count, "coverage": result.coverage.count,
                "gaps": result.coverage.filter { $0.status != .success }.count,
                "verdicts_positive": positives.count, "verdicts_unknown": result.verdicts.filter { $0.outcome == .unknown }.count,
            ]
            try db.run("INSERT INTO scan VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                       [.text(result.scanID), .int(Int64(seq)), .text(scopeDigest), .text(kind), .text(result.status.rawValue),
                        .text(result.startedAt), .text(result.endedAt), .text(Clock.localTimeZoneID), .text(json(result.adapterVersions)),
                        .text(result.rulesVersion), .text(json(result.notes)), .text(json(counts))])
            for c in result.coverage {
                try db.run("INSERT INTO coverage VALUES(?,?,?,?,?,?,?)", [.text(result.scanID), .text(c.adapter), .text(c.adapterVersion),
                                                                          .text(c.scopeID), .text(c.itemAlias), .text(c.status.rawValue), .text(c.reason)])
            }
            for o in result.observations {
                try db.run("INSERT INTO observation VALUES(?,?,?,?,?,?,?,?,?)",
                           [.text(o.observationID), .text(result.scanID), .text(o.objectID), .text(o.objectType.rawValue), .text(o.field),
                            .text(o.safeValue), .text(o.valueKind.rawValue), .text(json(o.provenance)), .from(o.secretFingerprint)])
            }
            if result.status != .cancelled {
                try FindingRepo.reconcile(db, result: result)
                try db.run("INSERT INTO snapshot VALUES(?,?,?,?,?,?,?)",
                           [.text(Ids.new("snap")), .text(result.scanID), .text(Digest.content(result.observations, scopes: result.scopes, adapterVersions: result.adapterVersions)),
                            .text(Digest.secrets(result.observations)), .text(Digest.scopeDigest(result.scopes)), .text(keyID), .text(Clock.nowUTC())])
                _ = try DecisionRepo.reviewExceptions(db, evidenceDigests: FindingRepo.evidenceDigests(db, result: result))
            }
            return ScanSummary(scanID: result.scanID, sequence: seq, kind: kind, status: result.status, startedAt: result.startedAt,
                               endedAt: result.endedAt, rulesVersion: result.rulesVersion, counts: counts, notes: result.notes)
        }
    }

    public static func latest(_ db: SQLiteDB) throws -> ScanSummary? { try list(db, limit: 1).first }
    public static func get(_ db: SQLiteDB, scanID: String) throws -> ScanSummary? { try list(db, limit: 10000).first { $0.scanID == scanID } }
    public static func snapshotDigest(_ db: SQLiteDB, scanID: String) throws -> (content: String, secret: String, keyID: String)? {
        guard let r = try db.query("SELECT content_digest, secret_digest, key_id FROM snapshot WHERE scan_id=?", [.text(scanID)]).first else { return nil }
        return (r["content_digest"]?.string ?? "", r["secret_digest"]?.string ?? "", r["key_id"]?.string ?? "")
    }
    public static func scopeIDs(_ db: SQLiteDB, scanID: String) throws -> Set<String> {
        Set(try db.query("SELECT DISTINCT scope_id FROM coverage WHERE scan_id=?", [.text(scanID)]).compactMap { $0["scope_id"]?.string })
    }
    public static func latestCompletedOrPartial(_ db: SQLiteDB) throws -> ScanSummary? {
        try list(db, limit: 50).first { $0.status == .complete || $0.status == .partial }
    }

    public static func list(_ db: SQLiteDB, limit: Int = 50) throws -> [ScanSummary] {
        try db.query("SELECT * FROM scan ORDER BY sequence DESC LIMIT ?", [.int(Int64(limit))]).map { r in
            let counts = (try? JSONDecoder().decode([String: Int].self, from: Data((r["counts_json"]?.string ?? "{}").utf8))) ?? [:]
            let notes = (try? JSONDecoder().decode([String].self, from: Data((r["notes_json"]?.string ?? "[]").utf8))) ?? []
            return ScanSummary(scanID: r["scan_id"]?.string ?? "", sequence: Int(r["sequence"]?.int ?? 0), kind: r["kind"]?.string ?? "",
                               status: ScanStatus(rawValue: r["status"]?.string ?? "") ?? .failed, startedAt: r["started_at"]?.string ?? "",
                               endedAt: r["ended_at"]?.string ?? "", rulesVersion: r["rule_version"]?.string ?? "", counts: counts, notes: notes)
        }
    }

    public static func coverage(_ db: SQLiteDB, scanID: String) throws -> [Coverage] {
        try db.query("SELECT * FROM coverage WHERE scan_id=? ORDER BY status, item_alias", [.text(scanID)]).map {
            Coverage(adapter: $0["adapter"]?.string ?? "", adapterVersion: $0["adapter_version"]?.string ?? "", scopeID: $0["scope_id"]?.string ?? "",
                     itemAlias: $0["item_alias"]?.string ?? "", status: CoverageStatus(rawValue: $0["status"]?.string ?? "") ?? .error, reason: $0["reason"]?.string ?? "")
        }
    }

    public static func observations(_ db: SQLiteDB, scanID: String, objectID: String? = nil) throws -> [Observation] {
        let rows = objectID == nil
            ? try db.query("SELECT * FROM observation WHERE scan_id=? ORDER BY object_id, field", [.text(scanID)])
            : try db.query("SELECT * FROM observation WHERE scan_id=? AND object_id=? ORDER BY field", [.text(scanID), .text(objectID!)])
        return rows.compactMap { r in
            guard let prov = try? JSONDecoder().decode(Provenance.self, from: Data((r["provenance_json"]?.string ?? "{}").utf8)) else { return nil }
            return Observation(objectID: r["object_id"]?.string ?? "", objectType: ObjectType(rawValue: r["object_type"]?.string ?? "") ?? .configuration,
                               field: r["field"]?.string ?? "", safeValue: r["safe_value"]?.string ?? "",
                               valueKind: ValueKind(rawValue: r["value_kind"]?.string ?? "") ?? .unknown, provenance: prov, secretFingerprint: r["secret_fp"]?.string)
        }
    }
}

public struct Finding: Identifiable, Sendable, Equatable {
    public var id: String { findingID }
    public let findingID: String
    public let ruleID: String
    public let ruleVersion: String
    public let objectID: String
    public let objectType: ObjectType
    public let targetFingerprint: String
    public let severity: Severity
    public let confidence: Confidence
    public let title: String
    public let summary: String
    public let evidence: [String]
    public let limits: String
    public let nextAction: String
    public let scopeID: String
    public let locationAlias: String
    public let state: FindingState
    public let firstScanID: String
    public let lastScanID: String
    public let seenCount: Int
    public let openedAt: String
    public let updatedAt: String
    /// verified | unverifiable (재점검에서 대상을 읽지 못함)
    public let verifyStatus: String
}

public enum FindingRepo {
    /// 스캔 결과로 finding 생명주기 갱신.
    /// - 양성: 새로면 open, 있으면 seen_count+1, resolved 상태였으면 다시 open
    /// - 미탐지: 대상의 coverage가 success면 resolved_by_rescan, 아니면 상태 유지 + unverifiable
    static func reconcile(_ db: SQLiteDB, result: ScanResult) throws {
        let now = Clock.nowUTC()
        let scannedScopes = Set(result.scopes.map { $0.scopeID })
        let positives = result.verdicts.filter { $0.outcome == .positive }
        var seen = Set<String>()
        for v in positives {
            let fp = v.targetFingerprint
            seen.insert("\(v.ruleID)|\(fp)")
            let ev = ScanRepo.json(v.evidence)
            if let r = try db.query("SELECT finding_id, state FROM finding WHERE rule_id=? AND target_fp=?", [.text(v.ruleID), .text(fp)]).first {
                let fid = r["finding_id"]?.string ?? ""
                let st = FindingState(rawValue: r["state"]?.string ?? "") ?? .open
                var newState = st
                if st == .resolvedByRescan { newState = .open }
                try db.run("""
                    UPDATE finding SET severity=?, confidence=?, summary=?, evidence_json=?, last_scan_id=?, seen_count=seen_count+1,
                      updated_at=?, state=?, verify_status='verified', rule_version=?, limits_text=?, next_action_text=? WHERE finding_id=?
                    """, [.text(v.severity.rawValue), .text(v.confidence.rawValue), .text(v.summary), .text(ev), .text(result.scanID), .text(now),
                          .text(newState.rawValue), .text(v.ruleVersion), .text(v.limits), .text(v.nextAction), .text(fid)])
                if newState != st {
                    try event(db, fid, kind: "reopened", from: st, to: newState, scanID: result.scanID, actor: "engine", note: "재탐지")
                }
            } else {
                let fid = Ids.new("f")
                try db.run("INSERT INTO finding VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                           [.text(fid), .text(v.ruleID), .text(v.ruleVersion), .text(v.objectID), .text(v.objectType.rawValue), .text(fp),
                            .text(v.severity.rawValue), .text(v.confidence.rawValue), .text(v.title), .text(v.summary), .text(ev), .text(v.limits),
                            .text(v.nextAction), .text(v.scopeID), .text(v.locationAlias), .text(FindingState.open.rawValue), .text(result.scanID),
                            .text(result.scanID), .int(1), .text(now), .text(now), .text("verified")])
                try event(db, fid, kind: "opened", from: nil, to: .open, scanID: result.scanID, actor: "engine", note: "최초 탐지")
            }
        }
        let candidates = try db.query("SELECT finding_id, rule_id, target_fp, state, scope_id, location_alias, object_type FROM finding WHERE state IN ('open','in_progress','excepted','false_positive_review')")
        let successAliases = Set(result.coverage.filter { $0.status == .success }.map { $0.itemAlias })
        let registeredScopes = Set(try ScopeRepo.all(db).map { $0.scopeID }).union(scannedScopes)
        for r in candidates {
            let key = "\(r["rule_id"]?.string ?? "")|\(r["target_fp"]?.string ?? "")"
            if seen.contains(key) { continue }
            let sid = r["scope_id"]?.string ?? ""
            if !registeredScopes.contains(sid) {
                try db.run("UPDATE finding SET verify_status='scope_removed', updated_at=? WHERE finding_id=?", [.text(now), .text(r["finding_id"]?.string ?? "")])
                continue
            }
            guard scannedScopes.contains(sid) else { continue }
            let fid = r["finding_id"]?.string ?? ""
            let st = FindingState(rawValue: r["state"]?.string ?? "") ?? .open
            let alias = r["location_alias"]?.string ?? ""
            let objType = r["object_type"]?.string ?? ""
            let verifiable = objType == ObjectType.coverageItem.rawValue ? true : coverageSucceeded(alias: alias, success: successAliases)
            if verifiable {
                if st == .open || st == .inProgress || st == .falsePositiveReview || st == .excepted {
                    try db.run("UPDATE finding SET state=?, updated_at=?, last_scan_id=?, verify_status='verified' WHERE finding_id=?",
                               [.text(FindingState.resolvedByRescan.rawValue), .text(now), .text(result.scanID), .text(fid)])
                    try event(db, fid, kind: "resolved", from: st, to: .resolvedByRescan, scanID: result.scanID, actor: "engine", note: "재점검에서 원인 조건이 사라짐")
                }
            } else {
                try db.run("UPDATE finding SET verify_status='unverifiable', updated_at=? WHERE finding_id=?", [.text(now), .text(fid)])
            }
        }
    }

    /// 근거 관측값 digest (예외 재검토용): finding_id → sha256(근거 safe_value들)
    static func evidenceDigests(_ db: SQLiteDB, result: ScanResult) throws -> [String: String] {
        let byID = Dictionary(result.observations.map { ($0.observationID, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: String] = [:]
        for v in result.verdicts where v.outcome == .positive {
            guard let r = try db.query("SELECT finding_id FROM finding WHERE rule_id=? AND target_fp=?", [.text(v.ruleID), .text(v.targetFingerprint)]).first,
                  let fid = r["finding_id"]?.string else { continue }
            out[fid] = evidenceDigest(v.evidence, byID)
        }
        return out
    }
    public static func evidenceDigest(_ evidence: [String], _ byID: [String: Observation]) -> String {
        Hashing.sha256Hex(evidence.sorted().map { id in (byID[id].map { "\($0.field)=\($0.valueKind == .redacted ? ($0.secretFingerprint ?? "") : $0.safeValue)" } ?? id) }.joined(separator: "\n"))
    }

    static func coverageSucceeded(alias: String, success: Set<String>) -> Bool {
        if success.contains(alias) { return true }
        if let base = alias.split(separator: " ").first, success.contains(String(base)) { return true }
        return false
    }

    static func event(_ db: SQLiteDB, _ fid: String, kind: String, from: FindingState?, to: FindingState?, scanID: String?, actor: String, note: String) throws {
        try db.run("INSERT INTO finding_event(finding_id, at, kind, from_state, to_state, scan_id, actor, note) VALUES(?,?,?,?,?,?,?,?)",
                   [.text(fid), .text(Clock.nowUTC()), .text(kind), .from(from?.rawValue), .from(to?.rawValue), .from(scanID), .text(actor), .text(note)])
    }

    /// 사용자 상태 변경.
    public static func userTransition(_ db: SQLiteDB, findingID: String, to: FindingState, note: String) throws {
        precondition(to != .resolvedByRescan, "resolved_by_rescan은 엔진만 기록한다")
        guard let r = try db.query("SELECT state FROM finding WHERE finding_id=?", [.text(findingID)]).first else { return }
        let from = FindingState(rawValue: r["state"]?.string ?? "") ?? .open
        try db.transaction {
            try db.run("UPDATE finding SET state=?, updated_at=? WHERE finding_id=?", [.text(to.rawValue), .text(Clock.nowUTC()), .text(findingID)])
            try event(db, findingID, kind: "user", from: from, to: to, scanID: nil, actor: "user", note: note)
        }
    }

    public static func list(_ db: SQLiteDB) throws -> [Finding] {
        try db.query("SELECT * FROM finding ORDER BY CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 3 END, updated_at DESC").map(map)
    }

    public static func get(_ db: SQLiteDB, findingID: String) throws -> Finding? {
        try db.query("SELECT * FROM finding WHERE finding_id=?", [.text(findingID)]).first.map(map)
    }

    public static func events(_ db: SQLiteDB, findingID: String) throws -> [(at: String, kind: String, from: String?, to: String?, actor: String, note: String)] {
        try db.query("SELECT * FROM finding_event WHERE finding_id=? ORDER BY seq", [.text(findingID)]).map {
            ($0["at"]?.string ?? "", $0["kind"]?.string ?? "", $0["from_state"]?.string, $0["to_state"]?.string, $0["actor"]?.string ?? "", $0["note"]?.string ?? "")
        }
    }

    static func map(_ r: SQLiteDB.Row) -> Finding {
        Finding(findingID: r["finding_id"]?.string ?? "", ruleID: r["rule_id"]?.string ?? "", ruleVersion: r["rule_version"]?.string ?? "",
                objectID: r["object_id"]?.string ?? "", objectType: ObjectType(rawValue: r["object_type"]?.string ?? "") ?? .configuration,
                targetFingerprint: r["target_fp"]?.string ?? "", severity: Severity(rawValue: r["severity"]?.string ?? "") ?? .medium,
                confidence: Confidence(rawValue: r["confidence"]?.string ?? "") ?? .low, title: r["title"]?.string ?? "", summary: r["summary"]?.string ?? "",
                evidence: (try? JSONDecoder().decode([String].self, from: Data((r["evidence_json"]?.string ?? "[]").utf8))) ?? [],
                limits: r["limits_text"]?.string ?? "", nextAction: r["next_action_text"]?.string ?? "", scopeID: r["scope_id"]?.string ?? "",
                locationAlias: r["location_alias"]?.string ?? "", state: FindingState(rawValue: r["state"]?.string ?? "") ?? .open,
                firstScanID: r["first_scan_id"]?.string ?? "", lastScanID: r["last_scan_id"]?.string ?? "", seenCount: Int(r["seen_count"]?.int ?? 0),
                openedAt: r["opened_at"]?.string ?? "", updatedAt: r["updated_at"]?.string ?? "", verifyStatus: r["verify_status"]?.string ?? "verified")
    }
}
