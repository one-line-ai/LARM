import Foundation

/// Cursor MCP 어댑터.
public struct CursorAdapter: Adapter {
    public let id = "cursor"
    public let version = "1.0.0"
    public init() {}

    public func detectInstall(home: String) -> AgentInstall {
        let plist = "/Applications/Cursor.app/Contents/Info.plist"
        if let d = FileManager.default.contents(atPath: plist),
           let p = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any] {
            let v = p["CFBundleShortVersionString"] as? String
            return AgentInstall(status: .installed, version: v, versionSource: "Cursor.app Info.plist", supportLevel: "limited")
        }
        if AdapterUtil.exists(home + "/.cursor/mcp.json") {
            return AgentInstall(status: .configOnly, version: nil, versionSource: "설정 잔존", supportLevel: "limited")
        }
        return AgentInstall(status: .notInstalled, version: nil, versionSource: "없음", supportLevel: "unsupported")
    }

    public func watchTargets(scope: Scope, home: String) -> WatchTargets {
        scope.kind == .userRoot ? WatchTargets(dirs: [home + "/.cursor"], files: []) : WatchTargets(dirs: [scope.realPath + "/.cursor"], files: [])
    }

    public func scan(_ ctx: AdapterContext) {
        let home = ctx.home
        let install = detectInstall(home: home)
        let path = ctx.scope.kind == .userRoot ? home + "/.cursor/mcp.json" : ctx.scope.realPath + "/.cursor/mcp.json"
        let prov = ctx.provenance(path, precedence: ctx.scope.kind == .userRoot ? "user" : "project", interpretation: "Cursor mcp.json (S5)")
        if ctx.scope.kind == .userRoot { AdapterUtil.emitInstall(ctx, agent: id, install: install, prov: prov) }
        guard AdapterUtil.exists(path) else { if ctx.scope.kind == .userRoot { ctx.cover(path, .absent, install.status == .notInstalled ? "미설치·파일 없음" : "파일 없음") }; return }
        guard install.status != .notInstalled else { return }
        guard let (obj, _) = ctx.readParsed(path, parse: { try SafeJSON.parse($0) }), let dict = obj as? [String: Any] else { return }
        let label = ctx.scope.kind == .userRoot ? "user" : "project"
        let cfgID = "cfg:cursor:\(ctx.scope.scopeID):\(label)"
        ctx.emit(cfgID, .configuration, "agent", "cursor", prov: prov)
        ctx.emit(cfgID, .configuration, "scope", label, prov: prov)
        ctx.emit(cfgID, .configuration, "location", prov.locationAlias, prov: prov)
        if let servers = dict["mcpServers"] as? [String: Any] {
            for (name, def) in servers { if let d = def as? [String: Any] {
                MCPNormalizer.emit(ctx: ctx, agent: id, scopeLabel: "\(ctx.scope.scopeID):\(label)", name: name, def: d, prov: prov, configObjectID: cfgID) } }
        }
        ctx.emitFilePerms(path, prov: prov, isCredentialStore: false)
    }
}
