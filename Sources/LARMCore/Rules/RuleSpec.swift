import Foundation

/// 룰은 데이터다.
public struct RuleSet: Codable, Sendable {
    public let schema: String
    public let version: String
    public let rules: [RuleSpec]
}

public struct RuleSpec: Codable, Sendable {
    public let id: String
    public let title: String
    public let target: ObjectType
    public let unknownWhen: [Predicate]?
    public let verdicts: [VerdictSpec]
    public let limits: String
    public let nextAction: String
    public let requirements: [String]
    public let guidance: String?

    enum CodingKeys: String, CodingKey {
        case id, title, target, verdicts, limits, requirements, guidance
        case unknownWhen = "unknown_when", nextAction = "next_action"
    }
}

public struct VerdictSpec: Codable, Sendable {
    public let severity: Severity
    public let confidence: Confidence
    public let when: [Predicate]
    public let summary: String
}

/// 닫힌 연산자 집합.
public struct Predicate: Codable, Sendable {
    public enum Op: String, Codable, Sendable {
        case eq, neq, `in`, notIn = "not_in", present, absent, isUnknown = "is_unknown", glob, contains, gte
    }
    public let field: String
    public let op: Op
    public let value: JSONValue?
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported json value")
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s); case .number(let d): try c.encode(d); case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a); case .null: try c.encodeNil()
        }
    }
    var stringValue: String? {
        switch self { case .string(let s): return s; case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"; default: return nil }
    }
    var strings: [String] { if case .array(let a) = self { return a.compactMap { $0.stringValue } }; return stringValue.map { [$0] } ?? [] }
}

public enum RuleLoader {
    public enum LoadError: Error, CustomStringConvertible {
        case missing, invalid(String), schemaMismatch(String)
        public var description: String {
            switch self {
            case .missing: return "룰 파일이 없습니다"
            case .invalid(let s): return "룰 파일 오류: \(s)"
            case .schemaMismatch(let s): return "미지원 룰 schema: \(s)"
            }
        }
    }
    public static let supportedSchema = "larm-rules/1"

    public static func load(_ data: Data) throws -> RuleSet {
        let set: RuleSet
        do { set = try JSONDecoder().decode(RuleSet.self, from: data) } catch { throw LoadError.invalid("\(error)") }
        guard set.schema == supportedSchema else { throw LoadError.schemaMismatch(set.schema) }
        return set
    }

    public static func loadBundled(name: String = "static-1.0.0.json") throws -> RuleSet {
        guard let data = try? ResourceLocator.data("rules/\(name)") else { throw LoadError.missing }
        return try load(data)
    }
}
