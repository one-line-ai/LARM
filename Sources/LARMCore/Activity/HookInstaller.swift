import Foundation

/// Claude Code hook 등록·제거.
public enum HookInstaller {
    public static let events = ["PreToolUse", "PostToolUse", "SessionStart", "SessionEnd"]
    public static let markerFragment = "/LARM.app/Contents/MacOS/larm-hook"

    public struct Plan: Sendable, Equatable {
        public let before: String
        public let after: String
        public let diff: String
        public let alreadyInstalled: Bool
        public let changed: Bool
    }

    public static func isLARM(_ hook: [String: Any]) -> Bool { (hook["command"] as? String)?.contains(markerFragment) ?? false }

    static func settingsObject(_ text: String) throws -> [String: Any] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let o = try SafeJSON.parse(Data(text.utf8)) as? [String: Any] else { throw ParseError.invalid("settings.json 최상위가 객체가 아님") }
        return o
    }

    static func render(_ obj: [String: Any]) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: d, as: UTF8.self) + "\n"
    }

    public static func isInstalled(settingsText: String) -> Bool {
        guard let o = try? settingsObject(settingsText), let hooks = o["hooks"] as? [String: Any] else { return false }
        for (_, v) in hooks { for m in (v as? [[String: Any]] ?? []) { for h in (m["hooks"] as? [[String: Any]] ?? []) where isLARM(h) { return true } } }
        return false
    }

    /// 설치 계획: 각 이벤트에 LARM 항목(마커 = 명령 경로)을 하나씩 추가.
    public static func planInstall(settingsText: String, hookPath: String) throws -> Plan {
        var o = try settingsObject(settingsText)
        var hooks = o["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for e in events {
            var matchers = hooks[e] as? [[String: Any]] ?? []
            let has = matchers.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isLARM) }
            if !has {
                matchers.append(["matcher": "", "hooks": [["type": "command", "command": "\(hookPath) \(e)", "timeout": 5]]])
                hooks[e] = matchers
                changed = true
            }
        }
        o["hooks"] = hooks
        let after = try render(o)
        return Plan(before: settingsText, after: after, diff: unifiedDiff(settingsText, after), alreadyInstalled: !changed, changed: changed)
    }

    /// 제거 계획: 마커 항목만 제거.
    public static func planRemove(settingsText: String) throws -> Plan {
        var o = try settingsObject(settingsText)
        guard var hooks = o["hooks"] as? [String: Any] else {
            return Plan(before: settingsText, after: settingsText, diff: "", alreadyInstalled: false, changed: false)
        }
        var changed = false
        for (e, v) in hooks {
            guard var matchers = v as? [[String: Any]] else { continue }
            matchers = matchers.compactMap { m in
                var m = m
                let inner = (m["hooks"] as? [[String: Any]] ?? [])
                let kept = inner.filter { !isLARM($0) }
                if kept.count != inner.count { changed = true }
                if kept.isEmpty && inner.count > kept.count { return nil }
                m["hooks"] = kept
                return m
            }
            if matchers.isEmpty { hooks.removeValue(forKey: e) } else { hooks[e] = matchers }
        }
        if hooks.isEmpty { o.removeValue(forKey: "hooks") } else { o["hooks"] = hooks }
        let after = changed ? try render(o) : settingsText
        return Plan(before: settingsText, after: after, diff: changed ? unifiedDiff(settingsText, after) : "", alreadyInstalled: changed, changed: changed)
    }

    /// 원자적 쓰기: 임시 파일 + rename, 기존 모드 보존.
    public static func apply(_ plan: Plan, to path: String) throws {
        let fm = FileManager.default
        let current = fm.fileExists(atPath: path) ? (try String(contentsOfFile: path, encoding: .utf8)) : ""
        guard current == plan.before else { throw NSError(domain: "LARM", code: 409, userInfo: [NSLocalizedDescriptionKey: "설정 파일이 계획 이후 바뀌었습니다. 다시 확인하세요."]) }
        let mode = (try? fm.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? 0o600
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        let tmp = dir + "/.settings.json.larm-\(UUID().uuidString.prefix(8))"
        guard fm.createFile(atPath: tmp, contents: Data(plan.after.utf8), attributes: [.posixPermissions: mode]) else { throw NSError(domain: "LARM", code: 500, userInfo: [NSLocalizedDescriptionKey: "임시 파일 생성 실패"]) }
        guard rename(tmp, path) == 0 else { try? fm.removeItem(atPath: tmp); throw NSError(domain: "LARM", code: 500, userInfo: [NSLocalizedDescriptionKey: "rename 실패 errno \(errno)"]) }
    }

    /// 단순 줄 단위 diff (LCS).
    public static func unifiedDiff(_ a: String, _ b: String) -> String {
        let x = a.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let y = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let n = x.count, m = y.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) { for j in stride(from: m - 1, through: 0, by: -1) {
            dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1]) } }
        var i = 0, j = 0, out: [String] = []
        while i < n && j < m {
            if x[i] == y[j] { out.append("  " + x[i]); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { out.append("- " + x[i]); i += 1 }
            else { out.append("+ " + y[j]); j += 1 }
        }
        while i < n { out.append("- " + x[i]); i += 1 }
        while j < m { out.append("+ " + y[j]); j += 1 }
        return out.joined(separator: "\n")
    }
}
