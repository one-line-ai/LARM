import SwiftUI
import LARMCore

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch state.boot {
        case .ready:
            Text("라미: \(Mascot(mood: state.mood).label)")
            Text("감시: \(state.healthLabel)\(state.monitor.map { m in m.pause.isPaused ? " · " + m.pause.description : "" } ?? "")")
            if let ok = state.monitor?.health.lastOKAt { Text("마지막 건강 확인 \(Fmt.elapsed(Clock.utc(ok)))") }
            Text("열린 위험 높음 \(state.openHighCount) · 확인 못 한 항목 \(state.gapCount) · 감시가 끊긴 구간 \(state.watchGapCount)")
            if let s = state.lastScan { Text("마지막 점검 \(Fmt.elapsed(s.endedAt)) · \(s.status.label)") }
        case .starting: Text("준비 중")
        case .failed: Text("시작 실패")
        }
        Divider()
        Button("지금 점검") { state.runScan() }.disabled(state.scanning || state.boot != .ready)
        if let m = state.monitor {
            if m.pause.isPaused {
                Button("감시 다시 시작") { m.resume() }
            } else {
                Menu("감시 잠시 멈춤") {
                    Button("15분") { m.pauseWatching(minutes: 15) }
                    Button("1시간") { m.pauseWatching(minutes: 60) }
                    Button("수동 다시 시작까지") { m.pauseWatching(minutes: nil) }
                }
            }
        }
        Button("LARM 열기") { openWindow(id: "main"); WindowOpener.openMain() }
        Divider()
        Text("창을 닫아도 감시는 유지됨").font(AppFont.footnote)
        Button("감시 종료 (앱 종료)") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
