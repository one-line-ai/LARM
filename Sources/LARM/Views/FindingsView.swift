import SwiftUI
import LARMCore

struct FindingsView: View {
    @EnvironmentObject var state: AppState
    @State private var severity: Severity? = nil
    @State private var fstate: FindingState? = .open
    @State private var agent: String = "all"
    @State private var scopeID: String = "all"
    @State private var query = ""

    var filtered: [Finding] {
        state.findings.filter { f in
            (severity == nil || f.severity == severity!) &&
            (fstate == nil || f.state == fstate! || (fstate == .open && f.state == .inProgress)) &&
            (agent == "all" || f.objectID.contains(":\(agent):") || f.objectID.hasPrefix("agent:\(agent)") || f.locationAlias.contains(agentPath(agent))) &&
            (scopeID == "all" || f.scopeID == scopeID) &&
            (query.isEmpty || f.title.localizedCaseInsensitiveContains(query) || f.locationAlias.localizedCaseInsensitiveContains(query) || f.ruleID.localizedCaseInsensitiveContains(query) || f.summary.localizedCaseInsensitiveContains(query))
        }
    }
    func agentPath(_ a: String) -> String { a == "claude-code" ? ".claude" : a == "codex" ? ".codex" : ".cursor" }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filters
                if filtered.isEmpty {
                    VStack(spacing: 6) {
                        Text(state.findings.isEmpty ? "아직 발견 사항이 없습니다." : "조건에 맞는 발견 사항이 없습니다.").foregroundStyle(.secondary)
                        if !state.findings.isEmpty && fstate != nil { Button("전체 상태 보기") { fstate = nil } }
                        if state.lastScan == nil { Text("오른쪽 위 '점검'을 누르세요.").font(.footnote).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                List(selection: $state.selectedFindingID) {
                    ForEach(filtered) { f in
                        HStack(alignment: .top) {
                            SeverityBadge(severity: f.severity)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(f.ruleID) \(f.title)").bold()
                                Text(f.summary).font(.callout).lineLimit(2)
                                HStack {
                                    Text(f.locationAlias).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    StateBadge(state: f.state)
                                    if f.verifyStatus == "unverifiable" { Text("검증 불가").font(.caption).foregroundStyle(.orange) }
                                    if f.verifyStatus == "scope_removed" { Text("범위 제거됨").font(.caption).foregroundStyle(.orange) }
                                    if f.seenCount > 1 { Text("\(f.seenCount)회").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }.tag(f.findingID)
                    }
                }
                Text("전체 \(state.findings.count)건 · 필터 후 \(filtered.count)건").font(.footnote).foregroundStyle(.secondary).padding(6)
            }.frame(minWidth: 300)
            Group {
                if let id = state.selectedFindingID, let f = state.findings.first(where: { $0.findingID == id }) {
                    FindingDetailView(finding: f)
                } else {
                    Text("발견 사항을 선택하세요").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minWidth: 360)
        }
    }

    var filters: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("심각도", selection: $severity) {
                    Text("전체").tag(Severity?.none)
                    ForEach([Severity.high, .medium, .low, .gap], id: \.self) { Text($0.label).tag(Severity?.some($0)) }
                }
                Picker("상태", selection: $fstate) {
                    Text("열림+조치 중").tag(FindingState?.some(.open))
                    Text("전체").tag(FindingState?.none)
                    ForEach([FindingState.inProgress, .resolvedByRescan, .excepted, .falsePositiveReview], id: \.self) { Text($0.label).tag(FindingState?.some($0)) }
                }
            }
            HStack {
                Picker("에이전트", selection: $agent) {
                    Text("전체").tag("all"); Text("Claude Code").tag("claude-code"); Text("Codex").tag("codex"); Text("Cursor").tag("cursor")
                }
                Picker("범위", selection: $scopeID) {
                    Text("전체").tag("all")
                    ForEach(state.scopes) { Text($0.kind == .userRoot ? "사용자" : $0.alias).tag($0.scopeID) }
                }
            }
            TextField("검색 (룰, 위치, 요약)", text: $query).textFieldStyle(.roundedBorder)
        }.padding(8)
    }
}

