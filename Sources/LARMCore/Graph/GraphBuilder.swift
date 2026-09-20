import Foundation

/// 관측·발견 사항으로 그래프를 만든다.
public struct GraphBuilder {
    public init() {}

    public func build(observations: [Observation], findings: [Finding], scopes: [Scope], scanID: String) -> Graph {
        var nodes: [String: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var rejected: [String] = []
        var byObject: [String: [Observation]] = [:]
        for o in observations { byObject[o.objectID, default: []].append(o) }

        nodes["device:local"] = GraphNode(id: "device:local", type: .device, label: "이 Mac", scopeID: "scope_user", attrs: [:])
        for s in scopes where s.kind == .project {
            nodes["project:\(s.scopeID)"] = GraphNode(id: "project:\(s.scopeID)", type: .project, label: s.alias, scopeID: s.scopeID, attrs: [:])
        }
        for (oid, obs) in byObject {
            guard let first = obs.first else { continue }
            var attrs: [String: String] = [:]
            for o in obs where o.valueKind != .redacted && o.field != "in_file" { attrs[o.field] = o.safeValue }
            let label: String
            switch first.objectType {
            case .agent: label = attrs["install_status"].map { "\(oid.dropFirst(6)) (\($0))" } ?? String(oid.dropFirst(6))
            case .mcpServer: label = attrs["name"] ?? oid
            case .endpoint: label = "\(attrs["scheme"] ?? "")://\(attrs["host"] ?? ""):\(attrs["port"] ?? "")"
            case .secretCandidate: label = "비밀정보 후보 (\(attrs["format"] ?? attrs["kind"] ?? ""))"
            case .configuration, .agentConfig: label = attrs["location"] ?? first.provenance.locationAlias
            case .permissionRule: label = attrs["rule_safe"] ?? oid
            case .hook: label = "\(attrs["event"] ?? "hook"):\(attrs["command_basename"] ?? "")"
            case .instructionFile, .file: label = first.provenance.locationAlias
            default: label = oid
            }
            if first.objectType == .secretCandidate { attrs = attrs.filter { ["kind", "format", "key_path", "value_kind"].contains($0.key) } }
            nodes[oid] = GraphNode(id: oid, type: Ontology.nodeType(for: first.objectType), label: label, scopeID: first.provenance.scopeID, attrs: attrs)
        }

        func add(_ type: Ontology.EdgeType, _ from: String, _ to: String, evidence: [String], epistemic: GraphEdge.Epistemic = .observed, confidence: String = "high") {
            guard let f = nodes[from], let t = nodes[to] else { rejected.append("\(type.rawValue) \(from)→\(to): 노드 없음"); return }
            guard Ontology.isAllowed(type, from: f.type, to: t.type) else { rejected.append("\(type.rawValue) \(f.type.rawValue)→\(t.type.rawValue): 타입 위반"); return }
            guard !evidence.isEmpty else { rejected.append("\(type.rawValue) \(from)→\(to): 근거 없음"); return }
            guard f.scopeID == "scope_user" || t.scopeID == "scope_user" || f.scopeID == t.scopeID || t.type == .rule || t.type == .finding || f.type == .finding else {
                rejected.append("\(type.rawValue) \(from)→\(to): 다른 범위 연결"); return
            }
            edges.append(GraphEdge(id: Hashing.sha256Hex("\(type.rawValue)|\(from)|\(to)").prefix(20).description, type: type, from: from, to: to,
                                   evidenceRef: evidence, scanID: scanID, epistemic: epistemic, confidence: confidence, schemaVersion: Ontology.version))
        }

        let cfgByLocation: [String: String] = Dictionary(byObject.compactMap { (oid, obs) -> (String, String)? in
            guard obs.first?.objectType == .configuration, let loc = obs.first(where: { $0.field == "location" })?.safeValue else { return nil }
            return (loc, oid)
        }, uniquingKeysWith: { a, _ in a })

        for (oid, obs) in byObject {
            guard let first = obs.first else { continue }
            let ev = obs.map { $0.observationID }
            switch first.objectType {
            case .configuration:
                if let agent = obs.first(where: { $0.field == "agent" })?.safeValue { add(.hasConfiguration, "agent:\(agent)", oid, evidence: ev) }
                let scope = first.provenance.scopeID
                add(.scopedTo, oid, scope == "scope_user" ? "device:local" : "project:\(scope)", evidence: ev, epistemic: .derived)
                add(.storedIn, oid, "file:\(first.provenance.locationAlias)", evidence: ev, epistemic: .derived)
            case .agentConfig:
                if let agent = oid.split(separator: ":").dropFirst().first { add(.hasConfiguration, "agent:\(agent)", oid, evidence: ev, epistemic: .derived) }
            case .mcpServer:
                if let loc = obs.first(where: { $0.field == "declared_in" })?.safeValue, let cfg = cfgByLocation[loc] { add(.declaresMCP, cfg, oid, evidence: ev) }
                if let ep = obs.first(where: { $0.field == "endpoint" })?.safeValue, ep.hasPrefix("ep:") { add(.pointsTo, oid, ep, evidence: ev) }
            case .endpoint:
                if let ref = obs.first(where: { $0.field == "referenced_by" })?.safeValue, ref.hasPrefix("cfg:") {
                    add(.pointsTo, String(ref.split(separator: " ").first ?? ""), oid, evidence: ev)
                }
            case .secretCandidate:
                let parts = oid.dropFirst(7)
                if let range = parts.range(of: ":", options: .backwards) {
                    var cfg = String(parts[..<range.lowerBound])
                    while nodes[cfg] == nil, let r2 = cfg.range(of: ":", options: .backwards) { cfg = String(cfg[..<r2.lowerBound]) }
                    add(.hasCandidate, cfg, oid, evidence: ev)
                }
                add(.storedIn, oid, "file:\(first.provenance.locationAlias)", evidence: ev, epistemic: .derived)
            case .permissionRule:
                let cfg = String(oid.dropFirst(5).split(separator: ":").dropLast().joined(separator: ":"))
                add(.declaresRule, nodes[cfg] != nil ? cfg : cfgByLocation[first.provenance.locationAlias] ?? cfg, oid, evidence: ev)
            case .hook:
                add(.declaresHook, cfgByLocation[first.provenance.locationAlias] ?? "", oid, evidence: ev)
            case .instructionFile:
                let scope = first.provenance.scopeID
                add(.hasInstruction, scope == "scope_user" ? "agent:\(first.provenance.adapter)" : "project:\(scope)", oid, evidence: ev)
            default: break
            }
        }
        for f in findings where f.state != .resolvedByRescan {
            let fid = "finding:\(f.findingID)"
            nodes[fid] = GraphNode(id: fid, type: .finding, label: "\(f.ruleID) \(f.title)", scopeID: f.scopeID, severity: f.severity.rawValue, state: f.state.rawValue, attrs: ["summary": f.summary])
            let rid = "rule:\(f.ruleID)@\(f.ruleVersion)"
            if nodes[rid] == nil { nodes[rid] = GraphNode(id: rid, type: .rule, label: "\(f.ruleID) v\(f.ruleVersion)", scopeID: "scope_user", attrs: [:]) }
            let ev = f.evidence.isEmpty ? ["scan:\(f.lastScanID)"] : f.evidence
            if nodes[f.objectID] != nil { add(.hasFinding, f.objectID, fid, evidence: ev) }
            else if f.objectType == .coverageItem {
                nodes[f.objectID] = GraphNode(id: f.objectID, type: .coverageGap, label: f.locationAlias, scopeID: f.scopeID, attrs: [:])
                add(.hasFinding, f.objectID, fid, evidence: ev)
            }
            add(.evaluatedBy, fid, rid, evidence: ev, epistemic: .derived)
        }
        return Graph(ontologyVersion: Ontology.version, scanID: scanID, nodes: nodes.values.sorted { $0.id < $1.id }, edges: edges.sorted { $0.id < $1.id }, rejected: rejected)
    }
}
