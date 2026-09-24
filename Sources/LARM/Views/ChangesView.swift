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
            Text("바뀐 설정").font(AppFont.title2)
            GroupBox("기준 상태") {
                VStack(alignment: .leading, spacing: 6) {
                    if let b = state.baseline, let s = state.baselineSummary {
                        Text("현재 기준 상태: 점검 #\(s.sequence) · \(Fmt.local(s.endedAt)) · 지정 \(Fmt.local(b.createdAt)) · 검토자 \(b.actorAlias) · 사유 \"\(b.reason)\"")
                        Text("기준 상태은 알려진 구성 상태이며 안전 인증이 아님. 기준 상태 지정만으로 고위험 발견 사항이 사라지지 않음").font(AppFont.footnote).foregroundStyle(Theme.inkSoft)
                    } else {
                        Text("기준 상태이 없음 비교 결과를 검토한 뒤 지정하기. MCP, 연결(hook) 구성은 그때까지 '미검토'로 남음.").foregroundStyle(Theme.indigoSoft)
                    }
                    HStack {
                        TextField("기준 상태 사유 (예: 초기 검토 완료)", text: $reason).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                        Button("마지막 점검을 기준 상태으로 지정") { message = state.setBaseline(reason: reason) ?? "기준 상태을 지정했음. 다음 점검부터 이 기준과 비교함"; reason = "" }
                            .disabled(state.lastScan == nil || state.lastScan?.status != .complete)
                        if state.lastScan?.status == .partial { Text("부분 점검은 전체 기준 상태으로 지정할 수 없음").font(AppFont.footnote).foregroundStyle(Theme.indigoSoft) }
                    }
                    if let m = message { Text(m).font(AppFont.footnote) }
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
            if state.baseline == nil { Text("비교할 기준 상태이 없음").foregroundStyle(Theme.inkSoft) }
            else if state.diff.isEmpty { Text("기준 상태 이후 변경 없음 (마지막 점검 기준).").foregroundStyle(Theme.inkSoft) }
            if !items.isEmpty {
            Table(items) {
                TableColumn("변경") { (d: DiffEntry) in Text(label(d.change)).foregroundStyle(d.change == .incomparable ? Theme.indigoSoft : Theme.ink) }.width(70)
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
