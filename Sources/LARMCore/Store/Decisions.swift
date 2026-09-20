import Foundation

/// 사용자 결정: 기준점·기한 예외·오탐·엔드포인트 검토.
public struct Decision: Identifiable, Sendable, Equatable {
    public var id: String { decisionID }
    public let decisionID: String
    public let kind: String          // baseline | exception | false_positive | endpoint_reviewed
    public let findingID: String?
    public let targetFP: String?
    public let scanID: String?
    public let objectID: String?
    public let actorAlias: String
    public let reason: String
    public let createdAt: String
    public let expiresAt: String?
    public let ruleVersion: String
    public let evidenceDigest: String
    public let active: Bool
}

public enum DecisionError: Error, CustomStringConvertible {
    case scanNotComplete(String), expiryRequired, expiryOutOfRange, notFound, reasonRequired
    public var description: String {
        switch self {
        case .scanNotComplete(let s): return "부분 점검(\(s))은 전체 기준점으로 지정할 수 없습니다. 범위를 좁혀 명시적으로 재점검하세요."
        case .expiryRequired: return "기한 없는 예외는 저장할 수 없습니다."
        case .expiryOutOfRange: return "예외 기한은 1일 이상 30일 이하여야 합니다."
        case .notFound: return "대상을 찾을 수 없습니다."
        case .reasonRequired: return "사유를 입력하세요."
        }
    }
}

public enum DecisionRepo {
    public static let defaultExceptionDays = 7
    public static let maxExceptionDays = 30


    public static func setBaseline(_ db: SQLiteDB, scanID: String, reason: String, actor: String = "user") throws {
        guard let s = try db.query("SELECT status, rule_version FROM scan WHERE scan_id=?", [.text(scanID)]).first else { throw DecisionError.notFound }
        let status = s["status"]?.string ?? ""
        guard status == ScanStatus.complete.rawValue else { throw DecisionError.scanNotComplete(status) }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { throw DecisionError.reasonRequired }
        try db.transaction {
            try db.run("UPDATE decision SET active=0 WHERE kind='baseline' AND active=1")
            try db.run("INSERT INTO decision VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1)",
                       [.text(Ids.new("dec")), .text("baseline"), .null, .null, .text(scanID), .null, .text(actor), .text(reason), .text(Clock.nowUTC()), .null,
                        .text(s["rule_version"]?.string ?? ""), .text("")])
            try Audit.record(db, kind: "baseline_set", detail: ["scan_id": scanID, "reason": reason])
        }
    }

    public static func currentBaseline(_ db: SQLiteDB) throws -> Decision? {
        try db.query("SELECT * FROM decision WHERE kind='baseline' AND active=1 ORDER BY created_at DESC LIMIT 1").first.map(map)
    }


    public static func addException(_ db: SQLiteDB, finding: Finding, days: Int, reason: String, evidenceDigest: String, actor: String = "user") throws {
        guard days >= 1 else { throw DecisionError.expiryRequired }
        guard days <= maxExceptionDays else { throw DecisionError.expiryOutOfRange }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { throw DecisionError.reasonRequired }
        let exp = Clock.utc(Date().addingTimeInterval(Double(days) * 86400))
        try db.transaction {
            try db.run("UPDATE decision SET active=0 WHERE kind='exception' AND finding_id=? AND active=1", [.text(finding.findingID)])
            try db.run("INSERT INTO decision VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1)",
                       [.text(Ids.new("dec")), .text("exception"), .text(finding.findingID), .text(finding.targetFingerprint), .null, .text(finding.objectID),
                        .text(actor), .text(reason), .text(Clock.nowUTC()), .text(exp), .text(finding.ruleVersion), .text(evidenceDigest)])
            try db.run("UPDATE finding SET state='excepted', updated_at=? WHERE finding_id=?", [.text(Clock.nowUTC()), .text(finding.findingID)])
            try FindingRepo.event(db, finding.findingID, kind: "exception", from: finding.state, to: .excepted, scanID: nil, actor: actor, note: "위험 수용 · 만료 \(String(exp.prefix(10))) · \(reason)")
            try Audit.record(db, kind: "exception_added", detail: ["finding_id": finding.findingID, "expires_at": exp])
        }
    }

    public static func activeException(_ db: SQLiteDB, findingID: String) throws -> Decision? {
        try db.query("SELECT * FROM decision WHERE kind='exception' AND finding_id=? AND active=1 ORDER BY created_at DESC LIMIT 1", [.text(findingID)]).first.map(map)
    }

