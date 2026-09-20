import Foundation

/// 어댑터가 관측·coverage를 쌓는 컨텍스트.
public final class AdapterContext {
    public let scope: Scope
    public let budget: ScanBudget
    public let redactor: Redactor
    public let adapter: String
    public let adapterVersion: String
    public private(set) var observations: [Observation] = []
    public private(set) var coverage: [Coverage] = []

    public init(scope: Scope, budget: ScanBudget, redactor: Redactor, adapter: String, adapterVersion: String) {
        self.scope = scope; self.budget = budget; self.redactor = redactor; self.adapter = adapter; self.adapterVersion = adapterVersion
    }

    /// 사용자 루트 scope의 실제 경로가 홈이다 (시험에서는 fixture 홈).
    public var home: String { scope.kind == .userRoot ? scope.realPath : NSHomeDirectory() }

    public func alias(_ path: String) -> String {
        let home = self.home
        if scope.kind == .project, path.hasPrefix(scope.realPath) {
            return "<\(scope.alias)>" + path.dropFirst(scope.realPath.count)
        }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    public func cover(_ path: String, _ status: CoverageStatus, _ reason: String = "") {
        coverage.append(Coverage(adapter: adapter, adapterVersion: adapterVersion, scopeID: scope.scopeID,
                                 itemAlias: alias(path), status: status, reason: reason))
    }
    public func coverError(_ path: String, _ error: Error) {
        let (s, r) = SafeFile.coverageStatus(for: error)
        cover(path, s, r)
    }

    public func provenance(_ path: String, precedence: String, interpretation: String) -> Provenance {
        Provenance(adapter: adapter, adapterVersion: adapterVersion, locationAlias: alias(path),
                   scopeID: scope.scopeID, precedence: precedence, interpretation: interpretation)
    }

    /// 값 안의 실제 경로(홈·프로젝트)를 별칭으로 치환한다.
    public func aliasPaths(_ value: String) -> String {
        var v = value
        if scope.kind == .project { v = v.replacingOccurrences(of: scope.realPath, with: "<\(scope.alias)>") }
        let home = self.home
        v = v.replacingOccurrences(of: home + "/", with: "~/").replacingOccurrences(of: home, with: "~")
        let realHome = NSHomeDirectory()
        if realHome != home { v = v.replacingOccurrences(of: realHome + "/", with: "~/").replacingOccurrences(of: realHome, with: "~") }
        return v
    }

    public func emit(_ objectID: String, _ type: ObjectType, _ field: String, _ value: String, kind: ValueKind = .literal,
                     prov: Provenance, fingerprint: String? = nil) {
        observations.append(Observation(objectID: objectID, objectType: type, field: field, safeValue: kind == .literal ? aliasPaths(value) : value,
                                        valueKind: kind, provenance: prov, secretFingerprint: fingerprint))
    }

    /// 문자열 값을 제거기로 통과시켜 기록하고, 비밀정보 후보면 SecretCandidate 객체도 만든다.
    public func emitValue(_ objectID: String, _ type: ObjectType, _ field: String, raw: String, keyPath: String, prov: Provenance,
                          configObjectID: String) {
        let r = redactor.redact(value: raw, key: keyPath)
        emit(objectID, type, field, r.safeValue, kind: r.kind, prov: prov, fingerprint: r.fingerprint)
        if r.kind == .redacted || r.kind == .ref {
            let sid = "secret:\(configObjectID):\(keyPath)"
            emit(sid, .secretCandidate, "kind", r.secretKind == .none ? "sensitive_key" : r.secretKind.rawValue, prov: prov)
            emit(sid, .secretCandidate, "format", r.format, prov: prov)
            emit(sid, .secretCandidate, "key_path", keyPath, prov: prov)
            emit(sid, .secretCandidate, "value_kind", r.kind.rawValue, prov: prov)
            emit(sid, .secretCandidate, "length", "\(raw.count)", prov: prov)
            emit(sid, .secretCandidate, "in_file", prov.locationAlias, prov: prov)
        }
    }

    /// 안전 읽기 + 파서 적용.
    public func readParsed<T>(_ path: String, parse: (Data) throws -> T) -> (T, SafeFile.Stat)? {
        do {
            let (data, st) = try SafeFile.read(path, scopeRoot: scope.realPath, budget: budget)
            do {
                let v = try parse(data)
                cover(path, .success)
                return (v, st)
            } catch let e as ParseError {
                if case .unsupported = e { cover(path, .unsupported, e.description) } else { cover(path, .error, e.description) }
                return nil
            }
        } catch {
            coverError(path, error)
            return nil
        }
    }

    /// 파일 권한 관측.
    public func emitFilePerms(_ path: String, prov: Provenance, isCredentialStore: Bool) {
        let fid = "file:\(alias(path))"
        do {
            let st = try SafeFile.lstat(path)
            guard st.isRegular || st.isSymlink else { cover(path, .unsupported, "일반 파일 아님"); return }
            emit(fid, .file, "posix_mode", String(format: "%04o", st.mode), prov: prov)
            emit(fid, .file, "owner_is_current_user", st.uid == getuid() ? "true" : "false", prov: prov)
            emit(fid, .file, "world_readable", (st.mode & 0o004) != 0 ? "true" : "false", prov: prov)
            emit(fid, .file, "group_readable", (st.mode & 0o040) != 0 ? "true" : "false", prov: prov)
            emit(fid, .file, "acl", "unknown", kind: .unknown, prov: prov)
            emit(fid, .file, "credential_store", isCredentialStore ? "true" : "false", prov: prov)
            let loc = alias(path)
            let hasSecret = observations.contains { $0.objectType == .secretCandidate && $0.field == "value_kind" && $0.safeValue == ValueKind.redacted.rawValue && $0.provenance.locationAlias == loc }
            emit(fid, .file, "has_secret_candidate", hasSecret ? "true" : "false", prov: prov)
            emit(fid, .file, "sensitive", (isCredentialStore || hasSecret) ? "true" : "false", prov: prov)
            if isCredentialStore { cover(path, .success, "권한만 확인 (내용 미열람)") }
        } catch {
            if isCredentialStore { coverError(path, error) }
        }
    }

    /// 지시·훅·스킬 파일 존재와 digest.
    public func emitInstructionFile(_ path: String, kind: String, prov: Provenance) {
        let iid = "instr:\(alias(path))"
        do {
            let (h, st) = try SafeFile.digest(path, scopeRoot: scope.realPath, budget: budget)
            emit(iid, .instructionFile, "kind", kind, prov: prov)
            emit(iid, .instructionFile, "sha256", h, prov: prov)
            emit(iid, .instructionFile, "size", "\(st.size)", prov: prov)
            emit(iid, .instructionFile, "baseline_status", "no_baseline", kind: .unknown, prov: prov)
            cover(path, .success)
        } catch {
            if case SafeFileError.absent = error { return }   // 부재는 정상
            coverError(path, error)
        }
    }
}

/// MCP 서버·엔드포인트 정규화.
public enum MCPNormalizer {
    public struct URLSummary { public let scheme: String; public let host: String; public let port: String; public let loopback: Bool }

