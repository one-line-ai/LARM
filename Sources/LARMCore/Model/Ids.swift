import Foundation

/// 식별자 생성.
public enum Ids {
    public static func new(_ prefix: String) -> String {
        prefix + "_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }
}

/// UTC ISO 8601 + 사용자 시간대 병기.
public enum Clock {
    public static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    public static func nowUTC() -> String { iso.string(from: Date()) }
    public static func utc(_ d: Date) -> String { iso.string(from: d) }
    public static func parse(_ s: String) -> Date? { iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) }
    public static var localTimeZoneID: String { TimeZone.current.identifier }
}
