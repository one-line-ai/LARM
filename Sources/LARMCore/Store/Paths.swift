import Foundation

/// 앱 데이터 위치.
public enum Paths {
    public static let appName = "LARM"

    /// 사용자 홈. 시험·시연용으로 LARM_HOME 환경 변수로 바꿀 수 있다 (실제 사용자 데이터를 건드리지 않고 fixture 홈을 점검).
    public static var home: String {
        if let h = ProcessInfo.processInfo.environment["LARM_HOME"], !h.isEmpty { return h }
        return NSHomeDirectory()
    }
    public static var supportDir: URL {
        if let d = ProcessInfo.processInfo.environment["LARM_DATA_DIR"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }
    public static var dbURL: URL { supportDir.appendingPathComponent("larm.sqlite") }
    public static var spoolDir: URL { supportDir.appendingPathComponent("spool", isDirectory: true) }
    public static var socketURL: URL { supportDir.appendingPathComponent("hook.sock") }
    public static var scopeMapURL: URL { supportDir.appendingPathComponent("scopes.json") }

    @discardableResult
    public static func ensureDirs() throws -> URL {
        let fm = FileManager.default
        for dir in [supportDir, spoolDir] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            }
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        return supportDir
    }

    public static func restrict(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
