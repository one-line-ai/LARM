import Foundation

/// 점검 오케스트레이터.
public final class Scanner {
    public let adapters: [Adapter]
    public let rules: RuleSet
    public let redactor: Redactor
    public let limits: Limits

    public init(adapters: [Adapter] = [ClaudeCodeAdapter(), CodexAdapter(), CursorAdapter()], rules: RuleSet, redactor: Redactor, limits: Limits = Limits()) {
        self.adapters = adapters; self.rules = rules; self.redactor = redactor; self.limits = limits
    }

    public var adapterVersions: [String: String] { Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0.version) }) }

    /// 기준점 관측·검토된 엔드포인트를 반영해 baseline_status / reviewed 필드를 도출한다.
    public struct Context {
        public var baselineObservations: [Observation]?
        public var reviewedEndpoints: Set<String>
        public init(baselineObservations: [Observation]? = nil, reviewedEndpoints: Set<String> = []) {
            self.baselineObservations = baselineObservations; self.reviewedEndpoints = reviewedEndpoints
        }
    }

    /// scopes: 사용자 루트 + 선택 프로젝트.
    public func run(scopes: [Scope], context: Context = Context(), isCancelled: () -> Bool = { false }) -> ScanResult {
        let scanID = Ids.new("scan")
        let started = Clock.nowUTC()
        let budget = ScanBudget(limits: limits)
        var coverage: [Coverage] = []
        var observations: [Observation] = []
        var notes: [String] = []
        var cancelled = false

        let active = scopes.filter { !$0.excluded }
        let projects = active.filter { $0.kind == .project }
        if projects.count > limits.maxProjects {
            notes.append("프로젝트 \(projects.count)개 중 상한 \(limits.maxProjects)개만 점검했음.")
        }
        let planned = active.filter { $0.kind == .userRoot } + projects.prefix(limits.maxProjects)

        outer: for scope in planned {
            for adapter in adapters {
                if isCancelled() { cancelled = true; break outer }
                let ctx = AdapterContext(scope: scope, budget: budget, redactor: redactor, adapter: adapter.id, adapterVersion: adapter.version)
                adapter.scan(ctx)
                coverage.append(contentsOf: ctx.coverage)
                observations.append(contentsOf: ctx.observations)
            }
        }
        for s in projects.dropFirst(limits.maxProjects) {
            coverage.append(Coverage(adapter: "scope", adapterVersion: "1", scopeID: s.scopeID, itemAlias: "<\(s.alias)>", status: .oversize, reason: "프로젝트 상한 초과"))
        }
        observations = derive(observations, context: context)
        let verdicts = RuleEngine(rules: rules).evaluate(observations: observations, coverage: coverage)
        let status: ScanStatus
        if cancelled { status = .cancelled }
        else if coverage.contains(where: { [.denied, .oversize, .unsupported, .error].contains($0.status) }) { status = .partial }
        else { status = .complete }
        if context.baselineObservations == nil { notes.append("기준 상태이 없어 MCP·hook 구성을 미검토로 표시함") }
        return ScanResult(scanID: scanID, status: status, startedAt: started, endedAt: Clock.nowUTC(), scopes: planned,
                          coverage: coverage, observations: observations, verdicts: verdicts, adapterVersions: adapterVersions,
                          rulesVersion: rules.version, notes: notes)
    }
}

extension Scanner {
    /// 도출 필드 갱신: baseline_status (new/changed/unchanged, 기준점 없으면 unknown 유지), reviewed (사용자 확인).
    func derive(_ obs: [Observation], context: Context) -> [Observation] {
        var out = obs
        let status = context.baselineObservations.map { Differ.baselineStatus(current: obs, baseline: $0) }
        for (i, o) in obs.enumerated() {
            if o.field == "baseline_status", let st = status?[o.objectID] {
                out[i] = Observation(objectID: o.objectID, objectType: o.objectType, field: o.field, safeValue: st, valueKind: .literal, provenance: o.provenance)
            } else if o.field == "reviewed", context.reviewedEndpoints.contains(o.objectID) {
                out[i] = Observation(objectID: o.objectID, objectType: o.objectType, field: o.field, safeValue: "true", valueKind: .literal, provenance: o.provenance)
            }
        }
        return out
    }
}
