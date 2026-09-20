import Foundation
import CryptoKit

public enum Hashing {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func sha256Hex(_ s: String) -> String { sha256Hex(Data(s.utf8)) }

    /// 설치별 키 기반 HMAC 지문.
    public static func hmacHex(_ data: Data, key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
