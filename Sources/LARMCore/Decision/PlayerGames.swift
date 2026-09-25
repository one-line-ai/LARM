import Foundation

/// 설계 10장: 사용자와 에이전트를 플레이어로 본 다섯 게임의 계산. 모두 규칙 기반이며 판단은 사람이 한다.
public enum PlayerGames {

    // MARK: 게임 1 권한 위임: 넓은 허용 규칙을 좁혔을 때 예상되는 확인 요청 수
    public struct Delegation: Sendable, Equatable {
        public let matched30d: Int        // 최근 30일에 이 규칙이 덮었을 요청 수
        public let sessions30d: Int       // 같은 기간 작업 세션 수
        public let perSession: Double
        public let recommendNarrow: Bool  // 세션당 2회 이내면 좁혀도 부담이 작음
        public let basis: String
    }

    /// breadth 값(full_shell, broad_shell, broad_write, wildcard, broad_network)과 범위로 최근 요청을 센다.
    public static func delegation(breadth: String, scopeID: String?, events: [RuntimeEvent], now: Date = Date()) -> Delegation {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let recent = events.filter { $0.phase == "request" && (Clock.parse($0.receivedAt).map { $0 > cutoff } ?? false) && (scopeID == nil || $0.scopeID == scopeID) }
        let matched = recent.filter { e in
            switch breadth {
            case "full_shell", "broad_shell": return e.toolName == "Bash"
            case "broad_write": return e.toolName == "Write" || e.toolName == "Edit" || e.toolName == "MultiEdit" || e.toolName == "NotebookEdit"
            case "wildcard": return e.toolName.hasPrefix("mcp__")
            case "broad_network": return e.targetKind == "url" || e.flags.contains("network_fetch")
            default: return false
            }
        }
        let sessions = Set(recent.map(\.sessionRef)).count
        let per = sessions == 0 ? 0 : Double(matched.count) / Double(sessions)
        let basis = recent.isEmpty ? "최근 30일 활동 기록 없음. 연결(hook)을 등록하면 계산됨" : "최근 30일 요청 \(recent.count)건, 세션 \(sessions)개 기준"
        return Delegation(matched30d: matched.count, sessions30d: sessions, perSession: per, recommendNarrow: !recent.isEmpty && per <= 2, basis: basis)
    }

    // MARK: 게임 2 신호: 세션별로 살펴볼 순서
    public struct SessionSignal: Identifiable, Sendable, Equatable {
        public var id: String { sessionRef }
        public let sessionRef: String
        public let firstAt: String
        public let lastAt: String
        public let requests: Int
        public let flagged: Int
        public let highRisk: Int
        public let outsideScope: Int
        public let p: Double            // 살펴볼 필요 추정 (규칙)
        public let basis: String
        public let reviewed: Bool
    }

    public static func sessionSignals(events: [RuntimeEvent]) -> [SessionSignal] {
        let groups = Dictionary(grouping: events.filter { $0.phase == "request" || $0.phase == "result" }, by: \.sessionRef)
        var out: [SessionSignal] = []
        for (ref, evs) in groups where ref != "unknown" {
            let req = evs.filter { $0.phase == "request" }
            let flagged = req.filter { !$0.flags.isEmpty }.count
            let strong = req.filter { !Set($0.flags).isDisjoint(with: ["base64_decode", "encoded_input", "pipe_to_shell", "eval", "shell_wrapper", "env_dump"]) }.count
            let high = req.filter { $0.riskSeverity == "high" }.count
            let outside = req.filter(\.outsideScope).count
            let sensitive = req.filter { $0.flags.contains("sensitive_path") }.count
            var p = 0.05 + 0.2 * Double(min(strong, 3)) + 0.15 * Double(min(high, 2)) + 0.05 * Double(min(sensitive, 3)) + 0.03 * Double(min(outside, 5))
            p = min(0.95, p)
            var parts: [String] = []
            if strong > 0 { parts.append("숨김·우회형 명령 \(strong)건") }
            if high > 0 { parts.append("높은 위험 판정 \(high)건") }
            if sensitive > 0 { parts.append("민감 경로 접근 \(sensitive)건") }
            if outside > 0 { parts.append("선택 범위 밖 \(outside)건") }
            let reviewed = !req.isEmpty && req.filter { $0.riskRule != nil }.allSatisfy { $0.ackState != "observed" } && req.contains { $0.riskRule != nil }
            let times = evs.map(\.observedAt).sorted()
            out.append(SessionSignal(sessionRef: ref, firstAt: times.first ?? "", lastAt: times.last ?? "", requests: req.count, flagged: flagged, highRisk: high, outsideScope: outside, p: p, basis: parts.isEmpty ? "특이 표시 없음" : parts.joined(separator: ", "), reviewed: reviewed))
        }
        return out.sorted { $0.p != $1.p ? $0.p > $1.p : $0.lastAt > $1.lastAt }
    }