    /// 만료·룰 변경·근거 변경 시 열림으로 복귀.
    public static func reviewExceptions(_ db: SQLiteDB, evidenceDigests: [String: String] = [:], now: Date = Date()) throws -> Int {
        var reopened = 0
        let rows = try db.query("SELECT * FROM decision WHERE kind='exception' AND active=1")
        for r in rows {
            let d = map(r)
            guard let fid = d.findingID, let f = try FindingRepo.get(db, findingID: fid), f.state == .excepted else { continue }
            var why: String? = nil
            if let e = d.expiresAt, let ed = Clock.parse(e), ed <= now { why = "예외 만료" }
            else if f.ruleVersion != d.ruleVersion { why = "룰 버전 변경 (\(d.ruleVersion) → \(f.ruleVersion))" }
            else if let cur = evidenceDigests[fid], !d.evidenceDigest.isEmpty, cur != d.evidenceDigest { why = "대상 구성 변경" }
            if let why {
                try db.transaction {
                    try db.run("UPDATE decision SET active=0 WHERE decision_id=?", [.text(d.decisionID)])
                    try db.run("UPDATE finding SET state='open', updated_at=? WHERE finding_id=?", [.text(Clock.nowUTC()), .text(fid)])
                    try FindingRepo.event(db, fid, kind: "exception_review", from: .excepted, to: .open, scanID: nil, actor: "engine", note: why)
                }
                reopened += 1
            }
        }
        return reopened
    }


    public static func markEndpointReviewed(_ db: SQLiteDB, objectID: String, reason: String, actor: String = "user") throws {
        guard objectID.hasPrefix("ep:") else { throw DecisionError.notFound }
        try db.transaction {
            try db.run("UPDATE decision SET active=0 WHERE kind='endpoint_reviewed' AND object_id=? AND active=1", [.text(objectID)])
            try db.run("INSERT INTO decision VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1)",
                       [.text(Ids.new("dec")), .text("endpoint_reviewed"), .null, .null, .null, .text(objectID), .text(actor), .text(reason), .text(Clock.nowUTC()), .null, .text(""), .text("")])
            try Audit.record(db, kind: "endpoint_reviewed", detail: ["object_id": objectID])
        }
    }

    public static func reviewedEndpoints(_ db: SQLiteDB) throws -> Set<String> {
        Set(try db.query("SELECT object_id FROM decision WHERE kind='endpoint_reviewed' AND active=1").compactMap { $0["object_id"]?.string })
    }

    public static func all(_ db: SQLiteDB) throws -> [Decision] {
        try db.query("SELECT * FROM decision ORDER BY created_at DESC").map(map)
    }

    static func map(_ r: SQLiteDB.Row) -> Decision {
        Decision(decisionID: r["decision_id"]?.string ?? "", kind: r["kind"]?.string ?? "", findingID: r["finding_id"]?.string, targetFP: r["target_fp"]?.string,
                 scanID: r["scan_id"]?.string, objectID: r["object_id"]?.string, actorAlias: r["actor_alias"]?.string ?? "", reason: r["reason"]?.string ?? "",
                 createdAt: r["created_at"]?.string ?? "", expiresAt: r["expires_at"]?.string, ruleVersion: r["rule_version"]?.string ?? "",
                 evidenceDigest: r["evidence_digest"]?.string ?? "", active: (r["active"]?.int ?? 0) == 1)
    }
}

/// 설정 값 (보존 기간 등)
public enum Settings {
    public static func get(_ db: SQLiteDB, _ key: String) -> String? { try? db.scalar("SELECT value FROM setting WHERE key=?", [.text(key)]).string }
    public static func set(_ db: SQLiteDB, _ key: String, _ value: String) throws {
        try db.run("INSERT INTO setting(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }
    public static func retentionDays(_ db: SQLiteDB) -> Int { Int(get(db, "retention_days") ?? "") ?? 30 }
}

/// 보존과 삭제.
public enum Retention {
    public static let choices = [7, 30, 90]

    @discardableResult
    public static func apply(_ db: SQLiteDB, now: Date = Date()) throws -> Int {
        let days = Settings.retentionDays(db)
        let cutoff = Clock.utc(now.addingTimeInterval(-Double(days) * 86400))
        let keep = Set([try DecisionRepo.currentBaseline(db)?.scanID, try ScanRepo.latest(db)?.scanID].compactMap { $0 })
        let old = try db.query("SELECT scan_id FROM scan WHERE ended_at < ?", [.text(cutoff)]).compactMap { $0["scan_id"]?.string }.filter { !keep.contains($0) }
        guard !old.isEmpty else { return 0 }
        try db.transaction {
            for id in old { try db.run("DELETE FROM scan WHERE scan_id=?", [.text(id)]) }
            try Audit.record(db, kind: "retention_purge", detail: ["deleted_scans": "\(old.count)", "days": "\(days)"])
        }
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
        return old.count
    }
}
