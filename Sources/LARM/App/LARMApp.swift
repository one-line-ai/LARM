import SwiftUI
import LARMCore

@main
struct LARMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    init() { Headless.runIfRequested(); AppFont.register() }

    var body: some Scene {
        WindowGroup("LARM", id: "main") {
            RootView()
                .environmentObject(state)
                .font(AppFont.body)
                .frame(minWidth: 1000, minHeight: 620)
        }
        .defaultSize(width: 1200, height: 760)

        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}
