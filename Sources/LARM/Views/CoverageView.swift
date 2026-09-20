import SwiftUI
import LARMCore

/// 점검 범위.
struct CoverageView: View {
    @EnvironmentObject var state: AppState
    @State private var showSuccess = false

    var items: [Coverage] { showSuccess ? state.lastCoverage : state.lastCoverage.filter { $0.status != .success && $0.status != .absent } }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("점검 범위").font(.title2.bold())
                Spacer()
                Toggle("성공, 부재 항목도 표시", isOn: $showSuccess)
            }.padding([.horizontal, .top])
            Text("읽지 못한 항목은 없는 것으로 치지 않습니다.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            if state.lastScan == nil {
                Text("아직 점검하지 않았습니다.").foregroundStyle(.secondary).padding()
            } else if items.isEmpty {
                Text("확인하지 못한 항목이 없습니다.").padding()
            }
            if !items.isEmpty {
            Table(items) {
                TableColumn("상태") { (c: Coverage) in Text(label(c.status)).foregroundStyle(c.status == .success ? Color.primary : Color.orange) }.width(80)
                TableColumn("어댑터") { (c: Coverage) in Text(c.adapter) }.width(100)
                TableColumn("범위") { (c: Coverage) in Text(state.scopeAlias(c.scopeID)) }.width(120)
                TableColumn("항목") { (c: Coverage) in Text(c.itemAlias).help(c.itemAlias) }
                TableColumn("사유") { (c: Coverage) in Text(c.reason) }
            }
            } else { Spacer() }
            Text("복구: 접근 거절은 권한, 개인정보 보호 설정 확인 후 재시도, 상한 초과는 범위 축소, 미지원은 지원표 확인 → 재점검").font(.footnote).foregroundStyle(.secondary).padding()
        }
    }
    func label(_ s: CoverageStatus) -> String {
        switch s { case .success: return "성공"; case .absent: return "부재"; case .denied: return "접근 거절"; case .oversize: return "상한 초과"; case .unsupported: return "미지원"; case .error: return "오류" }
    }
}

extension Coverage: Identifiable { public var id: String { "\(adapter)|\(scopeID)|\(itemAlias)|\(status.rawValue)" } }