    // MARK: 게임 3 반복 신뢰: 범위별 이력
    public struct TrustRecord: Identifiable, Sendable, Equatable {
        public var id: String { scopeID }
        public let scopeID: String
        public let riskyChanges30d: Int   // 최근 30일에 새로 열린 발견 사항
        public let repeated: Int          // 두 번 이상 열린 대상
        public let openHigh: Int
        public let lastOpenedAt: String?
        public let level: String          // "안정", "주의", "살펴볼 필요"
    }

    public static func trust(_ db: SQLiteDB, findings: [Finding], now: Date = Date()) throws -> [TrustRecord] {
        let cutoff = Clock.utc(now.addingTimeInterval(-30 * 86400))
        let rows = try db.query("""
            SELECT f.scope_id AS s, COUNT(*) AS n, MAX(e.at) AS last,
                   SUM(CASE WHEN (SELECT COUNT(*) FROM finding_event e2 WHERE e2.finding_id=f.finding_id AND e2.kind='opened') >= 2 THEN 1 ELSE 0 END) AS rep
            FROM finding_event e JOIN finding f ON f.finding_id=e.finding_id
            WHERE e.kind='opened' AND e.at > ? GROUP BY f.scope_id
            """, [.text(cutoff)])
        var byScope: [String: (Int, Int, String?)] = [:]
        for r in rows { byScope[r["s"]?.string ?? ""] = (Int(r["n"]?.int ?? 0), Int(r["rep"]?.int ?? 0), r["last"]?.string) }
        let scopes = Set(findings.map(\.scopeID)).union(byScope.keys)
        return scopes.map { sid in
            let v = byScope[sid] ?? (0, 0, nil)
            let high = findings.filter { $0.scopeID == sid && ($0.state == .open || $0.state == .inProgress) && $0.severity == .high }.count
            let level = high > 0 || v.1 > 0 ? "살펴볼 필요" : v.0 > 0 ? "주의" : "안정"
            return TrustRecord(scopeID: sid, riskyChanges30d: v.0, repeated: v.1, openHigh: high, lastOpenedAt: v.2, level: level)
        }.sorted { $0.riskyChanges30d > $1.riskyChanges30d }
    }

    /// G3 기준 상태 권장: 기준이 없거나 7일 넘게 바뀐 것 없이 높은 위험이 0이면 권장한다.
    public static func baselineSuggestion(hasBaseline: Bool, baselineAt: String?, diffCount: Int, openHigh: Int, lastScanAt: String?, now: Date = Date()) -> String? {
        guard lastScanAt != nil, openHigh == 0 else { return nil }
        if !hasBaseline { return "높은 위험이 없는 지금 상태를 기준 상태로 저장하면 이후 변화를 비교할 수 있음" }
        if diffCount > 0, let at = baselineAt, let d = Clock.parse(at), now.timeIntervalSince(d) > 7 * 86400 {
            return "기준 상태를 정한 지 7일이 넘었고 바뀐 설정 \(diffCount)건이 그대로 유지됨. 확인했다면 지금 상태를 새 기준으로 저장하기"
        }
        return nil
    }

    // MARK: 게임 5 주의 배분: 항목별 "확인하면 알 수 있는 것"
    public static func whatYouLearn(_ f: Finding) -> String {
        switch f.ruleID {
        case "R01": return "AI 도구가 확인 없이 실행되는지"
        case "R02": return "허용 규칙이 실제 쓰임보다 넓은지"
        case "R03": return "외부 도구 연결(MCP)이 인터넷에 노출됐는지"
        case "R04": return "설정 파일에 비밀값이 들어 있는지"
        case "R05": return "설정 파일을 다른 사용자가 읽을 수 있는지"
        case "R06": return "설정이 다른 위치를 가리키는지"
        case "R07": return "자동 실행 명령(hook)이 무엇을 하는지"
        case "R08": return "확인하지 못한 항목이 왜 남았는지"
        default: return "이 설정이 의도한 것인지"
        }
    }
}
