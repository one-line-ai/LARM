import Foundation

/// 점검 보고서 내보내기.
public struct ExportPreview: Sendable {
    public let scanID: String
    public let scanStatus: String
    public let scopeAliases: [String]
    public let openFindings: Int
    public let exceptions: Int
    public let gaps: Int
    public let diffEntries: Int
    public let hasBaseline: Bool
    public let files: [String]
}

public struct ExportInput {
    public let scanID: String
    public let scanSummary: ScanSummary
    public let scopes: [Scope]
    public let coverage: [Coverage]
    public let observations: [Observation]
    public let findings: [Finding]
    public let decisions: [Decision]
    public let diff: [DiffEntry]
    public let baselineScanID: String?
    public let versions: [String: String]
    public let filters: [String: String]
    public let installationID: String
    public var events: [RuntimeEvent] = []
    public var gaps: [CoverageGap] = []
    public init(scanID: String, scanSummary: ScanSummary, scopes: [Scope], coverage: [Coverage], observations: [Observation], findings: [Finding],
                decisions: [Decision], diff: [DiffEntry], baselineScanID: String?, versions: [String: String], filters: [String: String], installationID: String,
                events: [RuntimeEvent] = [], gaps: [CoverageGap] = []) {
        self.scanID = scanID; self.scanSummary = scanSummary; self.scopes = scopes; self.coverage = coverage; self.observations = observations
        self.findings = findings; self.decisions = decisions; self.diff = diff; self.baselineScanID = baselineScanID; self.versions = versions
        self.filters = filters; self.installationID = installationID; self.events = events; self.gaps = gaps
    }
}

public enum Exporter {
    public static let schema = "larm-evidence/1.1"
    public static let fileOrder = ["summary.html", "inventory.json", "coverage.json", "findings.json", "diff.json", "decisions.json", "versions.json",
                            "graph.json", "events.json", "coverage_gaps.json", "action_results.json", "README.txt"]

    public static func preview(_ i: ExportInput) -> ExportPreview {
        ExportPreview(scanID: i.scanID, scanStatus: i.scanSummary.status.rawValue, scopeAliases: i.scopes.map { $0.alias },
                      openFindings: i.findings.filter { $0.state == .open || $0.state == .inProgress }.count,
                      exceptions: i.findings.filter { $0.state == .excepted }.count,
                      gaps: i.coverage.filter { $0.status != .success && $0.status != .absent }.count,
                      diffEntries: i.diff.count, hasBaseline: i.baselineScanID != nil, files: ["manifest.json"] + fileOrder)
    }

