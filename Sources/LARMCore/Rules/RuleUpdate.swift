import Foundation
import CryptoKit

/// 어댑터·룰 갱신 패키지.
/// 룰은 데이터이며 셸·스크립트를 담을 수 없다.
public enum RuleUpdate {
    /// 배포 공개키 (raw 32바이트 hex).
    public static var publicKeyHex = "0000000000000000000000000000000000000000000000000000000000000000"

    public struct Package: Sendable {
        public let version: String
        public let schema: String
        public let rulesJSON: Data
        public let signatureHex: String
    }

    public enum UpdateError: Error, CustomStringConvertible, Equatable {
        case badSignature, unsupportedSchema(String), notNewer(String, String), invalidRules(String), containsExecutable
        public var description: String {
            switch self {
            case .badSignature: return "서명이 유효하지 않아 갱신을 거부했음 (변조 또는 다른 키)."
            case .unsupportedSchema(let s): return "미지원 점검 규칙 형식 \(s)."
            case .notNewer(let a, let b): return "오래된 버전임 (현재 \(a), 패키지 \(b))."
            case .invalidRules(let s): return "점검 규칙 파일 오류: \(s)"
            case .containsExecutable: return "점검 규칙 데이터에 실행 구문이 포함되어 거부했음."
            }
        }
    }

    /// 패키지 형식: ZIP(rules.json, manifest.json{version,schema,sha256}, signature.hex = Ed25519(manifest bytes))
    public static func parse(zip: Data) throws -> Package {
        let headers = try ZipReader.centralDirectory(zip)
        func file(_ n: String) throws -> Data {
            guard let h = headers.first(where: { $0.path == n }) else { throw UpdateError.invalidRules("\(n) 없음") }
            return try ZipReader.extract(zip, h)
        }
        let manifest = try file("manifest.json"), rules = try file("rules.json"), sig = try file("signature.hex")
        guard let m = try SafeJSON.parse(manifest) as? [String: Any], let v = m["version"] as? String, let s = m["schema"] as? String, let sha = m["sha256"] as? String else {
            throw UpdateError.invalidRules("manifest 형식")
        }
        guard Hashing.sha256Hex(rules) == sha.lowercased() else { throw UpdateError.invalidRules("rules.json 해시 불일치") }
        let sigHex = String(decoding: sig, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard verify(message: manifest, signatureHex: sigHex, publicKeyHex: publicKeyHex) else { throw UpdateError.badSignature }
        return Package(version: v, schema: s, rulesJSON: rules, signatureHex: sigHex)
    }

    public static func verify(message: Data, signatureHex: String, publicKeyHex: String) -> Bool {
        guard let pk = Data(hex: publicKeyHex), let sig = Data(hex: signatureHex), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pk) else { return false }
        return key.isValidSignature(sig, for: message)
    }

    /// 호환성 검사: schema 지원, 버전 증가, 룰 디코딩 성공, 실행 구문 없음
    public static func validate(_ p: Package, currentVersion: String) throws -> RuleSet {
        guard p.schema == RuleLoader.supportedSchema else { throw UpdateError.unsupportedSchema(p.schema) }
        guard isNewer(p.version, than: currentVersion) else { throw UpdateError.notNewer(currentVersion, p.version) }
        let text = String(decoding: p.rulesJSON, as: UTF8.self)
        for bad in ["\"command\"", "\"shell\"", "$(", "`", "exec(", "eval("] where text.contains(bad) { throw UpdateError.containsExecutable }
        do { return try RuleLoader.load(p.rulesJSON) } catch { throw UpdateError.invalidRules("\(error)") }
    }

    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// 원자적 설치: <dir>/rules-<version>.json 작성 후 current.json 심볼릭 링크 교체.
    public static func install(_ set: RuleSet, json: Data, into dir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = dir.appendingPathComponent("rules-\(set.version).json")
        try json.write(to: target, options: .atomic)
        Paths.restrict(target)
        let tmpLink = dir.appendingPathComponent(".current.tmp")
        try? fm.removeItem(at: tmpLink)
        try fm.createSymbolicLink(atPath: tmpLink.path, withDestinationPath: target.lastPathComponent)
        guard rename(tmpLink.path, dir.appendingPathComponent("current.json").path) == 0 else { throw UpdateError.invalidRules("전환 실패") }
        return target
    }

    /// 되돌리기: 마지막 검증 버전(직전 파일)으로 current.json을 교체
    public static func rollback(in dir: URL, to version: String) throws {
        let target = dir.appendingPathComponent("rules-\(version).json")
        guard FileManager.default.fileExists(atPath: target.path) else { throw UpdateError.invalidRules("이전 버전 파일 없음") }
        let tmpLink = dir.appendingPathComponent(".current.tmp")
        try? FileManager.default.removeItem(at: tmpLink)
        try FileManager.default.createSymbolicLink(atPath: tmpLink.path, withDestinationPath: target.lastPathComponent)
        guard rename(tmpLink.path, dir.appendingPathComponent("current.json").path) == 0 else { throw UpdateError.invalidRules("전환 실패") }
    }

    /// 로딩: current.json이 있고 검증되면 그것, 아니면 번들 룰.
    public static func loadCurrent(dir: URL) -> (RuleSet?, String) {
        let cur = dir.appendingPathComponent("current.json")
        guard let d = try? Data(contentsOf: cur) else { return (nil, "설치된 갱신 없음") }
        do { let s = try RuleLoader.load(d); return (s, "갱신 점검 규칙 \(s.version)") } catch { return (nil, "설치된 갱신 점검 규칙 손상: \(error)") }
    }
}

extension Data {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.count % 2 == 0 else { return nil }
        var d = Data(capacity: h.count / 2)
        var i = h.startIndex
        while i < h.endIndex {
            let j = h.index(i, offsetBy: 2)
            guard let b = UInt8(h[i..<j], radix: 16) else { return nil }
            d.append(b); i = j
        }
        self = d
    }
}
