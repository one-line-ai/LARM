import Foundation

/// 점검 범위 항목.
public struct Scope: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case userRoot = "user_root", project }
    public var id: String { scopeID }
    public let scopeID: String
    public let alias: String
    public let realPath: String
    public let kind: Kind
    public var excluded: Bool

    public init(scopeID: String, alias: String, realPath: String, kind: Kind, excluded: Bool = false) {
        self.scopeID = scopeID; self.alias = alias; self.realPath = realPath; self.kind = kind; self.excluded = excluded
    }
}

/// coverage 상태.
public enum CoverageStatus: String, Codable, Sendable, CaseIterable {
    case success, absent, denied, oversize, unsupported, error
}

public struct Coverage: Codable, Equatable, Sendable {
    public let adapter: String
    public let adapterVersion: String
    public let scopeID: String
    public let itemAlias: String
    public let status: CoverageStatus
    public let reason: String

    public init(adapter: String, adapterVersion: String, scopeID: String, itemAlias: String, status: CoverageStatus, reason: String = "") {
        self.adapter = adapter; self.adapterVersion = adapterVersion; self.scopeID = scopeID
        self.itemAlias = itemAlias; self.status = status; self.reason = reason
    }
}

public enum ValueKind: String, Codable, Sendable {
    case literal      // 안전한 리터럴 요약
    case ref          // ${VAR} 등 변수 참조
    case redacted     // 원문 제거됨 (지문만 로컬 보관)
    case unknown      // 확인 못 함 / 해석 불가
}

/// 확인 객체 타입
public enum ObjectType: String, Codable, Sendable, CaseIterable {
    case agent, configuration, agentConfig = "agent_config", mcpServer = "mcp_server", endpoint
    case secretCandidate = "secret_candidate", permissionRule = "permission_rule", file
    case instructionFile = "instruction_file", hook, project, coverageItem = "coverage_item"
}

public struct Provenance: Codable, Equatable, Sendable {
    public let adapter: String
    public let adapterVersion: String
    public let locationAlias: String   // 예: "~/.claude/settings.json" 또는 "<project:alias>/.claude/settings.json"
    public let scopeID: String
    public let precedence: String      // managed > local > project > user, 또는 "n/a"
    public let interpretation: String  // 어댑터가 어떻게 해석했는지 (S1~S5 근거 요약)

    public init(adapter: String, adapterVersion: String, locationAlias: String, scopeID: String, precedence: String, interpretation: String) {
        self.adapter = adapter; self.adapterVersion = adapterVersion; self.locationAlias = locationAlias
        self.scopeID = scopeID; self.precedence = precedence; self.interpretation = interpretation
    }
}

/// 확인 사실 하나.
public struct Observation: Codable, Equatable, Sendable, Identifiable {
    public var id: String { observationID }
    public let observationID: String
    public let objectID: String
    public let objectType: ObjectType
    public let field: String
    public let safeValue: String
    public let valueKind: ValueKind
    public let provenance: Provenance
    /// 로컬 전용 HMAC 지문 (증빙 제외)
    public let secretFingerprint: String?

    public init(objectID: String, objectType: ObjectType, field: String, safeValue: String, valueKind: ValueKind,
                provenance: Provenance, secretFingerprint: String? = nil) {
        self.observationID = Hashing.sha256Hex("\(objectID)\u{1F}\(field)\u{1F}\(provenance.locationAlias)").prefix(24).description
        self.objectID = objectID; self.objectType = objectType; self.field = field
        self.safeValue = safeValue; self.valueKind = valueKind; self.provenance = provenance
        self.secretFingerprint = secretFingerprint
    }
}

public enum Severity: String, Codable, Sendable, Comparable {
    case high, medium, low, gap
    public var rank: Int { switch self { case .high: return 3; case .medium: return 2; case .low: return 1; case .gap: return 0 } }
    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
    public var label: String { switch self { case .high: return "높음"; case .medium: return "중간"; case .low: return "낮음"; case .gap: return "점검 필요" } }
}

public enum Confidence: String, Codable, Sendable { case high, medium, low
    public var label: String { switch self { case .high: return "높음"; case .medium: return "보통"; case .low: return "낮음" } }
}

public enum Outcome: String, Codable, Sendable { case positive, negative, unknown }

/// 룰 판단 결과.
public struct Verdict: Codable, Equatable, Sendable {
    public let ruleID: String
    public let ruleVersion: String
    public let objectID: String
    public let objectType: ObjectType
    public let outcome: Outcome
    public let severity: Severity
    public let confidence: Confidence
    public let title: String
    public let summary: String
    public let evidence: [String]      // observation IDs
    public let limits: String
    public let nextAction: String
    public let scopeID: String
    public let locationAlias: String
    /// 대상 지문: 룰+객체+근거 필드의 해시.
    public var targetFingerprint: String {
        Hashing.sha256Hex("\(ruleID)\u{1F}\(objectID)\u{1F}\(locationAlias)").prefix(32).description
    }
}

public enum FindingState: String, Codable, Sendable, CaseIterable {
    case open, inProgress = "in_progress", resolvedByRescan = "resolved_by_rescan", excepted, falsePositiveReview = "false_positive_review"
    public var label: String {
        switch self {
        case .open: return "미조치"; case .inProgress: return "조치 중"; case .resolvedByRescan: return "다시 점검해 해결됨"
        case .excepted: return "예외"; case .falsePositiveReview: return "잘못된 탐지 검토"
        }
    }
}

public enum ScanStatus: String, Codable, Sendable { case complete, partial, failed, cancelled
    public var label: String { switch self { case .complete: return "완료"; case .partial: return "부분"; case .failed: return "실패"; case .cancelled: return "취소" } }
}

public struct ScanResult: Sendable {
    public let scanID: String
    public let status: ScanStatus
    public let startedAt: String
    public let endedAt: String
    public let scopes: [Scope]
    public let coverage: [Coverage]
    public let observations: [Observation]
    public let verdicts: [Verdict]
    public let adapterVersions: [String: String]
    public let rulesVersion: String
    public let notes: [String]
}
