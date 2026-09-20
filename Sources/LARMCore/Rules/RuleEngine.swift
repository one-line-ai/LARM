import Foundation

/// 결정론 룰 엔진.
public struct RuleEngine {
    public let rules: RuleSet
    public init(rules: RuleSet) { self.rules = rules }

    struct ObjectView {
        let id: String
        let type: ObjectType
        var fields: [String: (value: String, kind: ValueKind, obsID: String)] = [:]
        var locationAlias = ""
        var scopeID = ""
    }

    public func evaluate(observations: [Observation], coverage: [Coverage]) -> [Verdict] {
        var objects: [String: ObjectView] = [:]
        var order: [String] = []
        for o in observations {
            if objects[o.objectID] == nil {
                objects[o.objectID] = ObjectView(id: o.objectID, type: o.objectType, locationAlias: o.provenance.locationAlias, scopeID: o.provenance.scopeID)
                order.append(o.objectID)
            }
            if let ex = objects[o.objectID]!.fields[o.field], ex.kind != .unknown, o.valueKind == .unknown { continue }
            objects[o.objectID]!.fields[o.field] = (o.safeValue, o.valueKind, o.observationID)
        }
        var out: [Verdict] = []
        for rule in rules.rules.sorted(by: { $0.id < $1.id }) {
            for oid in order {
                let obj = objects[oid]!
                guard obj.type == rule.target else { continue }
                if let v = evaluate(rule: rule, object: obj) { out.append(v) }
            }
        }
        for c in coverage where c.status != .success && c.status != .absent {
            let oid = "cov:\(c.adapter):\(c.itemAlias)"
            out.append(Verdict(ruleID: "R08", ruleVersion: rules.version, objectID: oid, objectType: .coverageItem, outcome: .positive,
                               severity: .gap, confidence: .high, title: "점검 범위·가시성 공백",
                               summary: "\(c.itemAlias): \(statusLabel(c.status)) (\(c.reason))", evidence: [],
                               limits: "찾지 못한 것을 존재하지 않는 것으로 바꾸지 않는다. 위험 점수에 합산하지 않는다.",
                               nextAction: "오류 해결·범위 재선택·지원 업데이트 후 재점검", scopeID: c.scopeID, locationAlias: c.itemAlias))
        }
        return out
    }

    func statusLabel(_ s: CoverageStatus) -> String {
        switch s { case .success: return "성공"; case .absent: return "부재"; case .denied: return "접근 거절"; case .oversize: return "상한 초과"
        case .unsupported: return "미지원"; case .error: return "오류" }
    }

    func evaluate(rule: RuleSpec, object: ObjectView) -> Verdict? {
        func base(_ outcome: Outcome, _ sev: Severity, _ conf: Confidence, _ summary: String, _ evidence: [String]) -> Verdict {
            Verdict(ruleID: rule.id, ruleVersion: rules.version, objectID: object.id, objectType: object.type, outcome: outcome,
                    severity: sev, confidence: conf, title: rule.title, summary: summary, evidence: evidence, limits: rule.limits,
                    nextAction: rule.nextAction, scopeID: object.scopeID, locationAlias: object.locationAlias)
        }
        if let uw = rule.unknownWhen, uw.contains(where: { test($0, object) }) {
            let ev = uw.compactMap { object.fields[$0.field]?.obsID }
            return base(.unknown, .gap, .low, "판단 보류: 필요한 값을 확인하지 못했습니다 (\(uw.map { $0.field }.joined(separator: ", ")))", ev)
        }
        for v in rule.verdicts {
            if v.when.allSatisfy({ test($0, object) }) {
                let ev = v.when.compactMap { object.fields[$0.field]?.obsID }
                return base(.positive, v.severity, v.confidence, v.summary, ev)
            }
        }
        return nil
    }

    func test(_ p: Predicate, _ obj: ObjectView) -> Bool {
        let f = obj.fields[p.field]
        switch p.op {
        case .present: return f != nil
        case .absent: return f == nil
        case .isUnknown: return f == nil || f!.kind == .unknown
        default: break
        }
        guard let f, f.kind != .unknown else { return false }
        let v = f.value
        switch p.op {
        case .eq: return v == p.value?.stringValue
        case .neq: return v != p.value?.stringValue
        case .in: return p.value?.strings.contains(v) ?? false
        case .notIn: return !(p.value?.strings.contains(v) ?? false)
        case .contains: return p.value?.stringValue.map { v.contains($0) } ?? false
        case .glob:
            guard let g = p.value?.stringValue else { return false }
            return fnmatch(g, v, 0) == 0
        case .gte:
            guard let n = p.value.flatMap({ $0.stringValue }).flatMap(Double.init), let x = Double(v) else { return false }
            return x >= n
        default: return false
        }
    }
}
