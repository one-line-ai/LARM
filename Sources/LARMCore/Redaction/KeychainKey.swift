import Foundation
import Security

/// 설치별 HMAC 키.
public enum KeychainKey {
    public static let service = "com.onelineai.larm"
    public static let account = "install-hmac-key"

    public struct Material {
        public let keyID: String
        public let key: Data
    }

    public enum KeyError: Error, CustomStringConvertible {
        case keychain(OSStatus)
        case corrupt
        public var description: String {
            switch self {
            case .keychain(let s): return "Keychain 오류 \(s): \(SecCopyErrorMessageString(s, nil) as String? ?? "")"
            case .corrupt: return "Keychain 항목이 손상되었음"
            }
        }
    }

    /// 격리 데이터 폴더(LARM_DATA_DIR)를 쓰는 시험·시연 실행에서는 Keychain 대신 그 폴더의 파일 키(0600)를 쓴다.
    /// 실제 사용자 데이터 폴더에서는 항상 Keychain이다.
    static var isolatedKeyURL: URL? {
        guard let d = ProcessInfo.processInfo.environment["LARM_DATA_DIR"], !d.isEmpty else { return nil }
        return URL(fileURLWithPath: d, isDirectory: true).appendingPathComponent("hmac.key")
    }

    /// 기존 키를 읽거나 새로 만든다.
    public static func loadOrCreate() throws -> Material {
        if let u = isolatedKeyURL {
            if let d = try? Data(contentsOf: u), d.count == 32 { return Material(keyID: keyID(for: d), key: d) }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw KeyError.keychain(errSecInternalError) }
            let key = Data(bytes)
            try key.write(to: u, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
            return Material(keyID: keyID(for: key), key: key)
        }
        if let existing = try load() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard rc == errSecSuccess else { throw KeyError.keychain(rc) }
        let key = Data(bytes)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "LARM 설치 키 (비밀정보 요약값용)",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key,
        ]
        let st = SecItemAdd(attrs as CFDictionary, nil)
        guard st == errSecSuccess else { throw KeyError.keychain(st) }
        return Material(keyID: keyID(for: key), key: key)
    }

    public static func load() throws -> Material? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return nil }
        guard st == errSecSuccess else { throw KeyError.keychain(st) }
        guard let d = out as? Data, d.count == 32 else { throw KeyError.corrupt }
        return Material(keyID: keyID(for: d), key: d)
    }

    /// 전체 초기화용.
    public static func delete() throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let st = SecItemDelete(q as CFDictionary)
        guard st == errSecSuccess || st == errSecItemNotFound else { throw KeyError.keychain(st) }
    }

    static func keyID(for key: Data) -> String {
        String(Hashing.sha256Hex(key).prefix(16))
    }
}
