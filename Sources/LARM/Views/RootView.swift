import SwiftUI
import LARMCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LARM").font(AppFont.font(15, .bold)).foregroundStyle(Theme.sidebarText)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
                ForEach(AppState.Section.allCases) { s in
                    Button { state.section = s } label: {
                        HStack {
                            Label(s.title, systemImage: s.symbol).font(AppFont.font(13, state.section == s ? .semibold : .regular))
                            Spacer()
                            let n = badge(s)
                            if n > 0 { Text("\(n)").font(AppFont.caption).foregroundStyle(state.section == s ? Theme.sidebarSelectedText.opacity(0.8) : Theme.accent) }
                        }
                        .foregroundStyle(state.section == s ? Theme.sidebarSelectedText : Theme.sidebarText)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(state.section == s ? Theme.sidebarSelected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.sidebar.ignoresSafeArea())
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.indigoFaint).frame(width: 1).ignoresSafeArea() }
            .toolbarBackground(Theme.sidebar, for: .windowToolbar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
            switch state.boot {
            case .starting:
                ProgressView("준비 중")
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 12) {
                    Text("LARM을 시작하지 못했음").font(AppFont.title2)
                    Text(msg).textSelection(.enabled)
                    Text("복구: 앱을 다시 열거나 Keychain 접근을 허용하기. 데이터 위치: \(Paths.supportDir.path)")
                        .font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                }.padding()
            case .ready:
                switch state.section {
                case .overview: OverviewView()
                case .findings: FindingsView()
                case .activity: ActivityView()
                case .games: GamesView()
                case .changes: ChangesView()
                case .coverage: CoverageView()
                case .graph: GraphView()
                case .evidence: EvidenceSettingsView()
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.sand)
            .foregroundStyle(Theme.ink)
            .groupBoxStyle(DuoPanel())
            .tint(Theme.indigoSoft)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.scanning {
                    ProgressView().controlSize(.small)
                    Button("취소") { state.cancelScan() }
                } else {
                    Button { state.runScan() } label: { Label("점검", systemImage: "magnifyingglass") }
                        .keyboardShortcut("r")
                }
            }
        }
    }
}

extension RootView {
    func badge(_ s: AppState.Section) -> Int {
        switch s {
        case .findings: return state.openFindings.count
        case .coverage: return state.gapCount
        case .changes: return state.diff.count
        case .activity: return state.events.filter { $0.riskSeverity == "high" && $0.ackState == "observed" }.count
        default: return 0
        }
    }
}

struct PlaceholderView: View {
    let title: String; let note: String
    var body: some View {
        VStack(spacing: 8) { Text(title).font(AppFont.title2); Text(note).foregroundStyle(Theme.inkSoft) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

