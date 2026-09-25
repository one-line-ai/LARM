import SwiftUI
import LARMCore

struct EvidenceSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var purgeMessage: String?
    @State private var autoStartMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("보고서와 설정").font(AppFont.title2)
                residentBox
                exportBox
                verifyBox
                retentionBox
                decisionsBox
                GroupBox("버전") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("앱 \(AppInfo.version) · \(AppInfo.osBuild) · 점검 규칙 \(state.rulesVersion) · 읽기 모듈 claude-code 1.0.0 / codex 1.0.0 / cursor 1.0.0 · 보고서 형식 \(Exporter.schema) · 온톨로지 \(Ontology.version)")
                        if let i = state.installation { Text("설치 ID \(i.installationID) · 키 ID \(i.keyID)").font(AppFont.footnote).foregroundStyle(Theme.inkSoft) }
                        Text("데이터 위치: \(Paths.supportDir.path)").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("진단, 점검 규칙 갱신") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("진단 파일 미리보기, 저장") { state.saveDiagnostics() }
                            Text("앱, 점검 규칙, OS 버전과 오류 코드만 포함. 프로젝트 경로, 설정 원문, 비밀정보, 기기 일련번호 없음 자동 전송하지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        DisclosureGroup("진단 내용 보기") { Text(state.diagnosticsText()).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.font(AppFont.footnote)
                        Divider()
                        HStack {
                            Button("서명된 점검 규칙 갱신 패키지 가져오기…") { state.importRuleUpdate() }
                            Button("번들 룰로 되돌리기") { state.rollbackRules() }
                            Text("현재 점검 규칙 \(state.rulesVersion). 서명, 형식, 버전 검사를 통과한 패키지만 원자적으로 전환함. 룰은 데이터이며 스크립트를 담을 수 없음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                        }
                        if let m = state.ruleUpdateMessage { Text(m).font(AppFont.footnote).foregroundStyle(Theme.indigoSoft) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("도움말") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• 읽는 위치: ~/.claude/settings.json, ~/.claude.json(mcpServers, projects[*].mcpServers만), 프로젝트 .claude/settings*.json, .mcp.json, ~/.codex/config.toml, 프로젝트 .codex/config.toml, ~/.cursor/mcp.json, 프로젝트 .cursor/mcp.json")
                        Text("• LARM은 설정, 파일, 프로세스, 네트워크를 자동 변경하지 않음 발견한 실행 파일을 실행하지 않음")
                        Text("• 업데이트: 새 빌드를 install.sh로 설치함. 제거: uninstall.sh (앱 데이터까지 지우려면 --purge)")
                        Text("• 오류 복구: 범위 재선택 → 재시도. '점검한 파일' 화면에서 사유 확인 가능")
                        Text("• 보고서 검증기: /Applications/LARM.app/Contents/MacOS/larm-verify <zip> [--expect-목록 파일(manifest)-sha256 <hex>]")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
    }

    var residentBox: some View {
        GroupBox("자동 감시와 알림") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("로그인 시 자동 시작", isOn: Binding(get: { state.autoStartEnabled }, set: { autoStartMessage = state.setAutoStart($0) }))
                    Text(state.autoStartStatus).font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
                if let m = autoStartMessage { Text(m).font(AppFont.footnote).foregroundStyle(Theme.indigoSoft) }
                Text("사용자가 시스템 설정에서 끄면 LARM은 되살리지 않음 재설치(서명 변경) 후에는 다시 켜야 할 수 있음.").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                Divider()
                HStack {
                    Toggle("macOS 알림 (신규 높은 위험, 감시가 끊긴 구간, 복구)", isOn: Binding(get: { state.notificationsEnabled }, set: { state.setNotifications($0) }))
                    Text(state.notifierReason).font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
                Text("같은 항목의 반복 알림은 24시간 동안 한 번만 보내고 건수는 기록함. 알림을 꺼도 감시는 계속됨. 알림에는 파일 이름, 프로젝트 이름, 토큰이 들어가지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                HStack {
                    Toggle("조용한 시간", isOn: Binding(get: { state.quietHours.enabled }, set: { var q = state.quietHours; q.enabled = $0; state.setQuietHours(q) }))
                    Picker("시작", selection: Binding(get: { state.quietHours.startHour }, set: { var q = state.quietHours; q.startHour = $0; state.setQuietHours(q) })) { ForEach(0..<24, id: \.self) { Text("\($0)시").tag($0) } }.frame(width: 110)
                    Picker("끝", selection: Binding(get: { state.quietHours.endHour }, set: { var q = state.quietHours; q.endHour = $0; state.setQuietHours(q) })) { ForEach(0..<24, id: \.self) { Text("\($0)시").tag($0) } }.frame(width: 110)
                    Text("조용한 시간에도 앱 내 위험, 확인 못 한 구간 배지는 유지됨").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var exportBox: some View {
        GroupBox("보고서 내보내기") {
            VStack(alignment: .leading, spacing: 6) {
                if let p = state.exportPreview() {
                    Text("미리보기: 점검 \(String(p.scanID.suffix(8))) (\(p.scanStatus)) · 범위 \(p.scopeAliases.joined(separator: ", ")) · 미조치 위험 \(p.openFindings) · 예외 \(p.exceptions) · 확인 못 한 구간 \(p.gaps) · 변경 \(p.diffEntries)\(p.hasBaseline ? "" : " (기준점 없음)")")
                    Text("포함 파일: \(p.files.joined(separator: ", "))").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    Text("비밀값, 요약값, 실제 경로, 사용자 이름은 들어가지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    Button { state.exportEvidence() } label: { Label("ZIP으로 내보내기", systemImage: "square.and.arrow.up") }
                } else {
                    Text("내보낼 점검 결과가 없음 먼저 점검하기").foregroundStyle(Theme.inkSoft)
                }
                if let m = state.lastExportMessage { Text(m).font(AppFont.footnote).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var verifyBox: some View {
        GroupBox("보고서 파일 검증") {
            VStack(alignment: .leading, spacing: 6) {
                Text("수신자는 인터넷, LARM 계정 없이 파일 목록, 크기, SHA-256을 검증함. 성공은 묶음 내부 일관성이며 신원, 시점 공증이 아님.").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                Button { state.verifyEvidenceFile() } label: { Label("ZIP 검증", systemImage: "checkmark.seal") }
                if let m = state.verifyMessage { Text(m).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var retentionBox: some View {
        GroupBox("보존과 삭제") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("정적 점검 이력 보존", selection: Binding(get: { state.retentionDays }, set: { state.setRetention($0) })) {
                        ForEach(Retention.choices, id: \.self) { Text("\($0)일").tag($0) }
                    }.frame(maxWidth: 260)
                    Button("만료 기록 지금 정리") { purgeMessage = state.purgeNow() }
                }
                Text("현재 기준 상태과 최신 점검은 보존 기간과 무관하게 유지함. 내보낸 사본은 앱 보존과 별개임").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                if let m = purgeMessage { Text(m).font(AppFont.footnote) }
                Divider()
                Button(role: .destructive) { state.fullReset() } label: { Label("전체 초기화 (기록, 기준 상태, 설치 키 삭제 후 종료)", systemImage: "trash") }
                Text("SSD, 백업, 클라우드 사본의 물리적 완전 삭제를 약속하지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var decisionsBox: some View {
        GroupBox("사용자 결정 이력 (기준 상태, 예외, 연결 주소 검토)") {
            VStack(alignment: .leading, spacing: 3) {
                if state.decisions.isEmpty { Text("없음").foregroundStyle(Theme.inkSoft) }
                ForEach(state.decisions.prefix(30)) { d in
                    Text("\(Fmt.local(d.createdAt)) · \(kind(d.kind))\(d.active ? "" : " (비활성)") · \(d.objectID ?? d.scanID.map { "점검 " + String($0.suffix(8)) } ?? d.findingID ?? "") · \(d.reason)\(d.expiresAt.map { " · 만료 " + String($0.prefix(10)) } ?? "")")
                        .font(AppFont.footnote)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func kind(_ k: String) -> String { k == "baseline" ? "기준 상태" : k == "exception" ? "예외" : k == "endpoint_reviewed" ? "연결 주소 검토" : k }
}
