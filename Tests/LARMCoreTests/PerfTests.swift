import Testing
import Foundation
@testable import LARMCore

/// 성능 하니스.
@Suite struct PerfTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LARM_PERF"] == "1"))
    func fullScanTwentyRunsP95() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("larm-perf-\(UUID().uuidString.prefix(6))")
        let home = root.appendingPathComponent("home").path
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        var mcp: [String: Any] = [:]
        for i in 0..<50 { mcp["srv\(i)"] = ["command": "npx", "args": ["-y", "@scope/server-\(i)@1.0.\(i)"], "env": ["KEY\(i)": "${KEY\(i)}"]] }
        let userSettings: [String: Any] = ["permissions": ["allow": (0..<40).map { "Bash(cmd\($0) *)" }], "mcpServers": mcp]
        try JSONSerialization.data(withJSONObject: userSettings).write(to: URL(fileURLWithPath: home + "/.claude/settings.json"))
        var scopes = [Scope(scopeID: "scope_user", alias: "user", realPath: home, kind: .userRoot)]
        for p in 0..<20 {
            let proj = root.appendingPathComponent("proj\(p)").path
            try FileManager.default.createDirectory(atPath: proj + "/.claude/skills", withIntermediateDirectories: true)
            let ps: [String: Any] = ["permissions": ["allow": ["Bash(npm test *)"]], "hooks": ["PostToolUse": [["matcher": "Edit", "hooks": [["type": "command", "command": "npm run lint"]]]]]]
            try JSONSerialization.data(withJSONObject: ps).write(to: URL(fileURLWithPath: proj + "/.claude/settings.json"))
            try "# proj \(p)\n".write(toFile: proj + "/CLAUDE.md", atomically: true, encoding: .utf8)
            for f in 0..<90 { try String(repeating: "x", count: 1000).write(toFile: proj + "/.claude/skills/s\(f).md", atomically: true, encoding: .utf8) }
            scopes.append(Scope(scopeID: "p\(p)", alias: "proj\(p)", realPath: proj, kind: .project))
        }
        let scanner = Scanner(rules: Fx.rules, redactor: Fx.redactor)
        var times: [Double] = []
        var obs = 0
        for _ in 0..<20 {
            let t0 = Date()
            let r = scanner.run(scopes: scopes)
            times.append(Date().timeIntervalSince(t0))
            obs = r.observations.count
            #expect(r.status == .complete, "\(r.coverage.filter { $0.status != .success })")
        }
        times.sort()
        let p95 = times[Int(Double(times.count - 1) * 0.95)]
        let rss = residentMB()
        print("PERF full scan: n=20 obs=\(obs) p50=\(String(format: "%.3f", times[10]))s p95=\(String(format: "%.3f", p95))s max=\(String(format: "%.3f", times.last!))s rss=\(rss)MB host=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        #expect(p95 < 60, "p95 \(p95)s")
        #expect(rss < 350, "rss \(rss)MB")
        try? FileManager.default.removeItem(at: root)
    }

    func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
    }
}
