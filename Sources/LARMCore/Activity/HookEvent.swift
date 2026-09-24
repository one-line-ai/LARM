import Foundation

/// hook이 앱으로 보내는 최소 사건.
/// 경로는 별칭 처리를 위해 hook 프로세스 안에서만 잠시 다루고, 앱은 수신 즉시 별칭으로 바꾼다.
public struct HookEvent: Codable, Sendable, Equatable {
    public static let schema = "larm-hook/1"
    public var schema: String = HookEvent.schema
    public var hookVersion: String = "1.0.0"
    public var eventID: String
    public var sourceEventID: String
    public var phase: String              // request | result | session_start | session_end | test | other
    public var hookEventName: String      // PreToolUse 등 원문 활동 기록명
    public var toolName: String
    public var targetKind: String         // file | command | url | mcp | none
    public var targetPath: String?        // file/url 대상 (앱이 별칭 처리 후 폐기)
    public var commandBasename: String?
    public var argc: Int
    public var argFingerprint: String     // sha256(정규화 인자)
    public var flags: [String]            // sudo, rm_recursive, pipe_to_shell, base64_decode, eval, shell_wrapper, sensitive_path, network_fetch, env_dump
    public var sessionRef: String
    public var processRef: String         // "\(ppid)@\(starttime)"
    public var observedAt: String
    public var resultPresent: Bool

    enum CodingKeys: String, CodingKey {
        case schema, eventID = "event_id", sourceEventID = "source_event_id", phase, hookEventName = "hook_event_name", toolName = "tool_name"
        case targetKind = "target_kind", targetPath = "target_path", commandBasename = "command_basename", argc, argFingerprint = "arg_fp", flags
        case sessionRef = "session_ref", processRef = "process_ref", observedAt = "observed_at", resultPresent = "result_present", hookVersion = "hook_version"
    }
}

/// Claude Code hook stdin(JSON)을 최소 사건으로 분류한다.
public enum HookClassifier {
    static let sensitivePath = try! NSRegularExpression(pattern: "(?i)(/\\.ssh/|/\\.aws/|/\\.gnupg/|/\\.config/gcloud|\\.credentials\\.json|/auth\\.json|/\\.netrc|/\\.env(\\.|$)|\\.pem$|\\.p12$|id_rsa|id_ed25519|/Library/Keychains|/\\.claude/settings|/\\.codex/config\\.toml|/\\.cursor/mcp\\.json|/etc/(passwd|shadow|sudoers))")
    static let sensitiveInCommand = try! NSRegularExpression(pattern: "(?i)(~/\\.ssh|\\.ssh/|~/\\.aws|\\.aws/credentials|\\.credentials\\.json|auth\\.json|\\.netrc|\\.env\\b|id_rsa|id_ed25519|security find-generic-password|security find-internet-password|/Library/Keychains|/etc/shadow)")

    public static func classify(_ input: [String: Any], now: Date = Date(), ppid: Int32 = getppid(), processStart: String = "") -> HookEvent {
        let name = input["hook_event_name"] as? String ?? "unknown"
        let session = input["session_id"] as? String ?? "unknown"
        let tool = input["tool_name"] as? String ?? ""
        let toolInput = input["tool_input"] as? [String: Any] ?? [:]
        let toolUseID = input["tool_use_id"] as? String
        let phase: String
        switch name {
        case "PreToolUse": phase = "request"
        case "PostToolUse": phase = "result"
        case "SessionStart": phase = "session_start"
        case "SessionEnd": phase = "session_end"
        case "LARMTest": phase = "test"
        default: phase = "other"
        }
        var kind = "none", path: String? = nil, basename: String? = nil, argc = 0, flags: [String] = []
        var normalized = ""
        if let cmd = toolInput["command"] as? String, tool == "Bash" {
            kind = "command"
            let tokens = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            argc = max(0, tokens.count - 1)
            var first = tokens.first ?? ""
            var idx = 0
            while idx < tokens.count, tokens[idx].contains("="), !tokens[idx].hasPrefix("-") { idx += 1; first = idx < tokens.count ? tokens[idx] : first; flags.append("env_assignment"); break }
            basename = (first as NSString).lastPathComponent
            normalized = cmd.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let lower = cmd.lowercased()
            if lower.contains("sudo ") || lower.hasPrefix("sudo") { flags.append("sudo") }
            if lower.range(of: "\\brm\\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-rf|-fr)\\b", options: .regularExpression) != nil { flags.append("rm_recursive") }
            if lower.range(of: "\\|\\s*(sudo\\s+)?(ba|z|da)?sh\\b", options: .regularExpression) != nil { flags.append("pipe_to_shell") }
            if lower.contains("base64") && (lower.contains("-d") || lower.contains("--decode")) { flags.append("base64_decode") }
            if lower.range(of: "\\beval\\b", options: .regularExpression) != nil { flags.append("eval") }
            if lower.range(of: "\\b(bash|sh|zsh)\\s+-c\\b", options: .regularExpression) != nil { flags.append("shell_wrapper") }
            if lower.range(of: "\\b(curl|wget)\\b", options: .regularExpression) != nil { flags.append("network_fetch") }
            if lower.range(of: "\\b(env|printenv)\\b", options: .regularExpression) != nil || lower.contains("cat ~/.zshrc") { flags.append("env_dump") }
            if sensitiveInCommand.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)) != nil { flags.append("sensitive_path") }
            if lower.contains("\\x") || lower.contains("$'\\") || lower.contains("printf '\\") { flags.append("encoded_input") }
        } else if let p = (toolInput["file_path"] as? String) ?? (toolInput["path"] as? String) ?? (toolInput["notebook_path"] as? String) {
            kind = "file"; path = p; argc = toolInput.count; normalized = p
            if sensitivePath.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)) != nil { flags.append("sensitive_path") }
        } else if let u = toolInput["url"] as? String {
            kind = "url"; argc = toolInput.count
            if let s = MCPNormalizer.summarize(url: u) { path = "\(s.scheme)://\(s.host):\(s.port)" ; normalized = path! }
            flags.append("network_fetch")
        } else if tool.hasPrefix("mcp__") {
            kind = "mcp"; argc = toolInput.count; normalized = tool + ":" + toolInput.keys.sorted().joined(separator: ",")
        } else if !toolInput.isEmpty {
            argc = toolInput.count; normalized = tool + ":" + toolInput.keys.sorted().joined(separator: ",")
        }
        let fp = Hashing.sha256Hex("\(tool)\u{1F}\(normalized)")
        let source = toolUseID.map { "\(session):\($0)" } ?? "\(session):\(name):\(fp.prefix(16)):\(Int(now.timeIntervalSince1970))"
        return HookEvent(eventID: Ids.new("ev"), sourceEventID: source, phase: phase, hookEventName: name, toolName: tool, targetKind: kind,
                         targetPath: path, commandBasename: basename, argc: argc, argFingerprint: fp, flags: Array(Set(flags)).sorted(),
                         sessionRef: session, processRef: "\(ppid)@\(processStart)", observedAt: Clock.utc(now), resultPresent: input["tool_response"] != nil)
    }

    /// 부모 프로세스 시작 시각 (PID 재사용 구분, N11).
    public static func processStartTime(pid: Int32) -> String {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return "" }
        let t = info.kp_proc.p_starttime
        return "\(t.tv_sec).\(t.tv_usec)"
    }
}
