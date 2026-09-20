import SwiftUI
import LARMCore

@main
struct LARMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    init() { Headless.runIfRequested() }

    var body: some Scene {
        WindowGroup("LARM", id: "main") {
            RootView()
                .environmentObject(state)
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
