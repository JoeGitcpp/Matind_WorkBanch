import SwiftUI
import WebKit

/// WKWebView 插件宿主，注入 MatindBridge JS 对象
struct WebViewPluginHost: NSViewRepresentable {
    let pluginId: String
    let pluginDirectory: URL
    let apiToken: String?
    var onNavigateToBoard: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // 注入 JS Bridge（必须在创建 WebView 前配置）
        injectBridge(into: config, coordinator: context.coordinator)

        // 创建 WebView
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // 加载本地 HTML
        let entryURL = pluginDirectory.appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: entryURL.path) {
            webView.loadFileURL(entryURL, allowingReadAccessTo: pluginDirectory)
        } else {
            webView.loadHTMLString(fallbackHTML(), baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(pluginId: pluginId, apiToken: apiToken, onNavigateToBoard: onNavigateToBoard)
    }

    private func injectBridge(into config: WKWebViewConfiguration, coordinator: Coordinator) {
        let script = """
        window.MatindBridge = {
            api: {
                get: function(path) {
                    return new Promise(function(resolve, reject) {
                        window.webkit.messageHandlers.apiGet.postMessage({path: path, resolve: null, reject: null});
                    });
                }
            },
            notification: {
                send: function(payload) {
                    window.webkit.messageHandlers.notificationSend.postMessage(payload);
                }
            },
            params: {
                getAll: function() {
                    return new Promise(function(resolve) {
                        window.webkit.messageHandlers.paramsGetAll.postMessage({});
                    });
                }
            },
            navigation: {
                goToBoard: function(boardId) {
                    window.webkit.messageHandlers.navigateToBoard.postMessage({boardId: boardId});
                }
            }
        };
        console.log('[MatindBridge] Injected successfully');
        """

        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)

        // 注册消息处理器
        config.userContentController.add(coordinator, name: "apiGet")
        config.userContentController.add(coordinator, name: "notificationSend")
        config.userContentController.add(coordinator, name: "paramsGetAll")
        config.userContentController.add(coordinator, name: "navigateToBoard")
    }

    private func fallbackHTML() -> String {
        """
        <html><body style="font-family:system-ui;padding:20px;color:#666">
        <h3>插件加载失败</h3>
        <p>找不到插件入口文件 index.html</p>
        </body></html>
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let pluginId: String
        let apiToken: String?
        var onNavigateToBoard: ((String) -> Void)?

        init(pluginId: String, apiToken: String?, onNavigateToBoard: ((String) -> Void)?) {
            self.pluginId = pluginId
            self.apiToken = apiToken
            self.onNavigateToBoard = onNavigateToBoard
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "apiGet":
                handleAPIGet(message)
            case "notificationSend":
                handleNotificationSend(message)
            case "navigateToBoard":
                handleNavigateToBoard(message)
            default:
                break
            }
        }

        private func handleAPIGet(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let path = body["path"] as? String else { return }

            Task { @MainActor in
                do {
                    let data: Data = try await APIClient.shared.getRaw(path)
                    let jsonString = String(data: data, encoding: .utf8) ?? "{}"
                    // 回调 JS（需要 webView 引用，这里简化为 console.log）
                    _ = try? await message.webView?.evaluateJavaScript(
                        "console.log('[API] \(path):', '\(jsonString.prefix(100))')"
                    )
                } catch {
                    print("[WebViewPluginHost] API error: \(error)")
                }
            }
        }

        private func handleNotificationSend(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            let title = body["title"] as? String ?? "通知"
            let bodyText = body["body"] as? String ?? ""
            NotificationCenter.default.post(
                name: .pluginRequestedNotification,
                object: nil,
                userInfo: ["title": title, "body": bodyText]
            )
        }

        private func handleNavigateToBoard(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let boardId = body["boardId"] as? String else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onNavigateToBoard?(boardId)
            }
        }
    }
}

extension Notification.Name {
    static let pluginRequestedNotification = Notification.Name("com.matrixindustry.pluginRequestedNotification")
}
