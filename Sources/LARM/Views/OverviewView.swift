import SwiftUI
import LARMCore

/// 상태 중심 개요.
struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                HStack(alignment: .top, spacing: 12) {
                    tile("높은 위험", "\(state.openHighCount)", state.openHighCount > 0 ? Theme.accent : Theme.mute, strong: true)
                    tile("중간 위험", "\(state.openFindings.filter { $0.severity == .medium }.count)", Theme.indigoSoft)
                    tile("조치 중", "\(state.findings.filter { $0.state == .inProgress }.count)", Theme.indigoSoft)
                    tile("예외로 둔 항목", "\(state.findings.filter { $0.state == .excepted }.count)", Theme.indigoSoft)
                    tile("확인 못 한 항목", "\(state.gapCount)", Theme.mute)
                    tile("바뀐 설정", state.baseline == nil ? "-" : "\(state.diff.count)", Theme.indigoSoft)
                }
                if let e = state.scanError { Text(e).foregroundStyle(Theme.indigoSoft).textSelection(.enabled) }
                if let e = state.rulesError { Text(e).foregroundStyle(Theme.indigo) }
                scanBox
                monitorBox
                supportBox
                scopeBox
                todayBox
                glossaryBox
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    var headline: some View {
        HStack(alignment: .top, spacing: 14) {
        Mascot(mood: state.mood, size: 56)
        VStack(alignment: .leading, spacing: 4) {
            Text("LARM 개요").font(AppFont.largeTitle)
            HStack {
                Text("감시 상태: ").foregroundStyle(Theme.inkSoft)
                Text(state.healthLabel).bold().foregroundStyle(state.monitor?.health.overall == .watching ? Theme.indigo : Theme.indigoSoft)
                if let m = state.monitor, m.pause.isPaused { Text("· \(m.pause.description)").foregroundStyle(Theme.indigoSoft) }
                if let ok = state.monitor?.health.lastOKAt { Text("· 마지막 건강 확인 \(Fmt.elapsed(Clock.utc(ok)))").foregroundStyle(Theme.inkSoft) }
            }
            if state.lastScan == nil {
                Text("아직 점검하지 않았음. 오른쪽 위 '점검' 버튼으로 시작").font(AppFont.headline)
            } else if state.openFindings.isEmpty && state.gapCount > 0 {
                Text("발견 사항 0건 / 확인 못 한 항목 있음 → 점검 필요").font(AppFont.headline).foregroundStyle(Theme.indigoSoft)
            } else if state.openFindings.isEmpty {
                Text("열린 발견 사항이 없음. 지금 상태가 좋음").font(AppFont.headline)
            } else if state.openHighCount > 0 {
                Text("높은 위험 \(state.openHighCount)건이 열려 있음. 아래 '오늘 확인할 항목'부터 보기").font(AppFont.headline)
            }
            if let m = state.monitor, let n = m.nextReconcileAt {
                Text("다음 전체 대조 \(Fmt.local(Clock.utc(n))) (\(m.reconcileBasis))").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
            }
        }
        }
    }

    func tile(_ title: String, _ value: String, _ color: Color, strong: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.caption).foregroundStyle(Theme.inkSoft)
            Text(value).font(AppFont.font(24, strong ? .bold : .semibold)).foregroundStyle(color)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(strong ? Theme.accent : Theme.indigoFaint).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.indigoFaint, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    var scanBox: some View {
        GroupBox("마지막 점검") {
            if let s = state.lastScan {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("상태: \(s.status.label)").bold().foregroundStyle(s.status == .complete ? Theme.ink : Theme.indigoSoft)
                        Text("· \(Fmt.local(s.endedAt)) (\(Fmt.elapsed(s.endedAt)))")
                        Text("· 점검 규칙 \(s.rulesVersion) · 종류 \(s.kind)").foregroundStyle(Theme.inkSoft)
                    }
                    Text("확인한 값 \(s.counts["observations"] ?? 0)건 · 확인 항목 \(s.counts["coverage"] ?? 0)건 · 확인 못 한 구간 \(s.counts["gaps"] ?? 0)건 · 판단 보류 \(s.counts["verdicts_unknown"] ?? 0)건")
                        .font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    ForEach(s.notes, id: \.self) { Text($0).font(AppFont.footnote).foregroundStyle(Theme.indigoSoft) }
                    if s.status == .partial { Text("일부 항목을 확인하지 못했음. 부분 결과이며 전체 완료가 아님.").font(AppFont.footnote).foregroundStyle(Theme.indigoSoft) }
                    if s.status == .failed || s.status == .cancelled {
                        Text("최신 실행이 \(s.status.label)임. 이전 성공 결과를 아래 목록에 유지함").font(AppFont.footnote).foregroundStyle(Theme.indigoSoft)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("기록 없음").foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var monitorBox: some View {
        GroupBox("자동 감시 (창을 닫아도 유지)") {
            VStack(alignment: .leading, spacing: 6) {
                if let m = state.monitor {
                    HStack {
                        Text("설정 감시:").bold(); Text(m.health.configWatch.label)
                        Text("· AI 도구 활동:").bold(); Text(m.health.activity.label + (m.hookInstalled ? "" : " (연결 안 됨)"))
                        Spacer()
                        if m.pause.isPaused { Button("감시 다시 시작") { m.resume() } } else {
                            Menu("잠시 멈춤") { Button("15분") { m.pauseWatching(minutes: 15) }; Button("1시간") { m.pauseWatching(minutes: 60) }; Button("수동 다시 시작까지") { m.pauseWatching(minutes: nil) } }.frame(width: 110)
                        }
                    }
                    Text("폴더 감시 \(m.watchedDirs.count)개 폴더 (\(m.watchedDirs.joined(separator: ", "))) · 60초 폴링 \(m.polledFiles.count)개 파일 · 30분 주기 대조\(m.health.lastReconcileAt.map { " · 마지막 대조 " + Fmt.elapsed(Clock.utc($0)) } ?? "")")
                        .font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    if let d = state.lastSkippedReconcileAt { Text("변화 없음 확인 \(Fmt.elapsed(d)) (저장 생략)").font(AppFont.footnote).foregroundStyle(Theme.inkSoft) }
                    if !m.health.detail.isEmpty { Text(m.health.detail).font(AppFont.footnote).foregroundStyle(Theme.inkSoft) }
                    if m.openGaps.isEmpty {
                        Text("지금은 감시가 끊긴 곳이 없음").font(AppFont.callout)
                    } else {
                        ForEach(m.openGaps) { g in
                            Text("확인 못 한 구간 진행 중: \(g.label) · 시작 \(Fmt.local(g.startedAt)) · 범위 \(g.surface == "config_watch" ? "설정 감시" : g.surface)").foregroundStyle(Theme.indigoSoft)
                        }
                        Text("복구: 잠시 멈춤이면 다시 시작, 절전이면 복귀 후 자동 대조, 장애면 앱 재시작 → 연결 확인 신호 확인").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    }
                    DisclosureGroup("최근 확인 못 한 구간 기록 (\(m.recentGaps.count))") {
                        ForEach(m.recentGaps) { g in
                            Text("\(Fmt.local(g.startedAt)) ~ \(g.endedAt.map { Fmt.local($0) } ?? "진행 중") · \(g.label)\(g.recoveryEvidence.isEmpty ? "" : " · 복구: " + g.recoveryEvidence)").font(AppFont.footnote)
                        }
                    }.font(AppFont.footnote)
                    Text("감시가 멈춘 동안의 변경은 알 수 없고, 복귀하면 현재 상태만 다시 확인함. 파일 변경 알림은 누가 바꿨는지나 실행 여부를 말해 주지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                } else { Text("자동 감시 준비 중").foregroundStyle(Theme.inkSoft) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var glossaryBox: some View {
        GroupBox("용어 안내") {
            VStack(alignment: .leading, spacing: 5) {
                glossary("점검", "AI 도구(Claude Code, Codex, Cursor)의 설정 파일을 읽어 위험한 설정이 있는지 확인하는 일. 설정을 바꾸지는 않음")
                glossary("발견 사항", "점검에서 찾은 위험한 설정 한 건. 높음·중간 위험도와 함께 이유와 고치는 방법을 보여 줌")
                glossary("기준 상태", "\"이 설정은 내가 확인했다\"고 저장해 둔 상태. 이후 무엇이 바뀌었는지 비교하는 기준")
                glossary("예외", "위험을 알지만 당분간 두기로 한 항목. 기한(최대 30일)이 지나면 다시 열림")
                glossary("자동 감시", "앱이 켜져 있는 동안 설정 파일이 바뀌는지 지켜보다가 바뀌면 다시 점검하는 기능")
                glossary("AI 도구 활동", "Claude Code가 파일을 읽거나 명령을 실행하려 할 때 그 사실만 기록한 것. 내용은 저장하지 않고 막지도 않음")
                glossary("점검 보고서", "점검 결과를 다른 사람에게 전달할 수 있게 묶은 파일. 비밀값과 실제 경로는 들어가지 않음")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func glossary(_ term: String, _ meaning: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(term).font(AppFont.font(12.5, .semibold)).foregroundStyle(Theme.indigo).frame(width: 90, alignment: .leading)
            Text(meaning).font(AppFont.callout).foregroundStyle(Theme.inkSoft)
        }
    }

    var supportBox: some View {
        GroupBox("지원 도구") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["claude-code", "codex", "cursor"], id: \.self) { id in
                    let s = state.installStatus[id]
                    HStack {
                        Text(id).frame(width: 110, alignment: .leading).bold()
                        Text(label(s?.status ?? "-")).frame(width: 90, alignment: .leading)
                        Text("버전 \(s?.version ?? "-")").frame(width: 150, alignment: .leading)
                        Text(support(s?.support ?? "-")).foregroundStyle(Theme.inkSoft)
                    }.font(AppFont.callout)
                }
                if state.installStatus.values.allSatisfy({ $0.status == "not_installed" }) {
                    Text("점검할 지원 대상이 없음 지원 범위: Claude Code, Codex CLI, Cursor MCP. 프로젝트를 추가하거나 도구를 설치하기").foregroundStyle(Theme.indigoSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func label(_ s: String) -> String { s == "installed" ? "설치됨" : s == "config_only" ? "설정 잔존" : s == "not_installed" ? "미설치" : s }
    func support(_ s: String) -> String { s == "supported" ? "정적 점검 지원 (시험 버전)" : s == "limited" ? "제한 지원 (버전 미확인)" : "미지원" }

    var scopeBox: some View {
        GroupBox("점검 대상 폴더") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.scopes) { s in
                    HStack {
                        Image(systemName: s.kind == .userRoot ? "house" : "folder")
                        Text(s.kind == .userRoot ? "사용자 설정 위치 (~/.claude, ~/.codex, ~/.cursor)" : s.alias)
                        if s.excluded { Text("제외됨").font(AppFont.caption).foregroundStyle(Theme.inkSoft) }
                        Spacer()
                        if s.kind == .project {
                            Text(s.realPath).font(AppFont.caption).foregroundStyle(Theme.inkSoft).lineLimit(1).truncationMode(.middle).help(s.realPath)
                            Button(s.excluded ? "포함" : "제외") { state.toggleExcluded(s) }.controlSize(.small)
                            Button("삭제") { state.removeScope(s) }.controlSize(.small)
                        }
                    }
                }
                HStack {
                    Button { state.addProjectFolder() } label: { Label("프로젝트 추가", systemImage: "plus") }
                    Text("홈 전체, 다른 사용자, 클라우드 병합은 자동 탐색하지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var todayBox: some View {
        GroupBox("오늘 확인할 항목 (조치 필요 추정 순)") {
            let top = Array(state.todayItems.prefix(3))
            VStack(alignment: .leading, spacing: 8) {
                if top.isEmpty {
                    HStack(spacing: 10) { Mascot(mood: .clear, size: 32); Text("오늘은 확인할 항목이 없음").foregroundStyle(Theme.inkSoft) }
                }
                ForEach(top) { f in
                    Button {
                        state.selectedFindingID = f.findingID; state.section = .findings
                    } label: {
                        HStack(alignment: .top) {
                            SeverityBadge(severity: f.severity)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text("\(f.ruleID) \(f.title)").bold(); Text(f.locationAlias).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                                Text("확인하면 알 수 있는 것: \(PlayerGames.whatYouLearn(f))").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                Text("순서: 위험도 → 재점검으로 확인된 것 → 여러 번 발견된 것 → 오래된 것. 자세한 근거는 '사용자와 AI 도구' 화면").font(AppFont.caption).foregroundStyle(Theme.mute)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
