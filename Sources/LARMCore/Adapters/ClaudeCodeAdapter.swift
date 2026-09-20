import Foundation

/// Claude Code 어댑터.
public struct ClaudeCodeAdapter: Adapter {
    public let id = "claude-code"
    public let version = "1.0.0"
    /// 실제 시험한 버전 범위.
    static let testedMajorMinor = ["2.1"]
    public init() {}

    public func detectInstall(home: String) -> AgentInstall {
        let bin = home + "/.local/bin/claude"
        let cfg = home + "/.claude/settings.json"
        if let target = AdapterUtil.readlink(bin), let v = AdapterUtil.semver(in: target) {
            let mm = v.split(separator: ".").prefix(2).joined(separator: ".")
            return AgentInstall(status: .installed, version: v, versionSource: "~/.local/bin/claude 심볼릭 링크 대상",
                                supportLevel: Self.testedMajorMinor.contains(mm) ? "supported" : "limited")
        }
        if AdapterUtil.exists(bin) { return AgentInstall(status: .installed, version: nil, versionSource: "실행 파일 존재, 버전 불명", supportLevel: "limited") }
        if AdapterUtil.exists(cfg) || AdapterUtil.exists(home + "/.claude.json") {
            return AgentInstall(status: .configOnly, version: nil, versionSource: "설정 잔존", supportLevel: "limited")
        }
        return AgentInstall(status: .notInstalled, version: nil, versionSource: "없음", supportLevel: "unsupported")
    }

    public func watchTargets(scope: Scope, home: String) -> WatchTargets {
        if scope.kind == .userRoot { return WatchTargets(dirs: [home + "/.claude"], files: [home + "/.claude.json"]) }
        let r = scope.realPath
        return WatchTargets(dirs: [r + "/.claude"], files: [r + "/.mcp.json", r + "/CLAUDE.md", r + "/CLAUDE.local.md", r + "/AGENTS.md"])
    }

    public func scan(_ ctx: AdapterContext) {
        let home = ctx.home
        let install = detectInstall(home: home)
        if ctx.scope.kind == .userRoot {
            let p = ctx.provenance(home + "/.claude/settings.json", precedence: "user", interpretation: "사용자 설정 (S1)")
            AdapterUtil.emitInstall(ctx, agent: id, install: install, prov: p)
            guard install.status != .notInstalled else { ctx.cover(home + "/.claude/settings.json", .absent, "미설치·파일 없음"); return }
            scanSettings(ctx, path: "/Library/Application Support/ClaudeCode/managed-settings.json", scopeLabel: "managed", precedence: "managed", optional: true)
            scanSettings(ctx, path: home + "/.claude/settings.json", scopeLabel: "user", precedence: "user", optional: false)
            scanClaudeJSON(ctx, path: home + "/.claude.json")
            let credProv = ctx.provenance(home + "/.claude/.credentials.json", precedence: "n/a", interpretation: "자격증명 저장 위치 (권한만 확인)")
            ctx.emitFilePerms(home + "/.claude/.credentials.json", prov: credProv, isCredentialStore: true)
            let cp = ctx.provenance(home + "/.claude/CLAUDE.md", precedence: "user", interpretation: "전역 지시 파일")
            ctx.emitInstructionFile(home + "/.claude/CLAUDE.md", kind: "instruction", prov: cp)
        } else {
            guard install.status != .notInstalled else { return }
            let root = ctx.scope.realPath
            scanSettings(ctx, path: root + "/.claude/settings.json", scopeLabel: "project", precedence: "project", optional: true)
            scanSettings(ctx, path: root + "/.claude/settings.local.json", scopeLabel: "local", precedence: "local", optional: true)
            scanMCPJSON(ctx, path: root + "/.mcp.json")
            for f in ["CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md", "AGENTS.md"] {
                let p = ctx.provenance(root + "/" + f, precedence: "project", interpretation: "프로젝트 지시 파일")
                ctx.emitInstructionFile(root + "/" + f, kind: "instruction", prov: p)
            }
            for dir in [".claude/skills", ".claude/agents", ".claude/commands", ".claude/hooks"] {
                enumerateRegistered(ctx, dir: root + "/" + dir, kind: dir.replacingOccurrences(of: ".claude/", with: ""))
            }
        }
    }

