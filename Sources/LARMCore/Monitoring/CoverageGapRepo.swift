import Foundation

/// 감시 공백.
public struct CoverageGap: Identifiable, Sendable, Equatable {
    public var id: String { gapID }
    public let gapID: String
    public let surface: String     // config_watch | activity | app
    public let startedAt: String
    public let endedAt: String?
    public let reason: String      // paused | sleep | not_running | fs_overflow | watch_failed | denied | socket_down | spool_loss
    public let lostCount: Int
    public let recoveryEvidence: String
    public var label: String {
        switch reason {
        case "paused": return "사용자 일시중지"; case "sleep": return "절전"; case "not_running": return "앱 미실행"
        case "fs_overflow": return "파일 이벤트 유실"; case "watch_failed": return "감시 장애"; case "denied": return "권한 거절"
        case "socket_down": return "활동 연동 끊김"; case "spool_loss": return "이벤트 유실"; default: return reason
        }
    }
}

public enum CoverageGapRepo {
    @discardableResult
    public static func open(_ db: SQLiteDB, surface: String, reason: String, startedAt: String = Clock.nowUTC()) throws -> String {
        if let r = try db.query("SELECT gap_id FROM coverage_gap WHERE surface=? AND reason=? AND ended_at IS NULL", [.text(surface), .text(reason)]).first,
           let id = r["gap_id"]?.string { return id }
        let id = Ids.new("gap")
        try db.run("INSERT INTO coverage_gap VALUES(?,?,?,?,?,?,?,?)", [.text(id), .text(surface), .text(startedAt), .null, .text(reason), .int(0), .text(""), .text(Clock.localTimeZoneID)])
        return id
    }

    public static func close(_ db: SQLiteDB, surface: String, reason: String? = nil, evidence: String, lostCount: Int = 0) throws {
        let now = Clock.nowUTC()
        if let reason {
            try db.run("UPDATE coverage_gap SET ended_at=?, recovery_evidence=?, lost_count=lost_count+? WHERE surface=? AND reason=? AND ended_at IS NULL",
                       [.text(now), .text(evidence), .int(Int64(lostCount)), .text(surface), .text(reason)])
        } else {
            try db.run("UPDATE coverage_gap SET ended_at=?, recovery_evidence=? WHERE surface=? AND ended_at IS NULL", [.text(now), .text(evidence), .text(surface)])
        }
    }

    public static func openGaps(_ db: SQLiteDB) throws -> [CoverageGap] {
        try db.query("SELECT * FROM coverage_gap WHERE ended_at IS NULL ORDER BY started_at").map(map)
    }

    public static func recent(_ db: SQLiteDB, limit: Int = 50) throws -> [CoverageGap] {
        try db.query("SELECT * FROM coverage_gap ORDER BY started_at DESC LIMIT ?", [.int(Int64(limit))]).map(map)
    }

    static func map(_ r: SQLiteDB.Row) -> CoverageGap {
        CoverageGap(gapID: r["gap_id"]?.string ?? "", surface: r["surface"]?.string ?? "", startedAt: r["started_at"]?.string ?? "", endedAt: r["ended_at"]?.string,
                    reason: r["reason"]?.string ?? "", lostCount: Int(r["lost_count"]?.int ?? 0), recoveryEvidence: r["recovery_evidence"]?.string ?? "")
    }
}