    public static func summarize(url raw: String) -> URLSummary? {
        guard let u = URL(string: raw.trimmingCharacters(in: .whitespaces)), let scheme = u.scheme?.lowercased() else { return nil }
        let host = (u.host ?? "").lowercased()
        let port = u.port.map(String.init) ?? (scheme == "https" || scheme == "wss" ? "443" : scheme == "http" || scheme == "ws" ? "80" : "")
        let loop = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost") || host.hasPrefix("127.")
        return URLSummary(scheme: scheme, host: host, port: port, loopback: loop)
    }

    public static func commandKind(_ cmd: String) -> (kind: String, basename: String) {
        let base = (cmd as NSString).lastPathComponent
        switch base {
        case "npx", "bunx", "pnpx": return ("package_runner_node", base)
        case "uvx", "uv", "pipx": return ("package_runner_python", base)
        case "node", "deno", "bun": return ("interpreter_node", base)
        case "python", "python3": return ("interpreter_python", base)
        case "docker", "podman": return ("container", base)
        case "sh", "bash", "zsh": return ("shell", base)
        default: return (cmd.hasPrefix("/") ? "absolute_path" : "bare_command", base)
        }
    }

    /// npx/uvx 패키지 지정에 버전 고정이 있는지.
    public static func pinned(kind: String, args: [String]) -> String {
        guard kind.hasPrefix("package_runner") else { return "n/a" }
        let spec = args.first { !$0.hasPrefix("-") }
        guard let s = spec else { return "unknown" }
        let body = s.hasPrefix("@") ? String(s.dropFirst()) : s
        if body.contains("@") { return "true" }
        if s.hasPrefix("git+") || s.contains("://") { return "unknown" }
        return "false"
    }

