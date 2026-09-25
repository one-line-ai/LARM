import SwiftUI
import WebKit
import LARMCore

/// 번들 안의 갤럭시 지도 페이지를 띄우고 현재 그래프를 주입한다. 네트워크 없음.
struct GalaxyView: NSViewRepresentable {
    @EnvironmentObject var state: AppState
    let json: String
    var active: [String] = []
    let onOpenFinding: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onOpenFinding: onOpenFinding) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let activeJSON = (try? JSONSerialization.data(withJSONObject: active)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        cfg.userContentController.addUserScript(WKUserScript(source: "window.LARM_DATA = \(json); window.LARM_ACTIVE = \(activeJSON);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator, name: "larm")
        cfg.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        if let url = ResourceLocator.url("web/galaxy.html") {
            let access = Bundle.main.resourceURL ?? url.deletingLastPathComponent()
            web.loadFileURL(url, allowingReadAccessTo: access)
        }
        context.coordinator.lastJSON = json
        context.coordinator.lastActive = active
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastJSON != json {
            context.coordinator.lastJSON = json
            web.evaluateJavaScript("window.larmReload && window.larmReload((\(json)).real);", completionHandler: nil)
        }
        if context.coordinator.lastActive != active, let d = try? JSONSerialization.data(withJSONObject: active) {
            context.coordinator.lastActive = active
            web.evaluateJavaScript("window.larmSetActive && window.larmSetActive(\(String(decoding: d, as: UTF8.self)));", completionHandler: nil)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastJSON = ""
        var lastActive: [String] = []
        let onOpenFinding: (String) -> Void
        init(onOpenFinding: @escaping (String) -> Void) { self.onOpenFinding = onOpenFinding }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let body = m.body as? [String: Any], body["event"] as? String == "open", let fid = body["findingID"] as? String, !fid.isEmpty else { return }
            onOpenFinding(fid)
        }
    }
}
