import Foundation

/// 갤럭시 지도 페이지가 읽는 JSON 형태. 비밀값·실제 경로는 관측값 단계에서 이미 제거되어 있다.
public enum GraphExport {
    public static func json(_ g: Graph, scopes: [Scope], findings: [Finding]) throws -> String {
        let alias = Dictionary(scopes.map { ($0.scopeID, $0.kind == .userRoot ? "user" : $0.alias) }, uniquingKeysWith: { a, _ in a })
        let findingByNode = Dictionary(findings.map { ("finding:\($0.findingID)", $0.findingID) }, uniquingKeysWith: { a, _ in a })
        let nodes: [[String: Any]] = g.nodes.map { n in
            var d: [String: Any] = ["id": n.id, "type": n.type.rawValue, "label": n.label, "scope": alias[n.scopeID] ?? n.scopeID, "attrs": n.attrs]
            if let s = n.severity { d["severity"] = s }
            if let s = n.state { d["state"] = s }
            if let f = findingByNode[n.id] { d["findingID"] = f }
            return d
        }
        let edges: [[String: Any]] = g.edges.map { ["type": $0.type.rawValue, "from": $0.from, "to": $0.to, "epistemic": $0.epistemic.rawValue] }
        let data = try JSONSerialization.data(withJSONObject: ["real": ["nodes": nodes, "edges": edges]], options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