    func scanSettings(_ ctx: AdapterContext, path: String, scopeLabel: String, precedence: String, optional: Bool) {
        if optional, !AdapterUtil.exists(path) { return }
        guard let (obj, _) = ctx.readParsed(path, parse: { try SafeJSON.parse($0) }) else { return }
        guard let dict = obj as? [String: Any] else { ctx.cover(path, .error, "최상위가 객체가 아님"); return }
        let prov = ctx.provenance(path, precedence: precedence, interpretation: "Claude Code settings (\(precedence)) (S1/S2)")
        let cfgID = "cfg:claude-code:\(ctx.scope.scopeID):\(scopeLabel)"
        ctx.emit(cfgID, .configuration, "agent", "claude-code", prov: prov)
        ctx.emit(cfgID, .configuration, "scope", scopeLabel, prov: prov)
        ctx.emit(cfgID, .configuration, "location", prov.locationAlias, prov: prov)
        ctx.emit(cfgID, .configuration, "top_level_keys", dict.keys.sorted().joined(separator: ","), prov: prov)
        let known: Set<String> = ["permissions", "hooks", "mcpServers", "env", "sandbox", "model", "theme", "apiKeyHelper", "enableAllProjectMcpServers",
                                  "enabledMcpjsonServers", "disabledMcpjsonServers", "enabledPlugins", "extraKnownMarketplaces", "includeCoAuthoredBy",
                                  "cleanupPeriodDays", "statusLine", "outputStyle", "forceLoginMethod", "modelSettings", "alwaysThinkingEnabled",
                                  "inputNeededNotifEnabled", "agentPushNotifEnabled", "spinnerTipsEnabled", "language", "autoUpdates", "permissions.defaultMode"]
        let unknownKeys = dict.keys.filter { !known.contains($0) }.sorted()
        if !unknownKeys.isEmpty { ctx.emit(cfgID, .configuration, "unsupported_keys", unknownKeys.joined(separator: ","), kind: .unknown, prov: prov) }

        let acfgID = "acfg:claude-code:\(ctx.scope.scopeID)"
        if let perms = dict["permissions"] as? [String: Any] {
            if let mode = perms["defaultMode"] as? String {
                ctx.emit(cfgID, .configuration, "permissions.defaultMode", mode, prov: prov)
                ctx.emit(acfgID, .agentConfig, "approval_mode", mode, prov: prov)
                ctx.emit(acfgID, .agentConfig, "approval_mode_source", prov.locationAlias, prov: prov)
            }
            if let dirs = perms["additionalDirectories"] as? [Any] {
                ctx.emit(cfgID, .configuration, "permissions.additionalDirectories_count", "\(dirs.count)", prov: prov)
            }
            let denyList = (perms["deny"] as? [Any])?.compactMap { $0 as? String } ?? []
            for list in ["allow", "ask", "deny"] {
                guard let rules = perms[list] as? [Any] else { continue }
                for (i, r) in rules.enumerated() {
                    guard let s = r as? String else { continue }
                    emitPermissionRule(ctx, cfgID: cfgID, list: list, index: i, rule: s, denied: list != "deny" && denyList.contains(s), prov: prov)
                }
            }
        }
        if let sb = dict["sandbox"] as? [String: Any] {
            if let en = sb["enabled"] as? Bool {
                ctx.emit(acfgID, .agentConfig, "sandbox_mode", en ? "enabled" : "disabled", prov: prov)
            }
            if let net = sb["network"] as? [String: Any], let allow = net["allowUnixSockets"] ?? net["allowedDomains"] {
                ctx.emit(acfgID, .agentConfig, "network_access", "configured(\(type(of: allow)))", prov: prov)
            }
        }
        if let hooks = dict["hooks"] as? [String: Any] {
            for (event, arr) in hooks {
                guard let matchers = arr as? [[String: Any]] else { continue }
                for (mi, m) in matchers.enumerated() {
                    let inner = (m["hooks"] as? [[String: Any]]) ?? []
                    for (hi, h) in inner.enumerated() {
                        let hid = "hook:claude-code:\(ctx.scope.scopeID):\(scopeLabel):\(event)[\(mi)][\(hi)]"
                        ctx.emit(hid, .hook, "event", event, prov: prov)
                        ctx.emit(hid, .hook, "matcher", (m["matcher"] as? String) ?? "", prov: prov)
                        ctx.emit(hid, .hook, "type", (h["type"] as? String) ?? "unknown", prov: prov)
                        if let cmd = h["command"] as? String {
                            let (k, b) = MCPNormalizer.commandKind(cmd.split(separator: " ").first.map(String.init) ?? cmd)
                            ctx.emit(hid, .hook, "command_kind", k, prov: prov)
                            ctx.emit(hid, .hook, "command_basename", b, prov: prov)
                            ctx.emit(hid, .hook, "owner", cmd.contains("/LARM.app/Contents/MacOS/larm-hook") ? "larm" : "other", prov: prov)
                        }
                        ctx.emit(hid, .hook, "baseline_status", "no_baseline", kind: .unknown, prov: prov)
                    }
                }
            }
        }
        if let servers = dict["mcpServers"] as? [String: Any] {
            for (name, def) in servers {
                guard let d = def as? [String: Any] else { continue }
                MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(ctx.scope.scopeID):\(scopeLabel)", name: name, def: d, prov: prov, configObjectID: cfgID)
            }
        }
        if let env = dict["env"] as? [String: Any] {
            ctx.emit(cfgID, .configuration, "env_keys", env.keys.sorted().joined(separator: ","), prov: prov)
            for (k, v) in env {
                guard let s = v as? String else { continue }
                ctx.emitValue(cfgID, .configuration, "env.\(k)", raw: s, keyPath: "env.\(k)", prov: prov, configObjectID: cfgID)
                if k.hasSuffix("BASE_URL"), let sum = MCPNormalizer.summarize(url: s) {
                    let eid = "ep:\(sum.scheme)://\(sum.host):\(sum.port)"
                    ctx.emit(eid, .endpoint, "scheme", sum.scheme, prov: prov)
                    ctx.emit(eid, .endpoint, "host", sum.host, prov: prov)
                    ctx.emit(eid, .endpoint, "port", sum.port, prov: prov)
                    ctx.emit(eid, .endpoint, "loopback", sum.loopback ? "true" : "false", prov: prov)
                    ctx.emit(eid, .endpoint, "referenced_by", "\(cfgID) env.\(k)", prov: prov)
                    ctx.emit(eid, .endpoint, "reviewed", "false", prov: prov)
                }
            }
        }
        if let helper = dict["apiKeyHelper"] as? String {
            ctx.emit(cfgID, .configuration, "apiKeyHelper_present", "true", prov: prov)
            _ = helper
        }
        if let all = dict["enableAllProjectMcpServers"] as? Bool { ctx.emit(cfgID, .configuration, "enableAllProjectMcpServers", all ? "true" : "false", prov: prov) }
        ctx.emitFilePerms(path, prov: prov, isCredentialStore: false)
    }

