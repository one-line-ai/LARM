import SwiftUI
import LARMCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List {
                ForEach(AppState.Section.allCases) { s in
                    Button { state.section = s } label: {
                        HStack {
                            Label(s.title, systemImage: s.symbol)
                            Spacer()
                            let n = badge(s)
                            if n > 0 { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(state.section == s ? Color.accentColor.opacity(0.25) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch state.boot {
            case .starting:
                ProgressView("준비 중")
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 12) {
                    Text("LARM을 시작하지 못했습니다").font(.title2)
                    Text(msg).textSelection(.enabled)
                    Text("복구: 앱을 다시 열거나 Keychain 접근을 허용하세요. 데이터 위치: \(Paths.supportDir.path)")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            case .ready:
                switch state.section {
                case .overview: OverviewView()
                case .findings: FindingsView()
                case .activity: ActivityView()
                case .changes: ChangesView()
                case .coverage: CoverageView()
                case .graph: GraphView()
                case .evidence: EvidenceSettingsView()
                }
            }
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
        VStack(spacing: 8) { Text(title).font(.title2); Text(note).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Text(severity.label)
            .font(.caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18)).foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("심각도 \(severity.label)")
    }
    var color: Color {
        switch severity { case .high: return .red; case .medium: return .orange; case .low: return .yellow; case .gap: return .gray }
    }
}

struct StateBadge: View {
    let state: FindingState
    var body: some View {
        Text(state.label).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
