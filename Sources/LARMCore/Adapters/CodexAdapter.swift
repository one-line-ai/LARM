import Foundation

/// Codex CLI 어댑터.
public struct CodexAdapter: Adapter {
    public let id = "codex"
    public let version = "1.0.0"
    static let testedMajorMinor = ["0.153"]
    public init() {}

    public func detectInstall(home: String) -> AgentInstall {
        let bin = home + "/.local/bin/codex"
        let current = home + "/.codex/packages/standalone/current"
        if let target = AdapterUtil.readlink(current), let v = AdapterUtil.semver(in: target) {
            let mm = v.split(separator: ".").prefix(2).joined(separator: ".")
            return AgentInstall(status: .installed, version: v, versionSource: "~/.codex/packages/standalone/current 바로가기 링크 대상",
                                supportLevel: Self.testedMajorMinor.contains(mm) ? "supported" : "limited")
        }
        if AdapterUtil.exists(bin) { return AgentInstall(status: .installed, version: nil, versionSource: "실행 파일 존재, 버전 불명", supportLevel: "limited") }
        if AdapterUtil.exists(home + "/.codex/config.toml") {
            return AgentInstall(status: .configOnly, version: nil, versionSource: "설정 잔존", supportLevel: "limited")
        }
        return AgentInstall(status: .notInstalled, version: nil, versionSource: "없음", supportLevel: "unsupported")
    }

    public func watchTargets(scope: Scope, home: String) -> WatchTargets {
        if scope.kind == .userRoot { return WatchTargets(dirs: [], files: [home + "/.codex/config.toml", home + "/.codex/AGENTS.md"]) }
        let r = scope.realPath
        return WatchTargets(dirs: [r + "/.codex"], files: [r + "/AGENTS.md", r + "/AGENTS.override.md"])
    }

    public func scan(_ ctx: AdapterContext) {
        let home = ctx.home
        let install = detectInstall(home: home)
        if ctx.scope.kind == .userRoot {
            let p = ctx.provenance(home + "/.codex/config.toml", precedence: "user", interpretation: "사용자 설정 (S3)")
            AdapterUtil.emitInstall(ctx, agent: id, install: install, prov: p)
            guard install.status != .notInstalled else { ctx.cover(home + "/.codex/config.toml", .absent, "미설치·파일 없음"); return }
            scanConfig(ctx, path: home + "/.codex/config.toml", scopeLabel: "user", precedence: "user")
            let credProv = ctx.provenance(home + "/.codex/auth.json", precedence: "n/a", interpretation: "자격증명 저장 위치 (권한만 확인)")
            ctx.emitFilePerms(home + "/.codex/auth.json", prov: credProv, isCredentialStore: true)
            let ip = ctx.provenance(home + "/.codex/AGENTS.md", precedence: "user", interpretation: "전역 지시 파일")
            ctx.emitInstructionFile(home + "/.codex/AGENTS.md", kind: "instruction", prov: ip)
        } else {
            guard install.status != .notInstalled else { return }
            let root = ctx.scope.realPath
            if AdapterUtil.exists(root + "/.codex/config.toml") {
                scanConfig(ctx, path: root + "/.codex/config.toml", scopeLabel: "project", precedence: "project")
            }
            for f in ["AGENTS.md", "AGENTS.override.md"] {
                let p = ctx.provenance(root + "/" + f, precedence: "project", interpretation: "프로젝트 지시 파일")
                ctx.emitInstructionFile(root + "/" + f, kind: "instruction", prov: p)
            }
        }
    }

