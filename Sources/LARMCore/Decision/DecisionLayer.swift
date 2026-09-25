import Foundation

/// 결정 층 질문. Jev가 연결되면 같은 질문을 Jev가 답하고, 그 전에는 규칙 기반 추정이 답한다.
public enum DecisionQuestion: String, Codable, Sendable, CaseIterable {
    case actionNeeded = "Q1"      // 발견 사항이 실제로 조치가 필요할 확률
    case willRespond = "Q2"       // 알리면 24시간 안에 열어 볼 확률
    case changeSoon = "Q5"        // 60분 안에 설정이 바뀔 확률
    case evasion = "Q4"           // 판단 보류 활동이 회피 시도일 확률
}

public struct Estimate: Sendable, Equatable {
    public let question: DecisionQuestion
    public let subject: String
    public let p: Double
    public let basis: String      // 사람이 읽는 근거
    public let model: String      // "rule-1" 또는 Jev 버전
    public init(question: DecisionQuestion, subject: String, p: Double, basis: String, model: String) {
        self.question = question; self.subject = subject; self.p = p; self.basis = basis; self.model = model
    }
}

public struct DecisionInput: Sendable {
    public var openHigh = 0
    public var recentEventCount15m = 0
    public var lastChangeMinutesAgo: Double? = nil
    public var responseRate30d: Double? = nil
    public var responseSamples = 0
    public var quietHours = false
    public init() {}
}

public protocol DecisionLayer {
    var model: String { get }
    func estimate(_ q: DecisionQuestion, subject: String, input: DecisionInput, context: [String: String]) -> Estimate
}

/// 규칙 기반 추정. 값은 보수적이며 화면에 "참고 추정(규칙)"으로 표시된다.
public struct HeuristicDecisionLayer: DecisionLayer {
    public let model = "rule-1"
    public init() {}
    public func estimate(_ q: DecisionQuestion, subject: String, input: DecisionInput, context: [String: String]) -> Estimate {
        switch q {
        case .changeSoon:
            if input.recentEventCount15m > 0 { return Estimate(question: q, subject: subject, p: 0.7, basis: "최근 15분에 AI 도구 활동 \(input.recentEventCount15m)건", model: model) }
            if let m = input.lastChangeMinutesAgo, m < 60 { return Estimate(question: q, subject: subject, p: 0.45, basis: "마지막 설정 변경 \(Int(m))분 전", model: model) }
            return Estimate(question: q, subject: subject, p: 0.12, basis: "최근 활동·변경 없음", model: model)
        case .willRespond:
            if input.quietHours { return Estimate(question: q, subject: subject, p: 0.15, basis: "조용한 시간", model: model) }
            if input.responseSamples >= 5, let r = input.responseRate30d { return Estimate(question: q, subject: subject, p: r, basis: "최근 알림 \(input.responseSamples)건 중 반응률", model: model) }
            return Estimate(question: q, subject: subject, p: 0.6, basis: "표본 부족, 기본값", model: model)
        case .actionNeeded:
            let sev = context["severity"] ?? "medium"; let seen = Int(context["seen"] ?? "1") ?? 1
            let p = (sev == "high" ? 0.85 : 0.45) + min(0.1, Double(seen) * 0.01)
            return Estimate(question: q, subject: subject, p: min(0.95, p), basis: "위험도 \(sev), 재탐지 \(seen)회", model: model)
        case .evasion:
            let flags = context["flags"] ?? ""
            let p = flags.contains("base64") || flags.contains("encoded") ? 0.5 : flags.contains("shell_wrapper") || flags.contains("eval") ? 0.35 : 0.2
            return Estimate(question: q, subject: subject, p: p, basis: "표시: \(flags.isEmpty ? "없음" : flags)", model: model)
        }
    }
}

/// 추정과 나중의 실제 결과를 기록해 보정을 검증한다 (설계 G7).
public enum EstimateRepo {
    public static func record(_ db: SQLiteDB, _ e: Estimate) throws {
        try db.run("INSERT INTO jev_estimate(estimate_id, model_version, question_id, subject_id, p, basis, created_at) VALUES(?,?,?,?,?,?,?)",
                   [.text(Ids.new("est")), .text(e.model), .text(e.question.rawValue), .text(e.subject), .real(e.p), .text(e.basis), .text(Clock.nowUTC())])
    }
    /// 같은 대상의 미결 추정에 결과를 기록한다.
    public static func outcome(_ db: SQLiteDB, question: DecisionQuestion, subject: String, value: Double) throws {
        try db.run("UPDATE jev_estimate SET outcome=?, outcome_at=? WHERE question_id=? AND subject_id=? AND outcome IS NULL",
                   [.real(value), .text(Clock.nowUTC()), .text(question.rawValue), .text(subject)])
    }
    /// 브라이어 점수 (낮을수록 좋음). 표본 5개 미만이면 nil.
    public static func brier(_ db: SQLiteDB, question: DecisionQuestion) throws -> (score: Double, n: Int)? {
        let rows = try db.query("SELECT p, outcome FROM jev_estimate WHERE question_id=? AND outcome IS NOT NULL", [.text(question.rawValue)])
        guard rows.count >= 5 else { return nil }
        let s = rows.reduce(0.0) { acc, r in let p = r["p"]?.double ?? 0, o = r["outcome"]?.double ?? 0; return acc + (p - o) * (p - o) } / Double(rows.count)
        return (s, rows.count)
    }
}

/// 검사 게임 G1: 다음 대조까지의 간격(초). 변경 확률이 높을수록 짧고, 0.7~1.3 무작위 곱으로 예측을 막는다.
public enum InspectionPolicy {
    public static func nextInterval(changeSoon p: Double, base: TimeInterval = 30 * 60, min minI: TimeInterval = 10 * 60, max maxI: TimeInterval = 60 * 60, random: Double = Double.random(in: 0.7...1.3)) -> TimeInterval {
        let t = base / (1 + 2.5 * p)
        return Swift.min(maxI, Swift.max(minI, t)) * random
    }
}

/// 늑대소년 게임 G2: 알림 가치 V = a·b·L − c. 높은 위험과 감시 장애는 게이트를 거치지 않는다.
public enum AlertGate {
    public static func shouldSend(actionNeeded a: Double, willRespond b: Double, weight L: Double, threshold: Double = 0.25, cost: Double = 0.1) -> (send: Bool, value: Double) {
        let v = a * b * L - cost
        return (v > threshold, v)
    }
}