    /// 허용 규칙 문법 해석.
    func emitPermissionRule(_ ctx: AdapterContext, cfgID: String, list: String, index: Int, rule: String, denied: Bool, prov: Provenance) {
        let rid = "perm:\(cfgID):\(list)[\(index)]"
        ctx.emit(rid, .permissionRule, "list", list, prov: prov)
        ctx.emit(rid, .permissionRule, "rule_safe", Redactor.scrub(String(rule.prefix(120))), prov: prov)
        ctx.emit(rid, .permissionRule, "denied_by_same_rule", denied ? "true" : "false", prov: prov)
        let re = try! NSRegularExpression(pattern: "^([A-Za-z_][A-Za-z0-9_]*)(?:\\((.*)\\))?$")
        guard let m = re.firstMatch(in: rule, range: NSRange(rule.startIndex..., in: rule)), let tr = Range(m.range(at: 1), in: rule) else {
            ctx.emit(rid, .permissionRule, "interpretable", "false", prov: prov)
            ctx.emit(rid, .permissionRule, "breadth", "unknown", kind: .unknown, prov: prov)
            return
        }
        let tool = String(rule[tr])
        let pattern = Range(m.range(at: 2), in: rule).map { String(rule[$0]) }
        ctx.emit(rid, .permissionRule, "tool", tool, prov: prov)
        ctx.emit(rid, .permissionRule, "interpretable", "true", prov: prov)
        var breadth = "narrow"
        let p = pattern?.trimmingCharacters(in: .whitespaces)
        if tool == "Bash" {
            if p == nil || p == "*" || p == "*:*" || p == "**" { breadth = "full_shell" }
            else if let p, p.hasPrefix("*") { breadth = "full_shell" }
            else if let p, p.contains("sudo") || p.hasPrefix("sh ") || p.hasPrefix("bash ") || p.hasPrefix("eval") { breadth = "broad_shell" }
        } else if ["Write", "Edit", "MultiEdit", "NotebookEdit"].contains(tool) {
            if p == nil || p == "*" || p == "**" || p == "//**" || p == "/**" { breadth = "broad_write" }
        } else if tool.hasPrefix("mcp__") {
            let parts = tool.split(separator: "_", omittingEmptySubsequences: false)
            if tool == "mcp__" || tool == "mcp__*" || parts.count <= 3 { breadth = "wildcard" }
        } else if tool == "WebFetch" || tool == "WebSearch" {
            if p == nil || p == "*" || p == "domain:*" { breadth = "broad_network" }
        }
        ctx.emit(rid, .permissionRule, "breadth", breadth, prov: prov)
        ctx.emit(rid, .permissionRule, "effective", (list == "allow" && !denied) ? "true" : "false", prov: prov)
    }

