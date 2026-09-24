import Foundation

/// 활동 위험 룰 RR01~RR02.
public struct ActivityRuleSet: Codable, Sendable {
    public let schema: String
    public let version: String
    public let rules: [ActivityRule]
}
public struct ActivityRule: Codable, Sendable {
    public struct When: Codable, Sendable {
        public let targetKind: [String]?
        public let flagsAny: [String]?
        public let outsideScope: Bool?
        enum CodingKeys: String, CodingKey { case targetKind = "target_kind", flagsAny = "flags_any", outsideScope = "outside_scope" }
    }
    public struct V: Codable, Sendable { public let severity: Severity; public let confidence: Confidence; public let when: When; public let summary: String }
    public let id: String
    public let title: String
    public let requirements: [String]
    public let verdicts: [V]
    public let unknownWhen: When?
    public let limits: String
    public let nextAction: String
    enum CodingKeys: String, CodingKey { case id, title, requirements, verdicts, unknownWhen = "unknown_when", limits, nextAction = "next_action" }
}

public struct ActivityVerdict: Sendable, Equatable {
    public let ruleID: String
    public let ruleVersion: String
    public let outcome: Outcome
    public let severity: Severity
    public let confidence: Confidence
    public let title: String
    public let summary: String
    public let limits: String
    public let nextAction: String
}

public enum ActivityRules {
    public static let supportedSchema = "larm-activity-rules/1"
    public static func loadBundled() throws -> ActivityRuleSet {
        let d = try ResourceLocator.data("rules/activity-1.0.0.json")
        let s = try JSONDecoder().decode(ActivityRuleSet.self, from: d)
        guard s.schema == supportedSchema else { throw RuleLoader.LoadError.schemaMismatch(s.schema) }
        return s
    }

    static func matches(_ w: ActivityRule.When, kind: String, flags: Set<String>, outside: Bool) -> Bool {
        if let k = w.targetKind, !k.contains(kind) { return false }
        if let f = w.flagsAny, f.allSatisfy({ !flags.contains($0) }) { return false }
        if let o = w.outsideScope, o != outside { return false }
        return true
    }

    /// 요청 활동 기록 하나에 대한 판단 목록 (룰별 최대 1건).
    public static func evaluate(_ set: ActivityRuleSet, targetKind: String, flags: [String], outsideScope: Bool) -> [ActivityVerdict] {
        let fl = Set(flags)
        var out: [ActivityVerdict] = []
        for r in set.rules {
            if let u = r.unknownWhen, matches(u, kind: targetKind, flags: fl, outside: outsideScope) {
                out.append(ActivityVerdict(ruleID: r.id, ruleVersion: set.version, outcome: .unknown, severity: .gap, confidence: .low, title: r.title,
                                           summary: "판단 보류: 인코딩·간접 실행·대상 불명은 문자열만으로 판단하지 않음", limits: r.limits, nextAction: r.nextAction))
                continue
            }
            if let v = r.verdicts.first(where: { matches($0.when, kind: targetKind, flags: fl, outside: outsideScope) }) {
                out.append(ActivityVerdict(ruleID: r.id, ruleVersion: set.version, outcome: .positive, severity: v.severity, confidence: v.confidence, title: r.title,
                                           summary: v.summary, limits: r.limits, nextAction: r.nextAction))
            }
        }
        return out
    }
}
