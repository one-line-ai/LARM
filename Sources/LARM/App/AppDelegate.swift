import AppKit

/// 창 닫기는 감시 종료가 아니다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.openMain() }
        return true
    }
}

enum WindowOpener {
    static func openMain() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "LARM" }) {
            w.makeKeyAndOrderFront(nil)
        }
    }
}
