import SwiftUI
import LARMCore

/// 설계 10장: 사용자와 AI 도구를 두 플레이어로 보고, LARM이 심판으로서 무엇을 바꾸는지 보여 준다.
struct GamesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Mascot(mood: state.mood, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("사용자와 AI 도구").font(AppFont.largeTitle)
                        Text("AI 도구는 일을 빨리 끝내려 넓은 권한을 원하고, 사용자는 일은 끝내되 위험은 줄이려 함. LARM은 막지 않고 기록·표시·기본값으로 둘의 선택을 바꾸는 심판 역할. 아래 숫자는 모두 규칙으로 계산한 참고값이며 판단은 사용자 몫").font(AppFont.callout).foregroundStyle(Theme.inkSoft)
                    }
                }
                delegationBox
                signalBox
                trustBox
                inspectionBox
                attentionBox
                basisBox
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
    }

    func header(_ n: Int, _ title: String, _ user: String, _ agent: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(n). \(title)").font(AppFont.title3)
            HStack(spacing: 14) {
                Label(user, systemImage: "person").font(AppFont.footnote)
                Label(agent, systemImage: "cpu").font(AppFont.footnote)
            }.foregroundStyle(Theme.inkSoft)
        }
    }

    // 1 권한 위임
    var delegationBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header(1, "권한 위임", "사용자: 허용 범위를 정함", "AI 도구: 주어진 범위를 끝까지 씀")
                let broad = state.openFindings.filter { $0.ruleID == "R01" || $0.ruleID == "R02" }
                if broad.isEmpty {
                    Text("열린 넓은 허용 규칙 없음").foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(broad) { f in
                        let d = state.delegation(for: f)
                        Button { state.selectedFindingID = f.findingID; state.section = .findings } label: {
                            HStack(alignment: .top) {
                                SeverityBadge(severity: f.severity)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(f.ruleID) \(f.title) · \(f.locationAlias)").bold()
                                    Text(d.map { "좁히면 늘어나는 확인 요청: 세션당 약 \(String(format: "%.1f", $0.perSession))회 (\($0.basis)) → \($0.recommendNarrow ? "좁혀도 부담 작음" : "좁히면 확인이 잦아짐, 규칙 세분화 권장")" } ?? "실행 전 확인 생략 설정. 실제 필요 여부는 프로젝트마다 다름")
                                        .font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 2 신호
    var signalBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header(2, "신호 읽기", "사용자: 계속 맡길지, 살펴볼지 정함", "AI 도구: 행동 자체가 신호가 됨")
                let s = state.sessionSignals.prefix(5)
                if s.isEmpty {
                    Text("기록된 작업 세션 없음. 연결(hook)을 등록하면 세션별로 살펴볼 순서가 생김").foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(Array(s)) { sig in SessionRow(sig: sig) }
                    Text("위 순서는 숨김·우회형 명령, 높은 위험 판정, 민감 경로, 범위 밖 접근 수로 계산한 참고값. '살펴봄' 표시는 나중에 추정이 맞았는지 검증하는 데 쓰임").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 3 반복 신뢰
    var trustBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header(3, "기억 있는 신뢰", "사용자: 프로젝트마다 얼마나 믿을지 정함", "AI 도구: 안전한 변경만 할지, 위험한 설정 변경을 할지")
                if state.trustRecords.isEmpty { Text("이력 없음").foregroundStyle(Theme.inkSoft) }
                ForEach(state.trustRecords) { t in
                    HStack {
                        Text(state.scopeAlias(t.scopeID)).bold().frame(width: 220, alignment: .leading).lineLimit(1)
                        Text(t.level).font(AppFont.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(t.level == "안정" ? Theme.sandDeep : Theme.indigoFaint).clipShape(RoundedRectangle(cornerRadius: 3))
                        Text("30일 새 발견 \(t.riskyChanges30d)건 · 반복 \(t.repeated)건 · 열린 높음 \(t.openHigh)건").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    }
                }
                if let s = state.baselineSuggestion {
                    HStack {
                        Mascot(mood: .clear, size: 28)
                        Text(s).font(AppFont.callout)
                        Button("기준 상태로 저장") { _ = state.setBaseline(reason: "권장에 따라 저장") }.controlSize(.small)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 4 검사
    var inspectionBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header(4, "예측할 수 없는 검사", "사용자: 언제 다시 확인할지", "AI 도구: 언제 설정을 바꿀지")
                if let m = state.monitor {
                    Text(m.nextReconcileAt.map { "다음 전체 대조: \(Fmt.local(Clock.utc($0))) · \(m.reconcileBasis)" } ?? "대조 예약 없음")
                    Text("작업 중에는 10~15분, 유휴에는 30~60분 사이에서 매번 무작위로 정함. 시각을 예측할 수 없으므로 검사 사이 틈을 노릴 수 없음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 5 주의 배분
    var attentionBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header(5, "주의 배분", "사용자: 알림에 반응할지", "AI 도구: 사건을 얼마든지 만들 수 있음")
                HStack(spacing: 18) {
                    stat("알림 반응률 (30일)", state.alertResponseRate.map { "\(Int($0 * 100))%" } ?? "표본 없음", "\(state.alertSamples)건")
                    stat("오늘 확인할 항목", "\(min(3, state.todayItems.count))건", "조치 필요 추정 순")
                    stat("높은 위험 알림", "항상 전송", "게이트 없음")
                }
                if !state.lastGateNote.isEmpty { Text("최근 게이트: \(state.lastGateNote)").font(AppFont.footnote).foregroundStyle(Theme.inkSoft) }
                Text("중간 위험과 감시 공백 알림은 조치 필요 확률 × 반응 확률이 낮으면 알림 대신 배지로만 표시함. 같은 안전을 더 적은 방해로").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    func stat(_ t: String, _ v: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(AppFont.caption).foregroundStyle(Theme.inkSoft)
            Text(v).font(AppFont.font(18, .semibold))
            Text(sub).font(AppFont.caption2).foregroundStyle(Theme.mute)
        }
    }

    // 결정 근거 (G7)
    var basisBox: some View {
        GroupBox("결정 근거와 검증") {
            VStack(alignment: .leading, spacing: 4) {
                Text("추정 모델: 규칙 기반 (rule-1). 외부 모델(Jev) 미연결").font(AppFont.callout)
                ForEach(state.calibration, id: \.0) { c in Text(c.1).font(AppFont.footnote).foregroundStyle(Theme.inkSoft) }
                Text("추정값은 나중 결과와 함께 저장되어 브라이어 점수로 검증됨. 0.25를 넘으면 추정을 끄고 기본 동작으로 돌아감").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject var state: AppState
    let sig: PlayerGames.SessionSignal
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(Int(sig.p * 100))%").font(AppFont.font(14, .semibold)).foregroundStyle(sig.p >= 0.4 ? Theme.indigo : Theme.inkSoft).frame(width: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text("세션 \(sig.sessionRef.prefix(8))… · \(Fmt.local(sig.firstAt)) · 요청 \(sig.requests)건").bold()
                Text(sig.basis).font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if sig.reviewed { Text("살펴봄").font(AppFont.caption).foregroundStyle(Theme.inkSoft) }
            else {
                Button("살펴봄, 문제 있음") { state.reviewSession(sig, problem: true) }.controlSize(.small)
                Button("살펴봄, 문제 없음") { state.reviewSession(sig, problem: false) }.controlSize(.small)
            }
        }
    }
}
