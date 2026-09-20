import Foundation

public enum AppInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    public static var bundleID: String? { Bundle.main.bundleIdentifier }
    public static var osBuild: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    public static var isBundled: Bool { bundleID != nil }
}
