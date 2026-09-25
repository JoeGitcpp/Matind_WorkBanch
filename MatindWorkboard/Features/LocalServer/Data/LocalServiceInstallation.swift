import Foundation
import MatindCore

enum LocalServiceInstallation {
    static func browserPolicy() -> BrowserExecutionPolicy {
        BrowserExecutionPolicy(
            controlPlaneUrl: AppConfig.apiBaseURL,
            driverManifestPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/browser/manifest.json").path,
            nodeExecutable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/node").path
        )
    }
    static func configuration() -> LocalServiceLaunch {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/matind-local-service")
        let dataPath = Bundle.main.object(forInfoDictionaryKey: "MATIND_DISTRIBUTION") as? String == "direct"
            ? "Matind/operations/\(Bundle.main.bundleIdentifier ?? "com.matrixindustry.matind-workboard.operations")/local-server"
            : "Matind/local-server"
        var executable = bundled
        var environment: [String: String] = [:]
        #if DEBUG
        // Only developer builds may use an explicitly selected local build.
        if let path = ProcessInfo.processInfo.environment["MATIND_LOCAL_SERVICE_BINARY"], path.hasPrefix("/") {
            executable = URL(fileURLWithPath: path)
        }
        if Bundle.main.object(forInfoDictionaryKey: "MATIND_DISTRIBUTION") as? String == "direct",
           Bundle.main.object(forInfoDictionaryKey: "MATIND_BUILD_CONFIGURATION") as? String == "LocalOperations",
           let testRoot = Bundle.main.object(forInfoDictionaryKey: "MATIND_TEST_MODULE_PUBLIC_KEY") as? String {
            environment["MATIND_TEST_MODULE_ROOT"] = testRoot
        }
        #endif
        return LocalServiceLaunch(
            executableURL: executable,
            dataDirectory: support.appendingPathComponent(dataPath, isDirectory: true),
            environment: environment
        )
    }
}