    /// ~/.claude.json: mcpServers와 projects.mcpServers/allowedTools만 읽는다.
    func scanClaudeJSON(_ ctx: AdapterContext, path: String) {
        guard let (obj, _) = ctx.readParsed(path, parse: { try SafeJSON.parse($0) }), let dict = obj as? [String: Any] else { return }
        let prov = ctx.provenance(path, precedence: "user", interpretation: "~/.claude.json의 mcpServers·projects[*].mcpServers만 해석")
        let cfgID = "cfg:claude-code:\(ctx.scope.scopeID):claude_json"
        ctx.emit(cfgID, .configuration, "agent", "claude-code", prov: prov)
        ctx.emit(cfgID, .configuration, "scope", "user", prov: prov)
        ctx.emit(cfgID, .configuration, "location", prov.locationAlias, prov: prov)
        ctx.emit(cfgID, .configuration, "keys_read", "mcpServers,projects[*].mcpServers,projects[*].allowedTools", prov: prov)
        if let servers = dict["mcpServers"] as? [String: Any] {
            for (name, def) in servers { if let d = def as? [String: Any] {
                MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(ctx.scope.scopeID):user", name: name, def: d, prov: prov, configObjectID: cfgID) } }
        }
        if let projects = dict["projects"] as? [String: Any] {
            ctx.emit(cfgID, .configuration, "projects_count", "\(projects.count)", prov: prov)
            for (ppath, pv) in projects {
                guard let pd = pv as? [String: Any] else { continue }
                let palias = ctx.alias(ppath)
                if let servers = pd["mcpServers"] as? [String: Any], !servers.isEmpty {
                    for (name, def) in servers { if let d = def as? [String: Any] {
                        MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(Hashing.sha256Hex(ppath).prefix(8)):project_local", name: name, def: d,
                                           prov: Provenance(adapter: prov.adapter, adapterVersion: prov.adapterVersion, locationAlias: "~/.claude.json projects[\(palias)]",
                                                            scopeID: ctx.scope.scopeID, precedence: "local", interpretation: prov.interpretation),
                                           configObjectID: cfgID) } }
                }
                if let tools = pd["allowedTools"] as? [Any], !tools.isEmpty {
                    let sub = "cfg:claude-code:\(ctx.scope.scopeID):claude_json:\(Hashing.sha256Hex(ppath).prefix(8))"
                    let sp = Provenance(adapter: prov.adapter, adapterVersion: prov.adapterVersion, locationAlias: "~/.claude.json projects[\(palias)].allowedTools",
                                        scopeID: ctx.scope.scopeID, precedence: "local", interpretation: "레거시 allowedTools")
                    for (i, t) in tools.enumerated() { if let s = t as? String {
                        emitPermissionRule(ctx, cfgID: sub, list: "allow", index: i, rule: s, denied: false, prov: sp) } }
                }
            }
        }
        ctx.emitFilePerms(path, prov: prov, isCredentialStore: false)
    }

    func scanMCPJSON(_ ctx: AdapterContext, path: String) {
        guard AdapterUtil.exists(path) else { return }
        guard let (obj, _) = ctx.readParsed(path, parse: { try SafeJSON.parse($0) }), let dict = obj as? [String: Any] else { return }
        let prov = ctx.provenance(path, precedence: "project", interpretation: "프로젝트 .mcp.json (S1)")
        let cfgID = "cfg:claude-code:\(ctx.scope.scopeID):mcp_json"
        ctx.emit(cfgID, .configuration, "agent", "claude-code", prov: prov)
        ctx.emit(cfgID, .configuration, "scope", "project", prov: prov)
        ctx.emit(cfgID, .configuration, "location", prov.locationAlias, prov: prov)
        if let servers = dict["mcpServers"] as? [String: Any] {
            for (name, def) in servers { if let d = def as? [String: Any] {
                MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(ctx.scope.scopeID):project", name: name, def: d, prov: prov, configObjectID: cfgID) } }
        }
        ctx.emitFilePerms(path, prov: prov, isCredentialStore: false)
    }

    /// 등록된 스킬·에이전트·커맨드·훅 파일 열거 (깊이 제한, 상한 적용).
    func enumerateRegistered(_ ctx: AdapterContext, dir: String, kind: String) {
        guard let st = try? SafeFile.lstat(dir), !st.isSymlink else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return }
        guard let e = FileManager.default.enumerator(atPath: dir) else { return }
        var count = 0
        while let rel = e.nextObject() as? String {
            if e.level > 3 { e.skipDescendants(); continue }
            if rel.hasPrefix(".") { continue }
            let full = dir + "/" + rel
            guard let fst = try? SafeFile.lstat(full), fst.isRegular else { continue }
            count += 1
            if count > 200 { ctx.cover(dir, .oversize, "등록 파일 200개 초과"); return }
            let p = ctx.provenance(full, precedence: "project", interpretation: "등록된 \(kind) 파일")
            ctx.emitInstructionFile(full, kind: kind, prov: p)
        }
    }
}
