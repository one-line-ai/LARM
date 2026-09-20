import Foundation

/// 수신 사건의 정규화·별칭·중복·순서·판정.
public struct RuntimeEvent: Identifiable, Sendable, Equatable {
    public var id: String { eventID }
    public let eventID: String
    public let sourceEventID: String
    public let phase: String
    public let hookEventName: String
    public let toolName: String
    public let targetKind: String
    public let targetAlias: String
    public let scopeID: String?
    public let outsideScope: Bool
    public let commandBasename: String?
    public let argc: Int
    public let argFingerprint: String
    public let flags: [String]
    public let sessionRef: String
    public let processRef: String
    public let observedAt: String
    public let receivedAt: String
    public let seq: Int
    public let delivery: String
    public let resultPresent: Bool
    public let riskRule: String?
    public let riskOutcome: String?
    public let riskSeverity: String?
    public let riskSummary: String?
    public let riskLimits: String?
    public let riskNext: String?
    public let ackState: String
    public let duplicateCount: Int
}

public enum EventIngest {
    public enum Result: Equatable, Sendable { case stored(String), duplicate(String), rejected(String) }

    /// 경로 → 별칭.
    public static func alias(path: String, scopes: [Scope], home: String = NSHomeDirectory()) -> (alias: String, scopeID: String?, outside: Bool) {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        for s in scopes where s.kind == .project && !s.excluded {
            if std == s.realPath || std.hasPrefix(s.realPath.hasSuffix("/") ? s.realPath : s.realPath + "/") {
                return ("<\(s.alias)>" + std.dropFirst(s.realPath.count), s.scopeID, false)
            }
        }
        if std.hasPrefix(home) { return ("~" + std.dropFirst(home.count), nil, true) }
        return (std, nil, true)
    }

    public static func ingest(_ db: SQLiteDB, raw: Data, scopes: [Scope], rules: ActivityRuleSet?, delivery: String, now: String = Clock.nowUTC()) -> Result {
        let ev: HookEvent
        do { ev = try JSONDecoder().decode(HookEvent.self, from: raw) } catch { return .rejected("schema 해석 실패") }
        guard ev.schema == HookEvent.schema else { return .rejected("미지원 schema \(ev.schema)") }
        return ingest(db, ev, scopes: scopes, rules: rules, delivery: delivery, now: now)
    }

