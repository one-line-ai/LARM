import Foundation

/// 구성 변경 비교.
public struct DiffEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Change: String, Codable, Sendable { case added, removed, modified, incomparable }
    public var id: String { "\(objectID)|\(field)|\(change.rawValue)" }
    public let objectID: String
    public let objectType: ObjectType
    public let field: String
    public let change: Change
    public let before: String?
    public let after: String?
    public let locationAlias: String
    public let secretChanged: Bool
    public let reason: String
}

public enum Differ {
    public static func diff(from: [Observation], fromCoverage: [Coverage], to: [Observation], toCoverage: [Coverage],
                            fromScopes: Set<String>, toScopes: Set<String>) -> [DiffEntry] {
        func key(_ o: Observation) -> String { "\(o.objectID)\u{1F}\(o.field)" }
        let a = Dictionary(from.filter { !Digest.derivedFields.contains($0.field) }.map { (key($0), $0) }, uniquingKeysWith: { _, b in b })
        let b = Dictionary(to.filter { !Digest.derivedFields.contains($0.field) }.map { (key($0), $0) }, uniquingKeysWith: { _, b in b })
        let toStatus: [String: CoverageStatus] = Dictionary(toCoverage.map { ($0.itemAlias, $0.status) }, uniquingKeysWith: { x, _ in x })
        var out: [DiffEntry] = []
        var removedScopes: [String: Int] = [:]
        for (k, o) in b where a[k] == nil {
            out.append(DiffEntry(objectID: o.objectID, objectType: o.objectType, field: o.field, change: .added, before: nil, after: o.safeValue,
                                 locationAlias: o.provenance.locationAlias, secretChanged: false, reason: "새 관측"))
        }
        for (k, o) in a {
            if let n = b[k] {
                let secretChanged = o.secretFingerprint != n.secretFingerprint && (o.secretFingerprint != nil || n.secretFingerprint != nil)
                if o.safeValue != n.safeValue || o.valueKind != n.valueKind || secretChanged {
                    out.append(DiffEntry(objectID: o.objectID, objectType: o.objectType, field: o.field, change: .modified,
                                         before: o.valueKind == .redacted ? "[제거됨]" : o.safeValue, after: n.valueKind == .redacted ? "[제거됨]" : n.safeValue,
                                         locationAlias: n.provenance.locationAlias, secretChanged: secretChanged,
                                         reason: secretChanged ? "비밀값 요약값 변경 (원문 미표시)" : "값 변경"))
                }
            } else {
                let base = String(o.provenance.locationAlias.split(separator: " ").first ?? Substring(o.provenance.locationAlias))
                let st = toStatus[o.provenance.locationAlias] ?? toStatus[base]
                if !toScopes.contains(o.provenance.scopeID) {
                    removedScopes[o.provenance.scopeID, default: 0] += 1
                } else if let st, st == .success || st == .absent {
                    out.append(entry(o, .removed, st == .absent ? "파일 부재 확인" : "정상 읽기에서 부재 확인"))
                } else if let st {
                    out.append(entry(o, .incomparable, "읽기 실패(\(st.rawValue))는 삭제로 처리하지 않음"))
                } else {
                    out.append(entry(o, .incomparable, "대상 파일을 이번 점검에서 확인하지 못함"))
                }
            }
        }
        for (scope, n) in removedScopes {
            out.append(DiffEntry(objectID: "scope:\(scope)", objectType: .project, field: "scope", change: .incomparable, before: "\(n)개 항목", after: nil,
                                 locationAlias: scope, secretChanged: false, reason: "범위가 제거되어 \(n)개 항목을 비교할 수 없음"))
        }
        return out.sorted { ($0.objectID, $0.field) < ($1.objectID, $1.field) }
    }

    static func entry(_ o: Observation, _ c: DiffEntry.Change, _ reason: String) -> DiffEntry {
        DiffEntry(objectID: o.objectID, objectType: o.objectType, field: o.field, change: c, before: o.valueKind == .redacted ? "[제거됨]" : o.safeValue,
                  after: nil, locationAlias: o.provenance.locationAlias, secretChanged: false, reason: reason)
    }

    /// 기준점 대비 객체 상태.
    public static func baselineStatus(current: [Observation], baseline: [Observation]) -> [String: String] {
        func fields(_ obs: [Observation]) -> [String: [String: String]] {
            var m: [String: [String: String]] = [:]
            for o in obs where !Digest.derivedFields.contains(o.field) {
                m[o.objectID, default: [:]][o.field] = (o.valueKind == .redacted ? "fp:" + (o.secretFingerprint ?? "") : o.safeValue)
            }
            return m
        }
        let c = fields(current), b = fields(baseline)
        var out: [String: String] = [:]
        for (id, f) in c {
            guard let bf = b[id] else { out[id] = "new"; continue }
            out[id] = f == bf ? "unchanged" : "changed"
        }
        return out
    }
}
