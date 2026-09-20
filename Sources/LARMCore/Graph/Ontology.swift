import Foundation

/// 근거 기반 온톨로지.
public enum Ontology {
    public static let version = "larm-ontology/1.1"

    public enum NodeType: String, Codable, Sendable, CaseIterable {
        case device = "Device", agent = "Agent", project = "Project", configuration = "Configuration", mcpServer = "MCPServer"
        case endpoint = "Endpoint", secretCandidate = "SecretCandidate", finding = "Finding", rule = "Rule", evidence = "Evidence"
        case permissionRule = "PermissionRule", hook = "Hook", instructionFile = "InstructionFile", file = "File"
        case session = "Session", process = "Process", toolRequest = "ToolRequest", actionResult = "ActionResult", resource = "Resource"
        case decision = "Decision", coverageGap = "CoverageGap"
    }

    public enum EdgeType: String, Codable, Sendable, CaseIterable {
        case hasConfiguration = "HAS_CONFIGURATION", scopedTo = "SCOPED_TO", declaresMCP = "DECLARES_MCP", pointsTo = "POINTS_TO"
        case hasCandidate = "HAS_CANDIDATE", hasFinding = "HAS_FINDING", evaluatedBy = "EVALUATED_BY", supportedBy = "SUPPORTED_BY"
        case declaresRule = "DECLARES_RULE", declaresHook = "DECLARES_HOOK", hasInstruction = "HAS_INSTRUCTION", storedIn = "STORED_IN"
        case requested = "REQUESTED", targets = "TARGETS", hasResult = "HAS_RESULT", executed = "EXECUTED", deniedConfirmed = "DENIED_CONFIRMED"
        case hasCoverageGap = "HAS_COVERAGE_GAP", hasDecision = "HAS_DECISION"
    }

    /// (관계, 출발, 도착) 허용 목록
    public static let allowed: [EdgeType: [(NodeType, NodeType)]] = [
        .hasConfiguration: [(.agent, .configuration)],
        .scopedTo: [(.configuration, .project), (.configuration, .device)],
        .declaresMCP: [(.configuration, .mcpServer)],
        .pointsTo: [(.mcpServer, .endpoint), (.configuration, .endpoint)],
        .hasCandidate: [(.configuration, .secretCandidate), (.mcpServer, .secretCandidate)],
        .hasFinding: [(.configuration, .finding), (.mcpServer, .finding), (.endpoint, .finding), (.secretCandidate, .finding),
                      (.permissionRule, .finding), (.hook, .finding), (.file, .finding), (.agent, .finding), (.coverageGap, .finding)],
        .evaluatedBy: [(.finding, .rule)],
        .supportedBy: [(.finding, .evidence), (.configuration, .evidence), (.toolRequest, .evidence), (.actionResult, .evidence), (.decision, .evidence), (.coverageGap, .evidence)],
        .declaresRule: [(.configuration, .permissionRule)],
        .declaresHook: [(.configuration, .hook)],
        .hasInstruction: [(.project, .instructionFile), (.agent, .instructionFile)],
        .storedIn: [(.configuration, .file), (.secretCandidate, .file)],
        .requested: [(.agent, .toolRequest), (.session, .toolRequest)],
        .targets: [(.toolRequest, .resource)],
        .hasResult: [(.toolRequest, .actionResult)],
        .executed: [(.actionResult, .resource)],
        .deniedConfirmed: [(.decision, .toolRequest)],
        .hasCoverageGap: [(.agent, .coverageGap), (.device, .coverageGap)],
        .hasDecision: [(.finding, .decision)],
    ]

    public static func isAllowed(_ e: EdgeType, from: NodeType, to: NodeType) -> Bool {
        allowed[e]?.contains { $0.0 == from && $0.1 == to } ?? false
    }

    public static func nodeType(for o: ObjectType) -> NodeType {
        switch o {
        case .agent: return .agent; case .configuration: return .configuration; case .agentConfig: return .configuration
        case .mcpServer: return .mcpServer; case .endpoint: return .endpoint; case .secretCandidate: return .secretCandidate
        case .permissionRule: return .permissionRule; case .file: return .file; case .instructionFile: return .instructionFile
        case .hook: return .hook; case .project: return .project; case .coverageItem: return .coverageGap
        }
    }
}

public struct GraphNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: Ontology.NodeType
    public let label: String
    public let scopeID: String
    public var severity: String?
    public var state: String?
    public var attrs: [String: String]
}

public struct GraphEdge: Codable, Equatable, Sendable, Identifiable {
    public enum Epistemic: String, Codable, Sendable { case observed, derived, userAsserted = "user_asserted" }
    public let id: String
    public let type: Ontology.EdgeType
    public let from: String
    public let to: String
    public let evidenceRef: [String]
    public let scanID: String
    public let epistemic: Epistemic
    public let confidence: String
    public let schemaVersion: String
}

public struct Graph: Codable, Equatable, Sendable {
    public let ontologyVersion: String
    public let scanID: String
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var rejected: [String]   // 거부된 간선 사유 (타입 위반·근거 없음)
}