    public static func ingest(_ db: SQLiteDB, _ ev: HookEvent, scopes: [Scope], rules: ActivityRuleSet?, delivery: String, now: String = Clock.nowUTC()) -> Result {
        let dedupe = "\(ev.sourceEventID)|\(ev.phase)"
        if let r = try? db.query("SELECT event_id FROM runtime_event WHERE dedupe_key=?", [.text(dedupe)]).first, let id = r["event_id"]?.string {
            _ = try? db.run("UPDATE runtime_event SET duplicate_count=duplicate_count+1 WHERE event_id=?", [.text(id)])
            return .duplicate(id)
        }
        var targetAlias = "", scopeID: String? = nil, outside = false
        switch ev.targetKind {
        case "file": if let p = ev.targetPath { (targetAlias, scopeID, outside) = alias(path: p, scopes: scopes) }
        case "url": targetAlias = ev.targetPath ?? ""; outside = true
        case "command": targetAlias = ev.commandBasename ?? ""; outside = ev.flags.contains("sensitive_path")
        case "mcp": targetAlias = ev.toolName
        default: targetAlias = ""
        }
        var verdict: ActivityVerdict? = nil
        if ev.phase == "request", let rules {
            let vs = ActivityRules.evaluate(rules, targetKind: ev.targetKind, flags: ev.flags, outsideScope: outside)
            verdict = vs.first(where: { $0.outcome == .positive }).map { v in vs.filter { $0.outcome == .positive }.max(by: { $0.severity < $1.severity }) ?? v } ?? vs.first
        }
        let seq = (try? db.scalar("SELECT COALESCE(MAX(seq),0)+1 FROM runtime_event").int).map(Int.init) ?? 1
        let flagsJSON = String(decoding: (try? JSONEncoder().encode(ev.flags)) ?? Data("[]".utf8), as: UTF8.self)
        do {
            try db.run("INSERT INTO runtime_event VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       [.text(ev.eventID), .text(ev.sourceEventID), .text(dedupe), .text("claude-code-hook"), .text(ev.phase), .text(ev.hookEventName), .text(ev.toolName),
                        .text(ev.targetKind), .text(targetAlias), .from(scopeID), .from(outside), .from(ev.commandBasename), .int(Int64(ev.argc)), .text(ev.argFingerprint),
                        .text(flagsJSON), .text(ev.sessionRef), .text(ev.processRef), .text(ev.observedAt), .text(now), .int(Int64(seq)), .text(delivery), .from(ev.resultPresent),
                        .from(verdict?.ruleID), .from(verdict?.ruleVersion), .from(verdict?.outcome.rawValue), .from(verdict?.severity.rawValue), .from(verdict?.summary),
                        .from(verdict?.limits), .from(verdict?.nextAction), .text("observed"), .int(0)])
        } catch { return .rejected("\(error)") }
        return .stored(ev.eventID)
    }

    /// 앱이 꺼져 있던 동안의 spool을 수집한다.
    public static func drainSpool(_ db: SQLiteDB, dir: URL, scopes: [Scope], rules: ActivityRuleSet?) -> (Int, Int) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return (0, 0) }
        var ok = 0, bad = 0
        for n in names.sorted() where n.hasSuffix(".json") {
            let u = dir.appendingPathComponent(n)
            if let d = try? Data(contentsOf: u) {
                switch ingest(db, raw: d, scopes: scopes, rules: rules, delivery: "spool") { case .rejected: bad += 1; default: ok += 1 }
            } else { bad += 1 }
            try? FileManager.default.removeItem(at: u)
        }
        return (ok, bad)
    }

    public static func list(_ db: SQLiteDB, limit: Int = 500) throws -> [RuntimeEvent] {
        try db.query("SELECT * FROM runtime_event ORDER BY seq DESC LIMIT ?", [.int(Int64(limit))]).map(map)
    }
    public static func forSource(_ db: SQLiteDB, sourceEventID: String) throws -> [RuntimeEvent] {
        try db.query("SELECT * FROM runtime_event WHERE source_event_id=? ORDER BY seq", [.text(sourceEventID)]).map(map)
    }
    public static func acknowledge(_ db: SQLiteDB, eventID: String, state: String) throws {
        try db.run("UPDATE runtime_event SET ack_state=? WHERE event_id=?", [.text(state), .text(eventID)])
    }
    public static func purge(_ db: SQLiteDB, olderThanDays days: Int) throws -> Int {
        let cutoff = Clock.utc(Date().addingTimeInterval(-Double(days) * 86400))
        return try db.run("DELETE FROM runtime_event WHERE received_at < ?", [.text(cutoff)])
    }

    static func map(_ r: SQLiteDB.Row) -> RuntimeEvent {
        RuntimeEvent(eventID: r["event_id"]?.string ?? "", sourceEventID: r["source_event_id"]?.string ?? "", phase: r["phase"]?.string ?? "",
                     hookEventName: r["hook_event_name"]?.string ?? "", toolName: r["tool_name"]?.string ?? "", targetKind: r["target_kind"]?.string ?? "",
                     targetAlias: r["target_alias"]?.string ?? "", scopeID: r["scope_id"]?.string, outsideScope: (r["outside_scope"]?.int ?? 0) == 1,
                     commandBasename: r["command_basename"]?.string, argc: Int(r["argc"]?.int ?? 0), argFingerprint: r["arg_fp"]?.string ?? "",
                     flags: (try? JSONDecoder().decode([String].self, from: Data((r["flags_json"]?.string ?? "[]").utf8))) ?? [],
                     sessionRef: r["session_ref"]?.string ?? "", processRef: r["process_ref"]?.string ?? "", observedAt: r["observed_at"]?.string ?? "",
                     receivedAt: r["received_at"]?.string ?? "", seq: Int(r["seq"]?.int ?? 0), delivery: r["delivery"]?.string ?? "", resultPresent: (r["result_present"]?.int ?? 0) == 1,
                     riskRule: r["risk_rule"]?.string, riskOutcome: r["risk_outcome"]?.string, riskSeverity: r["risk_severity"]?.string, riskSummary: r["risk_summary"]?.string,
                     riskLimits: r["risk_limits"]?.string, riskNext: r["risk_next"]?.string, ackState: r["ack_state"]?.string ?? "observed", duplicateCount: Int(r["duplicate_count"]?.int ?? 0))
    }
}