    public static func build(_ i: ExportInput, now: String = Clock.nowUTC()) throws -> (Data, String, String) {
        let exportID = Ids.new("exp")
        var files: [(String, Data)] = []
        let scopeAlias = Dictionary(i.scopes.map { ($0.scopeID, $0.alias) }, uniquingKeysWith: { a, _ in a })

        var objects: [String: [String: Any]] = [:]
        for o in i.observations where o.field != "in_file" {
            var obj = objects[o.objectID] ?? ["object_id": o.objectID, "object_type": o.objectType.rawValue, "scope": scopeAlias[o.provenance.scopeID] ?? o.provenance.scopeID,
                                              "location": o.provenance.locationAlias, "adapter": o.provenance.adapter, "adapter_version": o.provenance.adapterVersion, "fields": [String: Any]()]
            var fields = obj["fields"] as! [String: Any]
            fields[o.field] = ["value": o.valueKind == .redacted ? "[제거됨]" : o.safeValue, "kind": o.valueKind.rawValue]
            obj["fields"] = fields
            objects[o.objectID] = obj
        }
        let inventory: [String: Any] = ["schema": "larm-inventory/1.1", "scan_id": i.scanID, "observed_at": i.scanSummary.endedAt,
                                        "scopes": i.scopes.map { ["scope_id": $0.scopeID, "alias": $0.alias, "kind": $0.kind.rawValue, "excluded": $0.excluded] },
                                        "objects": objects.keys.sorted().map { objects[$0]! }]
        files.append(("inventory.json", try StableJSON.data(inventory)))
        files.append(("coverage.json", try StableJSON.data(["schema": "larm-coverage/1.1", "scan_id": i.scanID, "scan_status": i.scanSummary.status.rawValue,
            "items": i.coverage.map { ["adapter": $0.adapter, "adapter_version": $0.adapterVersion, "scope": scopeAlias[$0.scopeID] ?? $0.scopeID, "item": $0.itemAlias, "status": $0.status.rawValue, "reason": $0.reason] }])))
        files.append(("findings.json", try StableJSON.data(["schema": "larm-findings/1.1", "scan_id": i.scanID,
            "items": i.findings.map { f -> [String: Any] in
                ["finding_id": f.findingID, "rule_id": f.ruleID, "rule_version": f.ruleVersion, "object_id": f.objectID, "object_type": f.objectType.rawValue,
                 "severity": f.severity.rawValue, "confidence": f.confidence.rawValue, "title": f.title, "summary": f.summary, "state": f.state.rawValue,
                 "verify_status": f.verifyStatus, "location": f.locationAlias, "scope": scopeAlias[f.scopeID] ?? f.scopeID, "evidence_ref": f.evidence,
                 "limits": f.limits, "next_action": f.nextAction, "first_scan_id": f.firstScanID, "last_scan_id": f.lastScanID, "seen_count": f.seenCount,
                 "opened_at": f.openedAt, "updated_at": f.updatedAt] }])))
        files.append(("diff.json", try StableJSON.data(["schema": "larm-diff/1.1", "scan_id": i.scanID, "baseline_scan_id": orNull(i.baselineScanID),
            "note": i.baselineScanID == nil ? "기준 상태이 없어 비교하지 않았음" : "기준 상태 대비 비교. 읽기 실패·범위 제거는 삭제가 아니라 비교 불가임",
            "entries": i.diff.map { ["object_id": $0.objectID, "object_type": $0.objectType.rawValue, "field": $0.field, "change": $0.change.rawValue,
                                     "before": orNull($0.before), "after": orNull($0.after), "location": $0.locationAlias, "secret_changed": $0.secretChanged, "reason": $0.reason] }])))
        files.append(("decisions.json", try StableJSON.data(["schema": "larm-decisions/1.1",
            "items": i.decisions.map { ["decision_id": $0.decisionID, "kind": $0.kind, "finding_id": orNull($0.findingID), "object_id": orNull($0.objectID),
                                        "scan_id": orNull($0.scanID), "actor": $0.actorAlias, "reason": $0.reason, "created_at": $0.createdAt,
                                        "expires_at": orNull($0.expiresAt), "rule_version": $0.ruleVersion, "active": $0.active] }])))
        var versions = i.versions
        versions["schema"] = schema
        versions["ontology"] = Ontology.version
        files.append(("versions.json", try StableJSON.data(versions)))
        let graph = GraphBuilder().build(observations: i.observations, findings: i.findings, scopes: i.scopes, scanID: i.scanID)
        files.append(("graph.json", try StableJSON.data(["schema": "larm-graph/1.1", "ontology_version": graph.ontologyVersion, "scan_id": i.scanID,
            "nodes": graph.nodes.map { n -> [String: Any] in ["id": n.id, "type": n.type.rawValue, "label": n.label, "scope": scopeAlias[n.scopeID] ?? n.scopeID,
                                                             "severity": orNull(n.severity), "state": orNull(n.state)] },
            "edges": graph.edges.map { ["id": $0.id, "type": $0.type.rawValue, "from": $0.from, "to": $0.to, "evidence_ref": $0.evidenceRef, "scan_id": $0.scanID,
                                        "epistemic_status": $0.epistemic.rawValue, "confidence": $0.confidence, "schema_version": $0.schemaVersion] },
            "rejected_edges": graph.rejected])))
        files.append(("events.json", try StableJSON.data(["schema": "larm-events/1.1", "note": "Claude Code hook 확인 활동 기록 (확인 전용). 원문 prompt·명령 내용 제외. 항목 없음은 미확인을 뜻하며 안전을 뜻하지 않는다.",
            "items": i.events.map { e -> [String: Any] in
                ["event_id": e.eventID, "source_event_id": e.sourceEventID, "source_kind": "claude-code-hook", "phase": e.phase, "hook_event_name": e.hookEventName,
                 "tool_name": e.toolName, "target_kind": e.targetKind, "target_alias": e.targetAlias, "scope": e.scopeID.map { scopeAlias[$0] ?? $0 } ?? NSNull(),
                 "outside_scope": e.outsideScope, "command_basename": orNull(e.commandBasename), "argc": e.argc, "arg_fp": e.argFingerprint, "flags": e.flags,
                 "session_ref": String(e.sessionRef.prefix(8)), "process_ref": e.processRef, "observed_at": e.observedAt, "received_at": e.receivedAt, "seq": e.seq,
                 "delivery": e.delivery, "result_present": e.resultPresent, "duplicate_count": e.duplicateCount,
                 "risk": e.riskRule.map { ["rule_id": $0, "outcome": e.riskOutcome ?? "", "severity": e.riskSeverity ?? "", "summary": e.riskSummary ?? ""] as [String: Any] } ?? NSNull(),
                 "ack_state": e.ackState] }])))
        files.append(("coverage_gaps.json", try StableJSON.data(["schema": "larm-coverage-gaps/1.1", "note": "감시가 끊긴 구간. 계획 중지·장애·유실을 구분하며 확인 못 한 구간 중 행위는 미확인이다.",
            "items": i.gaps.map { ["gap_id": $0.gapID, "surface": $0.surface, "started_at": $0.startedAt, "ended_at": orNull($0.endedAt), "reason": $0.reason, "lost_count": $0.lostCount, "recovery_evidence": $0.recoveryEvidence] }])))
        files.append(("action_results.json", try StableJSON.data(["schema": "larm-action-results/1.1", "note": "집행 결과 없음: 실행 전 확인·정책 집행(F42/F43)은 제공하지 않는다 (확인 모드). 결과 활동 기록 존재는 events.json의 result_present로만 표시한다.",
            "items": i.events.filter { $0.phase == "result" }.map { ["request_id": $0.sourceEventID, "result_type": "result_event_observed", "enforcement_ack": false, "evidence_ref": $0.eventID] }])))
        files.append(("summary.html", Data(summaryHTML(i, exportID: exportID, now: now, scopeAlias: scopeAlias).utf8)))
        files.append(("README.txt", Data(readme(exportID: exportID).utf8)))
        files.sort { fileOrder.firstIndex(of: $0.0)! < fileOrder.firstIndex(of: $1.0)! }
        let home = NSHomeDirectory()
        files = files.map { (name, data) in
            guard var text = String(data: data, encoding: .utf8), text.contains(home) else { return (name, data) }
            text = text.replacingOccurrences(of: home + "/", with: "~/").replacingOccurrences(of: home, with: "~")
            return (name, Data(text.utf8))
        }
        let manifest: [String: Any] = [
            "schema_version": schema, "export_id": exportID, "generated_at": now, "generated_tz": Clock.localTimeZoneID,
            "installation_id": i.installationID, "scan_ids": [i.scanID], "baseline_scan_id": orNull(i.baselineScanID),
            "filters": i.filters, "versions": versions,
            "files": files.map { ["path": $0.0, "size": $0.1.count, "sha256": Hashing.sha256Hex($0.1)] },
        ]
        let manifestData = try StableJSON.data(manifest)
        let entries = [ZipEntry(path: "manifest.json", data: manifestData)] + files.map { ZipEntry(path: $0.0, data: $0.1) }
        return (try ZipWriter.write(entries), exportID, Hashing.sha256Hex(manifestData))
    }

