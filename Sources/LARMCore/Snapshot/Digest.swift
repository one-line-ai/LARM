import Foundation

/// 내용 비교용 digest.
public enum Digest {
    static let derivedFields: Set<String> = ["baseline_status", "reviewed"]

    public static func content(_ obs: [Observation], scopes: [Scope], adapterVersions: [String: String]) -> String {
        var lines = obs.filter { !derivedFields.contains($0.field) }.map { o -> String in
            let v = o.valueKind == .redacted ? "redacted" : o.safeValue
            return "\(o.objectID)\u{1F}\(o.field)\u{1F}\(o.valueKind.rawValue)\u{1F}\(v)"
        }
        lines.sort()
        lines.append("scopes=" + scopes.map { $0.scopeID }.sorted().joined(separator: ","))
        lines.append("adapters=" + adapterVersions.sorted { $0.key < $1.key }.map { "\($0.key)@\($0.value)" }.joined(separator: ","))
        return Hashing.sha256Hex(lines.joined(separator: "\n"))
    }

    /// 로컬 전용.
    public static func secrets(_ obs: [Observation]) -> String {
        let lines = obs.compactMap { o -> String? in
            guard let fp = o.secretFingerprint else { return nil }
            return "\(o.objectID)\u{1F}\(o.field)\u{1F}\(fp)"
        }.sorted()
        return Hashing.sha256Hex(lines.joined(separator: "\n"))
    }

    public static func scopeDigest(_ scopes: [Scope]) -> String {
        Hashing.sha256Hex(scopes.map { $0.scopeID }.sorted().joined(separator: ",")).prefix(16).description
    }
}