    func scanConfig(_ ctx: AdapterContext, path: String, scopeLabel: String, precedence: String) {
        guard let (dict, _) = ctx.readParsed(path, parse: { try MiniTOML.parse($0) }) else { return }
        let prov = ctx.provenance(path, precedence: precedence, interpretation: "Codex config.toml (\(precedence)) (S3/S4)")
        let cfgID = "cfg:codex:\(ctx.scope.scopeID):\(scopeLabel)"
        let acfgID = "acfg:codex:\(ctx.scope.scopeID)"
        ctx.emit(cfgID, .configuration, "agent", "codex", prov: prov)
        ctx.emit(cfgID, .configuration, "scope", scopeLabel, prov: prov)
        ctx.emit(cfgID, .configuration, "location", prov.locationAlias, prov: prov)
        ctx.emit(cfgID, .configuration, "top_level_keys", dict.keys.sorted().joined(separator: ","), prov: prov)

        var effective = dict
        var profileNote = "none"
        if let pname = dict["profile"] as? String {
            if let profiles = dict["profiles"] as? [String: Any], let prof = profiles[pname] as? [String: Any] {
                for (k, v) in prof { effective[k] = v }
                profileNote = "applied:\(pname)"
            } else {
                profileNote = "unresolved:\(pname)"
            }
        }
        ctx.emit(cfgID, .configuration, "profile", profileNote, kind: profileNote.hasPrefix("unresolved") ? .unknown : .literal, prov: prov)
        let unresolved = profileNote.hasPrefix("unresolved")

        func emitEff(_ key: String, as field: String) {
            if unresolved {
                ctx.emit(acfgID, .agentConfig, field, "unknown", kind: .unknown, prov: prov)
            } else if let v = effective[key] as? String {
                ctx.emit(acfgID, .agentConfig, field, v, prov: prov)
                ctx.emit(acfgID, .agentConfig, "\(field)_source", prov.locationAlias, prov: prov)
                ctx.emit(cfgID, .configuration, key, v, prov: prov)
            }
        }
        emitEff("approval_policy", as: "approval_mode")
        emitEff("sandbox_mode", as: "sandbox_mode")
        if let ww = effective["sandbox_workspace_write"] as? [String: Any], let net = ww["network_access"] as? Bool {
            ctx.emit(acfgID, .agentConfig, "network_access", net ? "allowed" : "restricted", prov: prov)
        }
        if effective["approval_policy"] == nil && !unresolved { ctx.emit(acfgID, .agentConfig, "approval_mode", "default_unset", prov: prov) }
        if effective["sandbox_mode"] == nil && !unresolved { ctx.emit(acfgID, .agentConfig, "sandbox_mode", "default_unset", prov: prov) }
        ctx.emit(acfgID, .agentConfig, "runtime_flags", "unobserved", kind: .unknown, prov: prov)

        if let notify = dict["notify"] as? [Any], let first = notify.first as? String {
            let (k, b) = MCPNormalizer.commandKind(first)
            let hid = "hook:codex:\(ctx.scope.scopeID):\(scopeLabel):notify"
            ctx.emit(hid, .hook, "event", "notify", prov: prov)
            ctx.emit(hid, .hook, "type", "command", prov: prov)
            ctx.emit(hid, .hook, "command_kind", k, prov: prov)
            ctx.emit(hid, .hook, "command_basename", b, prov: prov)
            ctx.emit(hid, .hook, "owner", "other", prov: prov)
            ctx.emit(hid, .hook, "baseline_status", "no_baseline", kind: .unknown, prov: prov)
        }
        if let projects = dict["projects"] as? [String: Any] {
            ctx.emit(cfgID, .configuration, "projects_count", "\(projects.count)", prov: prov)
            var full = 0
            for (_, v) in projects { if let d = v as? [String: Any], (d["trust_level"] as? String) == "trusted" { full += 1 } }
            ctx.emit(cfgID, .configuration, "projects_trusted_count", "\(full)", prov: prov)
        }
        if let servers = effective["mcp_servers"] as? [String: Any] {
            for (name, def) in servers { if let d = def as? [String: Any] {
                MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(ctx.scope.scopeID):\(scopeLabel)", name: name, def: d, prov: prov, configObjectID: cfgID) } }
        }
        if let providers = effective["model_providers"] as? [String: Any] {
            for (pname, pv) in providers {
                guard let pd = pv as? [String: Any] else { continue }
                if let base = pd["base_url"] as? String, let s = MCPNormalizer.summarize(url: base) {
                    let eid = "ep:\(s.scheme)://\(s.host):\(s.port)"
                    ctx.emit(eid, .endpoint, "scheme", s.scheme, prov: prov)
                    ctx.emit(eid, .endpoint, "host", s.host, prov: prov)
                    ctx.emit(eid, .endpoint, "port", s.port, prov: prov)
                    ctx.emit(eid, .endpoint, "loopback", s.loopback ? "true" : "false", prov: prov)
                    ctx.emit(eid, .endpoint, "referenced_by", "\(cfgID) model_providers.\(pname)", prov: prov)
                    ctx.emit(eid, .endpoint, "reviewed", "false", prov: prov)
                }
                for (k, v) in pd where k != "base_url" {
                    if let s = v as? String { ctx.emitValue(cfgID, .configuration, "model_providers.\(pname).\(k)", raw: s, keyPath: "model_providers.\(pname).\(k)", prov: prov, configObjectID: cfgID) }
                }
            }
        }
        if let sep = dict["shell_environment_policy"] as? [String: Any], let set = sep["set"] as? [String: Any] {
            for (k, v) in set { if let s = v as? String {
                ctx.emitValue(cfgID, .configuration, "shell_environment_policy.set.\(k)", raw: s, keyPath: "shell_environment_policy.set.\(k)", prov: prov, configObjectID: cfgID) } }
        }
        for (k, v) in dict {
            if let s = v as? String, SecretPatterns.isSensitiveKey(k) {
                ctx.emitValue(cfgID, .configuration, k, raw: s, keyPath: k, prov: prov, configObjectID: cfgID)
            }
        }
        ctx.emitFilePerms(path, prov: prov, isCredentialStore: false)
    }
}
