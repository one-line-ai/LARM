import Foundation

/// 앱 데이터 위치.
public enum Paths {
    public static let appName = "LARM"

    public static var supportDir: URL {
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
