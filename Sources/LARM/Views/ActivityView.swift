import SwiftUI
import LARMCore

/// 지원 AI 활동.
struct ActivityView: View {
    @EnvironmentObject var state: AppState
    @State private var phase = "request"
    @State private var onlyRisk = false
    @State private var selected: String?

    var items: [RuntimeEvent] {
        state.events.filter { (phase == "all" || $0.phase == phase) && (!onlyRisk || $0.riskRule != nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 활동 (Claude Code)").font(.title2.bold())
            hookBox
            HStack {
                Picker("단계", selection: $phase) {
                    Text("요청").tag("request"); Text("결과").tag("result"); Text("세션").tag("session_start"); Text("시험").tag("test"); Text("전체").tag("all")
                }.frame(maxWidth: 320)
                Toggle("위험 표시된 이벤트만", isOn: $onlyRisk)
                Spacer()
                Picker("활동 보존", selection: Binding(get: { state.eventRetentionDays }, set: { state.setEventRetention($0) })) {
                    ForEach([7, 30, 90], id: \.self) { Text("\($0)일").tag($0) }
                }.frame(maxWidth: 160)
            }
            Text("원문 프롬프트, 인자, 파일 내용은 수집하지 않습니다. 명령은 종류, 인자 개수, 지문, 플래그만, 경로는 별칭만 남깁니다. 보존 기간을 늘리면 저장량과 개인정보 영향이 커집니다.").font(.footnote).foregroundStyle(.secondary)
            if items.isEmpty {
                Text(state.events.isEmpty ? "기록된 이벤트가 없습니다. hook을 등록하면 새 Claude Code 세션부터 기록됩니다." : "조건에 맞는 이벤트가 없습니다.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 20)
            }
            HSplitView {
                Table(items, selection: $selected) {
                    TableColumn("시각") { (e: RuntimeEvent) in Text(Fmt.local(e.observedAt)) }.width(130)
                    TableColumn("단계") { (e: RuntimeEvent) in Text(e.phase) }.width(60)
                    TableColumn("도구") { (e: RuntimeEvent) in Text(e.toolName) }.width(90)
                    TableColumn("대상 별칭") { (e: RuntimeEvent) in Text(e.targetAlias).help(e.targetAlias) }
                    TableColumn("판단") { (e: RuntimeEvent) in
                        if let r = e.riskRule { Text("\(r) \(e.riskOutcome == "unknown" ? "보류" : (e.riskSeverity ?? ""))").foregroundStyle(e.riskSeverity == "high" ? Color.red : Color.orange) } else { Text("") }
                    }.width(90)
                    TableColumn("처리") { (e: RuntimeEvent) in Text(ack(e.ackState)) }.width(70)
                }.frame(minWidth: 380)
                detail.frame(minWidth: 280)
            }
        }.padding()
    }

    func ack(_ s: String) -> String { s == "observed" ? "안 함" : s == "acknowledged" ? "확인함" : s == "false_positive_review" ? "오탐 검토" : s }

    var hookBox: some View {
        GroupBox("연동 상태") {
            VStack(alignment: .leading, spacing: 6) {
                if let m = state.monitor {
                    HStack {
                        Text("Claude Code hook: ").bold()
                        Text(m.hookInstalled ? "등록됨" : "미등록")
                        Text("· 수신 소켓: \(m.health.activity.label)")
                        if let v = m.activityVerifiedAt { Text("· 시험 이벤트 확인 \(Fmt.elapsed(Clock.utc(v)))").foregroundStyle(.secondary) }
                        if let l = m.lastEventAt { Text("· 마지막 수신 \(Fmt.elapsed(Clock.utc(l)))").foregroundStyle(.secondary) }
                    }
                    HStack {
                        if m.hookInstalled { Button("hook 제거 (LARM 항목만)") { state.prepareHookInstall(remove: true) } }
                        else { Button("hook 등록 (변경 전후 확인)") { state.prepareHookInstall(remove: false) } }
                        Button("시험 이벤트 보내기") { state.sendTestEvent() }
                    }
                    Text("등록은 ~/.claude/settings.json의 hooks에 LARM 항목(PreToolUse, PostToolUse, SessionStart, SessionEnd)만 추가합니다. hook은 허용이나 차단 결정을 하지 않고 기록만 합니다. 앱이 꺼져 있으면 보관했다가 다음 실행 때 읽습니다. Codex와 Cursor의 활동은 지원하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let msg = state.hookMessage { Text(msg).font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $state.hookPlan) { plan in HookPlanSheet(plan: plan) }
    }

    var detail: some View {
        ScrollView {
            if let id = selected, let e = state.events.first(where: { $0.eventID == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(e.toolName) · \(e.phase)").font(.headline)
                    LabeledContent("대상 별칭", value: e.targetAlias.isEmpty ? "(없음)" : e.targetAlias)
                    LabeledContent("범위", value: e.scopeID.map { state.scopeAlias($0) } ?? (e.outsideScope ? "선택 범위 밖" : "-"))
                    if let b = e.commandBasename { LabeledContent("명령 종류", value: "\(b) · 인자 \(e.argc)개") }
                    LabeledContent("플래그", value: e.flags.isEmpty ? "없음" : e.flags.joined(separator: ", "))
                    LabeledContent("인자 지문", value: String(e.argFingerprint.prefix(16)) + "…")
                    LabeledContent("세션 / 프로세스", value: "\(e.sessionRef.prefix(8))… / \(e.processRef)")
                    LabeledContent("발생 시각 / 수신 시각", value: "\(Fmt.local(e.observedAt)) / \(Fmt.local(e.receivedAt))")
                    LabeledContent("전달", value: e.delivery + (e.duplicateCount > 0 ? " · 재전송 \(e.duplicateCount)회" : ""))
                    let linked = state.linkedEvents(e)
                    GroupBox("요청과 결과") {
                        VStack(alignment: .leading) {
                            ForEach(linked) { l in Text("\(l.phase) · \(Fmt.local(l.observedAt))\(l.phase == "result" ? " · 결과 이벤트 있음 (성공 여부는 도구 응답 기준 미해석)" : "")").font(.footnote) }
                            if !linked.contains(where: { $0.phase == "result" }) && e.phase == "request" {
                                Text("결과 이벤트 없음: 실행 여부 미확인. 실행 성공으로 표시하지 않습니다.").font(.footnote).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let r = e.riskRule {
                        GroupBox("판단 \(r) (룰 \(e.riskRule ?? "") v1.0.0)") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.riskOutcome == "unknown" ? "판단 보류" : "심각도 \(e.riskSeverity ?? "")").bold()
                                Text(e.riskSummary ?? "")
                                Text("한계: \(e.riskLimits ?? "")").font(.footnote).foregroundStyle(.secondary)
                                Text("다음 단계: \(e.riskNext ?? "")").font(.footnote)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            if e.ackState == "observed" { Button("확인함") { state.acknowledge(e, state: "acknowledged") } }
                            if e.ackState != "false_positive_review" { Button("오탐 검토") { state.acknowledge(e, state: "false_positive_review") } }
                            Text("확인해도 기록은 그대로 남습니다.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } else { Text("이벤트를 선택하세요").foregroundStyle(.secondary).padding() }
        }
    }
}

extension HookInstaller.Plan: Identifiable { public var id: String { Hashing.sha256Hex(after).prefix(16).description } }

struct HookPlanSheet: View {
    @EnvironmentObject var state: AppState
    let plan: HookInstaller.Plan
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.hookPlanIsRemoval ? "LARM hook 항목 제거: 변경 전후" : "Claude Code hook 등록: 변경 전후").font(.headline)
            Text("파일: ~/.claude/settings.json · 기존 hook과 다른 설정은 그대로 둡니다. 적용은 임시 파일 + rename으로 원자적으로 수행합니다.").font(.footnote).foregroundStyle(.secondary)
            ScrollView { Text(plan.diff).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("취소") { state.hookPlan = nil }
                Button(state.hookPlanIsRemoval ? "제거 적용" : "등록 적용") { state.applyHookPlan() }.keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 720, height: 420)
    }
}