    static func orNull(_ s: String?) -> Any { s.map { $0 as Any } ?? NSNull() }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func summaryHTML(_ i: ExportInput, exportID: String, now: String, scopeAlias: [String: String]) -> String {
        let open = i.findings.filter { $0.state == .open || $0.state == .inProgress }
        let gaps = i.coverage.filter { $0.status != .success && $0.status != .absent }
        var h = """
        <!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>LARM 보고서 요약</title>
        <style>body{font-family:-apple-system,"Apple SD Gothic Neo",sans-serif;max-width:900px;margin:2em auto;padding:0 1em;color:#111}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:4px 6px;text-align:left;font-size:13px}h1,h2{color:#000}.warn{color:#a00}</style></head><body>
        <h1>LARM 보고서 요약</h1>
        <p>export_id: \(esc(exportID)) · 생성 \(esc(now)) (UTC) · schema \(schema)</p>
        <h2>확인 범위·시점</h2>
        <p>점검 \(esc(i.scanID)) · 상태 <b>\(esc(i.scanSummary.status.label))</b> · 시작 \(esc(i.scanSummary.startedAt)) · 종료 \(esc(i.scanSummary.endedAt)) · 룰 \(esc(i.scanSummary.rulesVersion))</p>
        <p>범위: \(i.scopes.map { esc($0.alias) }.joined(separator: ", ")) (선택 범위이며 전체 시스템이 아님)</p>
        \(i.scanSummary.status != .complete ? "<p class=\"warn\">부분 결과임. 전체 완료로 해석하지 마기.</p>" : "")
        <h2>집계</h2>
        <table><tr><th>열린 위험</th><th>조치 중</th><th>다시 점검해 해결됨</th><th>예외</th><th>잘못된 탐지 검토</th><th>확인 못 한 항목</th><th>변경 항목</th></tr>
        <tr><td>\(open.filter { $0.state == .open }.count)</td><td>\(open.filter { $0.state == .inProgress }.count)</td><td>\(i.findings.filter { $0.state == .resolvedByRescan }.count)</td><td>\(i.findings.filter { $0.state == .excepted }.count)</td><td>\(i.findings.filter { $0.state == .falsePositiveReview }.count)</td><td>\(gaps.count)</td><td>\(i.diff.count)</td></tr></table>
        <p>위험과 공백을 가중 합산한 단일 점수는 만들지 않음.</p>
        <h2>열린 위험</h2><table><tr><th>심각도</th><th>룰</th><th>위치</th><th>요약</th><th>상태</th></tr>
        """
        for f in open.sorted(by: { $0.severity > $1.severity }) {
            h += "<tr><td>\(esc(f.severity.label))</td><td>\(esc(f.ruleID)) \(esc(f.title))</td><td>\(esc(f.locationAlias))</td><td>\(esc(f.summary))</td><td>\(esc(f.state.label))\(f.verifyStatus == "unverifiable" ? " (검증 불가)" : "")</td></tr>"
        }
        h += "</table><h2>예외 (위험을 알고 예외로 둠)</h2><table><tr><th>룰</th><th>위치</th><th>만료</th><th>사유</th></tr>"
        for f in i.findings where f.state == .excepted {
            let d = i.decisions.first { $0.kind == "exception" && $0.findingID == f.findingID && $0.active }
            h += "<tr><td>\(esc(f.ruleID))</td><td>\(esc(f.locationAlias))</td><td>\(esc(String((d?.expiresAt ?? "").prefix(10))))</td><td>\(esc(d?.reason ?? ""))</td></tr>"
        }
        h += "</table><h2>확인 못 한 항목</h2><table><tr><th>읽기 모듈</th><th>항목</th><th>상태</th><th>사유</th></tr>"
        for c in gaps { h += "<tr><td>\(esc(c.adapter))</td><td>\(esc(c.itemAlias))</td><td>\(esc(c.status.rawValue))</td><td>\(esc(c.reason))</td></tr>" }
        h += "</table><h2>기준 상태 대비 변경</h2>"
        if let b = i.baselineScanID {
            h += "<p>기준 상태 점검 \(esc(b)) 대비 \(i.diff.count)건 (추가 \(i.diff.filter { $0.change == .added }.count) · 삭제 \(i.diff.filter { $0.change == .removed }.count) · 수정 \(i.diff.filter { $0.change == .modified }.count) · 비교 불가 \(i.diff.filter { $0.change == .incomparable }.count))</p>"
        } else { h += "<p>기준 상태이 없어 비교하지 않았음.</p>" }
        h += """
        <h2>검증 한계</h2>
        <ul><li>정적 설정 확인이며 실제 실행·통신·유출을 확정하지 않음.</li>
        <li>비밀정보 후보는 형식 판단이며 유효성은 미확인임. 원문 값은 포함하지 않음.</li>
        <li>파일 검증 성공은 묶음 내부 일관성이며 생성자 신원·시점 공증이 아님.</li>
        <li>활동 활동 기록은 Claude Code hook이 등록된 세션의 요청·결과 기록만 담음 (\(i.events.count)건). 집행 결과는 없음 (확인 모드).</li>
        <li>감시가 끊긴 구간 \(i.gaps.count)건 기록. 공백 중 행위는 미확인임.</li></ul>
        </body></html>
        """
        return h
    }

