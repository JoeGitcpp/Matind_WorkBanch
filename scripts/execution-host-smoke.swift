import CryptoKit
import Foundation

/// Compile with the production LocalServiceHost/BrowserExecutionPolicy sources,
/// sign with the distribution target entitlements inside the development .app, then run.
/// This checks packaged execution, including applicable sandbox restrictions; it does not simulate the GUI.
@main @MainActor
struct ExecutionHostSmoke {
    static func main() async {
        let host = LocalServiceHost()
        do {
            let app = URL(fileURLWithPath: CommandLine.arguments[1])
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
            guard let rootKey = info["MATIND_TEST_MODULE_PUBLIC_KEY"] as? String else { throw BrowserPolicyError.invalidScope }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("matind-execution-smoke-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let connection = UUID()
            var policy = BrowserExecutionPolicy(controlPlaneUrl: "http://127.0.0.1:9", driverManifestPath: app.appendingPathComponent("Contents/Resources/browser/manifest.json").path, nodeExecutable: app.appendingPathComponent("Contents/Helpers/node").path)
            policy.enabled = true
            policy.bindings = [BrowserAccountBinding(workspaceId: 300_000_000_000_000_001, connectionId: connection, actions: ["browser.observe"], allowedOrigins: ["https://example.com"])]
            try BrowserPolicyStore(directory: root).save(policy)
            let key = Curve25519.Signing.PrivateKey()
            let device = UUID()
            let ready = try await host.start(configuration: LocalServiceLaunch(
                executableURL: app.appendingPathComponent("Contents/Helpers/matind-local-service"), dataDirectory: root,
                environment: ["MATIND_TEST_MODULE_ROOT": rootKey]
            ), identity: LocalServiceBootstrap(deviceId: device, privateKey: key.rawRepresentation))
            let deadline = Date().addingTimeInterval(90)
            var observed: [String: Any] = [:]
            let nonce = UUID()
            var opening = false
            while Date() < deadline {
                let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(ready.port)/health")!)
                let health = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                observed = (health["capabilities"] as? [String: Any])?["localBrowser"] as? [String: Any] ?? [:]
                if observed["ready"] as? Bool == true {
                    if !opening {
                        let command = try LocalProfileCommand(deviceId: device, workspaceId: 300_000_000_000_000_001, connectionId: connection, url: URL(string: "https://example.com/")!, nonce: nonce)
                        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(ready.port)/browser/open-profile")!)
                        request.httpMethod = "POST"
                        request.httpBody = try command.signed(privateKey: key.rawRepresentation)
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        let (_, response) = try await URLSession.shared.data(for: request)
                        guard (response as? HTTPURLResponse)?.statusCode == 202 else { throw BrowserPolicyError.invalidScope }
                        opening = true
                    }
                    if let result = observed["lastOwnerRequest"] as? [String: Any], result["requestId"] as? String == nonce.uuidString.lowercased() {
                        guard result["status"] as? String != "failed" else {
                            print("owner_open_failed: \(result["errorCode"] as? String ?? "unknown")")
                            throw LocalServiceHostError.launchFailed
                        }
                        if result["status"] as? String == "succeeded" {
                            host.stop()
                            print("packaged_host_signed_driver_and_chromium_profile_passed")
                            return
                        }
                    }
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            print("packaged_browser_not_ready: \(observed["errorCode"] as? String ?? "unknown")")
            host.stop()
            exit(1)
        } catch {
            host.stop()
            print("packaged_host_failed: \(error)")
            exit(1)
        }
    }
}
