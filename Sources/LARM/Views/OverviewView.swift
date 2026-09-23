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
                    tile("열린 위험 (높음)", "\(state.openHighCount)", .red)
                    tile("열린 위험 (중간)", "\(state.openFindings.filter { $0.severity == .medium }.count)", .orange)
                    tile("조치 중", "\(state.findings.filter { $0.state == .inProgress }.count)", .blue)
                    tile("예외", "\(state.findings.filter { $0.state == .excepted }.count)", .purple)
                    tile("점검 공백", "\(state.gapCount)", .gray)
                    tile("변경 사항", state.baseline == nil ? "-" : "\(state.diff.count)", .teal)
                }
                if let e = state.scanError { Text(e).foregroundStyle(.orange).textSelection(.enabled) }
                if let e = state.rulesError { Text(e).foregroundStyle(.red) }
                scanBox
                monitorBox
                supportBox
                scopeBox
                todayBox
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LARM 개요").font(AppFont.largeTitle)
            HStack {
                Text("감시 상태: ").foregroundStyle(.secondary)
                Text(state.healthLabel).bold().foregroundStyle(state.monitor?.health.overall == .watching ? Color.green : Color.orange)
                if let m = state.monitor, m.pause.isPaused { Text("· \(m.pause.description)").foregroundStyle(.orange) }
                if let ok = state.monitor?.health.lastOKAt { Text("· 마지막 건강 확인 \(Fmt.elapsed(Clock.utc(ok)))").foregroundStyle(.secondary) }
            }
            if state.lastScan == nil {
                Text("아직 점검하지 않았습니다. 오른쪽 위 '점검'을 누르세요.").font(AppFont.headline)
            } else if state.openFindings.isEmpty && state.gapCount > 0 {
                Text("발견 사항 0건 / 점검 공백 있음 → 점검 필요").font(AppFont.headline).foregroundStyle(.orange)
            } else if state.openFindings.isEmpty {
                Text("열린 발견 사항이 없습니다.").font(AppFont.headline)
            }
        }
    }

    func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.caption).foregroundStyle(.secondary)
            Text(value).font(AppFont.font(22, .bold, relativeTo: .title)).foregroundStyle(color)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    var scanBox: some View {
        GroupBox("마지막 점검") {
            if let s = state.lastScan {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("상태: \(s.status.label)").bold().foregroundStyle(s.status == .complete ? Color.primary : Color.orange)
                        Text("· \(Fmt.local(s.endedAt)) (\(Fmt.elapsed(s.endedAt)))")
                        Text("· 룰 \(s.rulesVersion) · 종류 \(s.kind)").foregroundStyle(.secondary)
                    }
                    Text("확인한 값 \(s.counts["observations"] ?? 0)건 · coverage \(s.counts["coverage"] ?? 0)건 · 공백 \(s.counts["gaps"] ?? 0)건 · 판단 보류 \(s.counts["verdicts_unknown"] ?? 0)건")
                        .font(AppFont.footnote).foregroundStyle(.secondary)
                    ForEach(s.notes, id: \.self) { Text($0).font(AppFont.footnote).foregroundStyle(.orange) }
                    if s.status == .partial { Text("일부 항목을 확인하지 못했습니다. 부분 결과이며 전체 완료가 아닙니다.").font(AppFont.footnote).foregroundStyle(.orange) }
                    if s.status == .failed || s.status == .cancelled {
                        Text("최신 실행이 \(s.status.label)입니다. 이전 성공 결과를 아래 목록에 유지합니다.").font(AppFont.footnote).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("기록 없음").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var monitorBox: some View {
        GroupBox("백그라운드 감시 (창을 닫아도 유지)") {
            VStack(alignment: .leading, spacing: 6) {
                if let m = state.monitor {
                    HStack {
                        Text("설정 감시:").bold(); Text(m.health.configWatch.label)
                        Text("· AI 활동:").bold(); Text(m.health.activity.label + (m.hookInstalled ? "" : " (hook 미등록)"))
                        Spacer()
                        if m.pause.isPaused { Button("감시 재개") { m.resume() } } else {
                            Menu("일시중지") { Button("15분") { m.pauseWatching(minutes: 15) }; Button("1시간") { m.pauseWatching(minutes: 60) }; Button("수동 재개까지") { m.pauseWatching(minutes: nil) } }.frame(width: 110)
                        }
                    }
                    Text("폴더 감시 \(m.watchedDirs.count)개 폴더 (\(m.watchedDirs.joined(separator: ", "))) · 60초 폴링 \(m.polledFiles.count)개 파일 · 30분 주기 대조\(m.health.lastReconcileAt.map { " · 마지막 대조 " + Fmt.elapsed(Clock.utc($0)) } ?? "")")
                        .font(AppFont.footnote).foregroundStyle(.secondary)
                    if let d = state.lastSkippedReconcileAt { Text("변화 없음 확인 \(Fmt.elapsed(d)) (저장 생략)").font(AppFont.footnote).foregroundStyle(.secondary) }
                    if !m.health.detail.isEmpty { Text(m.health.detail).font(AppFont.footnote).foregroundStyle(.secondary) }
                    if m.openGaps.isEmpty {
                        Text("지금은 감시가 끊긴 곳이 없습니다").font(AppFont.callout)
                    } else {
                        ForEach(m.openGaps) { g in
                            Text("공백 진행 중: \(g.label) · 시작 \(Fmt.local(g.startedAt)) · 범위 \(g.surface == "config_watch" ? "설정 감시" : g.surface)").foregroundStyle(.orange)
                        }
                        Text("복구: 일시중지면 재개, 절전이면 복귀 후 자동 대조, 장애면 앱 재시작 → 시험 이벤트 확인").font(AppFont.footnote).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("최근 공백 기록 (\(m.recentGaps.count))") {
                        ForEach(m.recentGaps) { g in
                            Text("\(Fmt.local(g.startedAt)) ~ \(g.endedAt.map { Fmt.local($0) } ?? "진행 중") · \(g.label)\(g.recoveryEvidence.isEmpty ? "" : " · 복구: " + g.recoveryEvidence)").font(AppFont.footnote)
                        }
                    }.font(AppFont.footnote)
                    Text("감시가 멈춘 동안의 변경은 알 수 없고, 복귀하면 현재 상태만 다시 확인합니다. 파일 변경 알림은 누가 바꿨는지나 실행 여부를 말해 주지 않습니다.").font(AppFont.footnote).foregroundStyle(.secondary)
                } else { Text("백그라운드 감시 준비 중").foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(support(s?.support ?? "-")).foregroundStyle(.secondary)
                    }.font(AppFont.callout)
                }
                if state.installStatus.values.allSatisfy({ $0.status == "not_installed" }) {
                    Text("점검할 지원 대상이 없습니다. 지원 범위: Claude Code, Codex CLI, Cursor MCP. 프로젝트를 추가하거나 도구를 설치하세요.").foregroundStyle(.orange)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func label(_ s: String) -> String { s == "installed" ? "설치됨" : s == "config_only" ? "설정 잔존" : s == "not_installed" ? "미설치" : s }
    func support(_ s: String) -> String { s == "supported" ? "정적 점검 지원 (시험 버전)" : s == "limited" ? "제한 지원 (버전 미확인)" : "미지원" }

    var scopeBox: some View {
        GroupBox("점검 범위") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.scopes) { s in
                    HStack {
                        Image(systemName: s.kind == .userRoot ? "house" : "folder")
                        Text(s.kind == .userRoot ? "사용자 설정 위치 (~/.claude, ~/.codex, ~/.cursor)" : s.alias)
                        if s.excluded { Text("제외됨").font(AppFont.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if s.kind == .project {
                            Text(s.realPath).font(AppFont.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(s.realPath)
                            Button(s.excluded ? "포함" : "제외") { state.toggleExcluded(s) }.controlSize(.small)
                            Button("삭제") { state.removeScope(s) }.controlSize(.small)
                        }
                    }
                }
                HStack {
                    Button { state.addProjectFolder() } label: { Label("프로젝트 추가", systemImage: "plus") }
                    Text("홈 전체, 다른 사용자, 클라우드 병합은 자동 탐색하지 않습니다.").font(AppFont.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var todayBox: some View {
        GroupBox("오늘 확인할 항목 (높은 위험 → 오래된 결과 순)") {
            let top = Array(state.openFindings.sorted { $0.severity > $1.severity }.prefix(3))
            VStack(alignment: .leading, spacing: 6) {
                if top.isEmpty { Text("없음").foregroundStyle(.secondary) }
                ForEach(top) { f in
                    Button {
                        state.selectedFindingID = f.findingID; state.section = .findings
                    } label: {
                        HStack { SeverityBadge(severity: f.severity); Text("\(f.ruleID) \(f.title)").bold(); Text(f.locationAlias).foregroundStyle(.secondary).lineLimit(1) }
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