    /// 한 MCP 서버 정의를 관측으로 변환한다.
    public static func emit(ctx: AdapterContext, agent: String, scopeLabel: String, name: String, def: [String: Any],
                            prov: Provenance, configObjectID: String) {
        let sid = "mcp:\(agent):\(scopeLabel):\(name)"
        ctx.emit(sid, .mcpServer, "name", name, prov: prov)
        ctx.emit(sid, .mcpServer, "agent", agent, prov: prov)
        ctx.emit(sid, .mcpServer, "declared_in", prov.locationAlias, prov: prov)
        let explicitType = (def["type"] as? String)?.lowercased()
        if let cmd = def["command"] as? String {
            let (k, b) = commandKind(cmd)
            let args = (def["args"] as? [Any])?.compactMap { $0 as? String } ?? []
            ctx.emit(sid, .mcpServer, "transport", explicitType ?? "stdio", prov: prov)
            ctx.emit(sid, .mcpServer, "command_kind", k, prov: prov)
            ctx.emit(sid, .mcpServer, "command_basename", b, prov: prov)
            ctx.emit(sid, .mcpServer, "argc", "\(args.count)", prov: prov)
            ctx.emit(sid, .mcpServer, "pinned_version", pinned(kind: k, args: args), prov: prov)
            for (i, a) in args.enumerated() {
                let r = ctx.redactor.redact(value: a, key: "args[\(i)]")
                if r.kind == .redacted {
                    ctx.emitValue(sid, .mcpServer, "args[\(i)]", raw: a, keyPath: "mcpServers.\(name).args[\(i)]", prov: prov, configObjectID: configObjectID)
                }
            }
        } else if let url = def["url"] as? String {
            let t = explicitType ?? (url.contains("/sse") ? "sse" : "http")
            ctx.emit(sid, .mcpServer, "transport", t, prov: prov)
            if let s = summarize(url: url) {
                let eid = "ep:\(s.scheme)://\(s.host):\(s.port)"
                ctx.emit(sid, .mcpServer, "endpoint", eid, prov: prov)
                ctx.emit(eid, .endpoint, "scheme", s.scheme, prov: prov)
                ctx.emit(eid, .endpoint, "host", s.host, prov: prov)
                ctx.emit(eid, .endpoint, "port", s.port, prov: prov)
                ctx.emit(eid, .endpoint, "loopback", s.loopback ? "true" : "false", prov: prov)
                ctx.emit(eid, .endpoint, "referenced_by", sid, prov: prov)
                ctx.emit(eid, .endpoint, "reviewed", "false", prov: prov)
            } else {
                ctx.emit(sid, .mcpServer, "endpoint", "unparseable", kind: .unknown, prov: prov)
            }
        } else {
            ctx.emit(sid, .mcpServer, "transport", "unknown", kind: .unknown, prov: prov)
        }
        if let env = def["env"] as? [String: Any] {
            ctx.emit(sid, .mcpServer, "env_keys", env.keys.sorted().joined(separator: ","), prov: prov)
            for (k, v) in env {
                if let s = v as? String {
                    ctx.emitValue(sid, .mcpServer, "env.\(k)", raw: s, keyPath: "mcpServers.\(name).env.\(k)", prov: prov, configObjectID: configObjectID)
                }
            }
        }
        for hk in ["headers", "http_headers"] {
            if let h = def[hk] as? [String: Any] {
                ctx.emit(sid, .mcpServer, "header_keys", h.keys.sorted().joined(separator: ","), prov: prov)
                for (k, v) in h {
                    if let s = v as? String {
                        ctx.emitValue(sid, .mcpServer, "header.\(k)", raw: s, keyPath: "mcpServers.\(name).headers.\(k)", prov: prov, configObjectID: configObjectID)
                    }
                }
            }
        }
        if let b = def["bearer_token_env_var"] as? String { ctx.emit(sid, .mcpServer, "bearer_token_env_var", b, kind: .ref, prov: prov) }
        ctx.emit(sid, .mcpServer, "baseline_status", "no_baseline", kind: .unknown, prov: prov)
    }
}

public protocol Adapter {
    var id: String { get }
    var version: String { get }
    /// 설치 식별과 구성 존재를 구분한다.
    func detectInstall(home: String) -> AgentInstall
    func scan(_ ctx: AdapterContext)
    /// 상시 감시 대상: FSEvents로 볼 디렉터리와 60초 stat 폴링으로 볼 개별 파일.
    func watchTargets(scope: Scope, home: String) -> WatchTargets
}

public struct WatchTargets: Sendable, Equatable {
    public var dirs: [String]
    public var files: [String]
    public init(dirs: [String], files: [String]) { self.dirs = dirs; self.files = files }
}

public struct AgentInstall: Sendable {
    public enum Status: String, Sendable { case installed, notInstalled = "not_installed", configOnly = "config_only" }
    public let status: Status
    public let version: String?        // nil = 버전 불명
    public let versionSource: String
    public let supportLevel: String    // "supported" | "limited" | "unsupported"
    public init(status: Status, version: String?, versionSource: String, supportLevel: String) {
        self.status = status; self.version = version; self.versionSource = versionSource; self.supportLevel = supportLevel
    }
}

enum AdapterUtil {
    static func exists(_ p: String) -> Bool { (try? SafeFile.lstat(p)) != nil }
    static func semver(in path: String) -> String? {
        let re = try! NSRegularExpression(pattern: "(\\d+\\.\\d+\\.\\d+)")
        guard let m = re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)), let r = Range(m.range(at: 1), in: path) else { return nil }
        return String(path[r])
    }
    static func readlink(_ p: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: p)
    }
    static func emitInstall(_ ctx: AdapterContext, agent: String, install: AgentInstall, prov: Provenance) {
        let aid = "agent:\(agent)"
        ctx.emit(aid, .agent, "install_status", install.status.rawValue, prov: prov)
        ctx.emit(aid, .agent, "version", install.version ?? "unknown", kind: install.version == nil ? .unknown : .literal, prov: prov)
        ctx.emit(aid, .agent, "version_source", install.versionSource, prov: prov)
        ctx.emit(aid, .agent, "support_level", install.supportLevel, prov: prov)
        ctx.emit(aid, .agent, "static_support", "true", prov: prov)
        ctx.emit(aid, .agent, "activity_support", agent == "claude-code" ? "candidate_hook" : "not_observed", prov: prov)
    }
}