    static func readme(exportID: String) -> String {
        """
        LARM 점검 보고서 (\(schema)) · export_id \(exportID)

        [오프라인 검증 절차]
        1. 인터넷·LARM 계정 없이 larm-verify 를 실행함:
             /Applications/LARM.app/Contents/MacOS/larm-verify <이 파일.zip>
           또는 수동으로: manifest.json 의 files[] 에 적힌 경로·크기·SHA-256 을 각 파일과 대조함 (shasum -a 256).
        2. 성공은 "manifest 에 적힌 파일과 묶음의 파일이 일치함" 임. 생성자 신원, 확인 사실의 진실성, 시점 공증, 악성 여부, 법규 준수를 증명하지 않음.
        3. manifest 까지 재작성한 위조는 별도 매체에 보관한 manifest SHA-256 과 대조해야 검출됨 (--expect-manifest-sha256).

        [호환 버전] schema larm-evidence/1.1 (1.0 정적 보고서과 구분). ZIP 은 저장 방식(무압축)만 사용함.

        [개인정보 취급] 원문 토큰·비밀값·raw args·URL query·사용자명·기기 일련번호를 포함하지 않음. 경로는 별칭임.
        내보낸 사본은 앱의 보존 정책과 별개이며 수신자가 관리함.

        [파일] manifest.json, summary.html(사람이 읽는 요약), inventory.json, coverage.json, findings.json, diff.json, decisions.json,
        versions.json, graph.json, events.json, coverage_gaps.json, action_results.json (이 빌드에서는 미수집), README.txt
        """
    }
}
