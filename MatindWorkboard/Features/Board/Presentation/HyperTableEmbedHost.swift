import MatindCore
import SwiftUI
import WebKit

/// 在工作板里打开网页端的多维表。访问令牌只注入给这个页面，不放进地址。
struct HyperTableEmbedHost: NSViewRepresentable {
    let page: URL
    let accessToken: String
    let subject: String
    let expiresAt: Date
    var onParams: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onParams: onParams)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let script = WKUserScript(
            source: Self.sessionScript(
                accessToken: accessToken,
                subject: subject,
                expiresAt: expiresAt
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(context.coordinator, name: "hyperTableParams")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.allowedHost = page.host
        context.coordinator.allowedScheme = page.scheme
        context.coordinator.loadedToken = accessToken
        webView.load(URLRequest(url: page))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onParams = onParams
        guard context.coordinator.loadedToken != accessToken else { return }
        context.coordinator.loadedToken = accessToken
        let script = WKUserScript(
            source: Self.sessionScript(
                accessToken: accessToken,
                subject: subject,
                expiresAt: expiresAt
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(script)
        webView.load(URLRequest(url: page))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "hyperTableParams")
    }

    private static func sessionScript(accessToken: String, subject: String, expiresAt: Date) -> String {
        let payload: [String: Any] = [
            "accessToken": accessToken,
            "subject": subject,
            "expiresAt": Int(expiresAt.timeIntervalSince1970)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.__MATIND_HOST_SESSION__ = \(json);"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onParams: (String, String) -> Void
        var allowedHost: String?
        var allowedScheme: String?
        var loadedToken: String?

        init(onParams: @escaping (String, String) -> Void) {
            self.onParams = onParams
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "hyperTableParams",
                  let body = message.body as? [String: Any] else { return }
            let datasetId = body["datasetId"] as? String ?? ""
            let viewType = body["viewType"] as? String ?? ""
            let deliver = onParams
            DispatchQueue.main.async {
                deliver(datasetId, viewType)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            let sameOrigin = url.scheme == allowedScheme && url.host == allowedHost
            decisionHandler(sameOrigin ? .allow : .cancel)
        }
    }
}