/// 근거를 읽을 수 있는 상세 + 수동 조치 안내.
struct FindingDetailView: View {
    @EnvironmentObject var state: AppState
    let finding: Finding
    @State private var showAllObs = false
    @State private var exceptionDays = DecisionRepo.defaultExceptionDays
    @State private var exceptionReason = ""
    @State private var reviewReason = ""
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { SeverityBadge(severity: finding.severity); Text("\(finding.ruleID) \(finding.title)").font(.title3.bold()); StateBadge(state: finding.state) }
                Text(finding.summary).textSelection(.enabled)
                LabeledContent("신뢰도", value: finding.confidence.label)
                LabeledContent("위치", value: finding.locationAlias)
                LabeledContent("대상", value: finding.objectID)
                LabeledContent("범위", value: state.scopeAlias(finding.scopeID))
                LabeledContent("룰 버전", value: finding.ruleVersion)
                LabeledContent("최초 / 최근", value: "\(Fmt.local(finding.openedAt)) / \(Fmt.local(finding.updatedAt)) · \(finding.seenCount)회")
                if finding.verifyStatus == "unverifiable" {
                    Text("재점검으로 확인하지 못했습니다 (대상을 읽지 못함). 해소로 표시하지 않습니다.").foregroundStyle(.orange)
                }
                if finding.verifyStatus == "scope_removed" {
                    Text("재점검으로 확인하지 못했습니다 (범위가 제거됨). 동일 범위를 다시 등록한 뒤 재점검하세요.").foregroundStyle(.orange)
                }
                if finding.state == .excepted, let d = state.exception(for: finding) {
                    Text("위험 수용 · 만료 \(String((d.expiresAt ?? "").prefix(10))) · 사유 \"\(d.reason)\" · 구성이나 룰이 바뀌면 재검토합니다.").foregroundStyle(.purple)
                }
                GroupBox("확인한 값") {
                    let obs = state.observations(for: finding)
                    let ev = Set(finding.evidence)
                    let shown = showAllObs ? obs : obs.filter { ev.contains($0.observationID) || ev.isEmpty }
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(shown) { o in
                            HStack(alignment: .top) {
                                Text(o.field).font(.system(.callout, design: .monospaced)).frame(width: 190, alignment: .leading)
                                Text(o.safeValue).font(.callout).textSelection(.enabled)
                                if o.valueKind == .unknown { Text("확인 안 됨").font(.caption).foregroundStyle(.orange) }
                                if o.valueKind == .redacted { Text("유효성 미확인").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        if let p = obs.first?.provenance {
                            Text("출처: \(p.locationAlias) · 우선순위 \(p.precedence) · \(p.interpretation) · 어댑터 \(p.adapter) \(p.adapterVersion)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle("이 항목의 모든 값 보기", isOn: $showAllObs).font(.footnote)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("한계") { Text(finding.limits).frame(maxWidth: .infinity, alignment: .leading) }
                GroupBox("다음 단계") { Text(finding.nextAction).bold().frame(maxWidth: .infinity, alignment: .leading) }
                GroupBox("수동 조치 안내") {
                    Text(state.guidance(for: finding.ruleID)).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                actions
                decisionsBox
                if let m = actionMessage { Text(m).font(.footnote).foregroundStyle(.orange) }
                GroupBox("이력") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.events(for: finding).enumerated()), id: \.offset) { _, e in
                            Text("\(Fmt.local(e.at)) · \(e.actor) · \(e.kind) \(e.from ?? "")→\(e.to ?? "") · \(e.note)").font(.footnote)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(16)
        }
    }

    var decisionsBox: some View {
        GroupBox("예외와 검토") {
            VStack(alignment: .leading, spacing: 8) {
                if finding.state == .open || finding.state == .inProgress {
                    HStack {
                        Picker("기한", selection: $exceptionDays) { ForEach([7, 14, 30], id: \.self) { Text("\($0)일").tag($0) } }.frame(maxWidth: 140)
                        TextField("예외 사유 (필수)", text: $exceptionReason).textFieldStyle(.roundedBorder)
                        Button("기한을 정해 예외 처리") {
                            actionMessage = state.addException(finding, days: exceptionDays, reason: exceptionReason); exceptionReason = ""
                        }
                    }
                    Text("예외는 위험을 알고 받아들이는 것이며 해결된 것이 아닙니다. 기본 7일, 최대 30일이고, 기한이 지나거나 설정이 바뀌면 다시 열립니다.").font(.footnote).foregroundStyle(.secondary)
                }
                if finding.ruleID == "R06", finding.state != .resolvedByRescan {
                    HStack {
                        TextField("검토 기록 (예: 사내 프록시, 소유자 확인)", text: $reviewReason).textFieldStyle(.roundedBorder)
                        Button("엔드포인트 검토 완료") { actionMessage = state.markEndpointReviewed(finding, reason: reviewReason); reviewReason = "" }
                    }
                    Text("같은 주소(scheme, host, port)에만 적용되며 평문 HTTP는 검토로 해결되지 않습니다. 다음 재점검부터 반영됩니다.").font(.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var actions: some View {
        HStack {
            if finding.state == .open {
                Button("조치 중으로 표시") { state.transition(finding, to: .inProgress, note: "사용자가 조치 시작") }
            }
            if finding.state == .inProgress {
                Button("열림으로 되돌리기") { state.transition(finding, to: .open, note: "사용자가 되돌림") }
            }
            if finding.state != .falsePositiveReview && finding.state != .resolvedByRescan {
                Button("오탐 검토 요청") { state.transition(finding, to: .falsePositiveReview, note: "사용자가 오탐으로 판단") }
            }
            Button { state.runScan(kind: "rescan", onlyScopeIDs: [finding.scopeID]) } label: { Label("재점검 (이 범위)", systemImage: "arrow.clockwise") }
                .disabled(state.scanning)
            Button("안내 복사") {
                let text = "\(finding.ruleID) \(finding.title)\n\(finding.summary)\n위치: \(finding.locationAlias)\n다음 단계: \(finding.nextAction)\n\n\(state.guidance(for: finding.ruleID))"
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Redactor.scrub(text), forType: .string)
            }
        }
    }
}
