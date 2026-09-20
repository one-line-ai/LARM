import SwiftUI
import LARMCore

/// 기준점 대비 구성 변경.
struct ChangesView: View {
    @EnvironmentObject var state: AppState
    @State private var reason = ""
    @State private var message: String?
    @State private var filter: DiffEntry.Change? = nil

    var items: [DiffEntry] { filter == nil ? state.diff : state.diff.filter { $0.change == filter! } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("변경 사항").font(.title2.bold())
            GroupBox("기준점") {
                VStack(alignment: .leading, spacing: 6) {
                    if let b = state.baseline, let s = state.baselineSummary {
                        Text("현재 기준점: 점검 #\(s.sequence) · \(Fmt.local(s.endedAt)) · 지정 \(Fmt.local(b.createdAt)) · 검토자 \(b.actorAlias) · 사유 \"\(b.reason)\"")
                        Text("기준점은 알려진 구성 상태이며 안전 인증이 아닙니다. 기준점 지정만으로 고위험 발견 사항이 사라지지 않습니다.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("기준점이 없습니다. 비교 결과를 검토한 뒤 지정하세요. MCP, 훅 구성은 그때까지 '미검토'로 남습니다.").foregroundStyle(.orange)
                    }
                    HStack {
                        TextField("기준점 사유 (예: 초기 검토 완료)", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                        Button("마지막 점검을 기준점으로 지정") { message = state.setBaseline(reason: reason) ?? "기준점을 지정했습니다. 다음 점검부터 이 기준과 비교합니다."; reason = "" }
                            .disabled(state.lastScan == nil || state.lastScan?.status != .complete)
                        if state.lastScan?.status == .partial { Text("부분 점검은 전체 기준점으로 지정할 수 없습니다.").font(.footnote).foregroundStyle(.orange) }
                    }
                    if let m = message { Text(m).font(.footnote) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Picker("변경 종류", selection: $filter) {
                    Text("전체 \(state.diff.count)").tag(DiffEntry.Change?.none)
                    Text("추가 \(state.diff.filter { $0.change == .added }.count)").tag(DiffEntry.Change?.some(.added))
                    Text("삭제 \(state.diff.filter { $0.change == .removed }.count)").tag(DiffEntry.Change?.some(.removed))
                    Text("수정 \(state.diff.filter { $0.change == .modified }.count)").tag(DiffEntry.Change?.some(.modified))
                    Text("비교 불가 \(state.diff.filter { $0.change == .incomparable }.count)").tag(DiffEntry.Change?.some(.incomparable))
                }.pickerStyle(.segmented)
            }
            if state.baseline == nil { Text("비교할 기준점이 없습니다.").foregroundStyle(.secondary) }
            else if state.diff.isEmpty { Text("기준점 이후 변경 없음 (마지막 점검 기준).").foregroundStyle(.secondary) }
            if !items.isEmpty {
            Table(items) {
                TableColumn("변경") { (d: DiffEntry) in Text(label(d.change)).foregroundStyle(d.change == .incomparable ? Color.orange : Color.primary) }.width(70)
                TableColumn("객체") { (d: DiffEntry) in Text(d.objectID).help(d.objectID) }
                TableColumn("필드") { (d: DiffEntry) in Text(d.field) }.width(160)
                TableColumn("이전") { (d: DiffEntry) in Text(d.before ?? "") }
                TableColumn("이후") { (d: DiffEntry) in Text(d.after ?? "") }
                TableColumn("사유") { (d: DiffEntry) in Text(d.secretChanged ? "비밀값 변경 (원문 미표시)" : d.reason) }
            }
            } else { Spacer() }
        }.padding()
    }
    func label(_ c: DiffEntry.Change) -> String {
        switch c { case .added: return "추가"; case .removed: return "삭제"; case .modified: return "수정"; case .incomparable: return "비교 불가" }
    }
}
