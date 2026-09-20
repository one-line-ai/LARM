import Foundation

/// 비밀정보 후보 판정.
public enum SecretPatterns {
    public enum Kind: String, Codable, Sendable {
        case knownFormat = "known_format"   // 알려진 토큰 형식
        case highEntropy = "high_entropy"   // 일반 고엔트로피 후보
        case ref                            // ${VAR} 참조: 비밀값 아님
        case none
    }

    /// 키 이름만으로 "비밀값을 담는 자리"로 취급하는 키 (구조 근거).
    public static let sensitiveKeyPattern = try! NSRegularExpression(
        pattern: "(?i)(token|secret|password|passwd|api[_-]?key|apikey|auth|credential|private[_-]?key|bearer|cookie|session)")

    /// 알려진 형식.
    static let known: [(String, NSRegularExpression)] = [
        ("anthropic", re("sk-ant-[A-Za-z0-9_\\-]{20,}")),
        ("openai", re("sk-(proj-|svcacct-)?[A-Za-z0-9_\\-]{20,}")),
        ("github_pat", re("gh[pousr]_[A-Za-z0-9]{36,}")),
        ("github_fine", re("github_pat_[A-Za-z0-9_]{22,}")),
        ("aws_access", re("(AKIA|ASIA)[0-9A-Z]{16}")),
        ("gcp_api", re("AIza[0-9A-Za-z_\\-]{35}")),
        ("slack", re("xox[abposr]-[0-9A-Za-z\\-]{10,}")),
        ("stripe", re("(sk|rk)_(live|test)_[0-9a-zA-Z]{20,}")),
        ("jwt", re("eyJ[A-Za-z0-9_\\-]{8,}\\.eyJ[A-Za-z0-9_\\-]{8,}\\.[A-Za-z0-9_\\-]{8,}")),
        ("pem", re("-----BEGIN [A-Z ]*PRIVATE KEY-----")),
        ("npm", re("npm_[A-Za-z0-9]{36}")),
        ("huggingface", re("hf_[A-Za-z0-9]{30,}")),
        ("notion", re("(secret_|ntn_)[A-Za-z0-9]{40,}")),
        ("larm_canary", re("LARM_CANARY_[A-Za-z0-9]{8,}")),
    ]

    static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    public static let refPattern = re("^\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?$")

    public static func isSensitiveKey(_ key: String) -> Bool {
        sensitiveKeyPattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    public static func isReference(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        return refPattern.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) != nil
    }

    /// 값 자체를 검사한다.
    public static func classify(value: String, key: String) -> (Kind, String) {
        if isReference(value) { return (.ref, "variable_reference") }
        for (name, r) in known where r.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
            return (.knownFormat, name)
        }
        if isSensitiveKey(key), value.count >= 16, shannonEntropy(value) >= 3.5, !value.contains(" ") {
            return (.highEntropy, "high_entropy_in_sensitive_key")
        }
        if value.count >= 32, value.count <= 200, !value.contains(" "), !value.contains("/"), shannonEntropy(value) >= 4.5 {
            return (.highEntropy, "high_entropy")
        }
        return (.none, "")
    }

    public static func shannonEntropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0.0) { acc, c in let p = Double(c) / n; return acc - p * log2(p) }
    }
}

/// 값 제거기.
public struct Redactor: Sendable {
    public let hmacKey: Data
    public init(hmacKey: Data) { self.hmacKey = hmacKey }

    public struct Result: Sendable {
        public let safeValue: String
        public let kind: ValueKind
        public let secretKind: SecretPatterns.Kind
        public let format: String
        public let fingerprint: String?
    }

    /// 문자열 값을 안전한 요약으로 바꾼다.
    public func redact(value: String, key: String) -> Result {
        let (kind, fmt) = SecretPatterns.classify(value: value, key: key)
        switch kind {
        case .ref:
            return Result(safeValue: "참조 \(value.prefix(48))", kind: .ref, secretKind: .ref, format: fmt, fingerprint: nil)
        case .knownFormat, .highEntropy:
            return Result(safeValue: "[제거됨: 평문 후보 \(fmt), 길이 \(value.count)]", kind: .redacted, secretKind: kind, format: fmt,
                          fingerprint: Hashing.hmacHex(Data(value.utf8), key: hmacKey))
        case .none:
            if SecretPatterns.isSensitiveKey(key) {
                return Result(safeValue: "[제거됨: 민감 키 값, 길이 \(value.count)]", kind: .redacted, secretKind: .none, format: "sensitive_key",
                              fingerprint: Hashing.hmacHex(Data(value.utf8), key: hmacKey))
            }
            return Result(safeValue: String(value.prefix(200)), kind: .literal, secretKind: .none, format: "", fingerprint: nil)
        }
    }

    /// 오류 문자열·경로 등 임의 텍스트에서 알려진 형식을 제거한다 (로그·진단용).
    public static func scrub(_ text: String) -> String {
        var out = text
        for (_, r) in SecretPatterns.known {
            out = r.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "[제거됨]")
        }
        return out
    }
}
