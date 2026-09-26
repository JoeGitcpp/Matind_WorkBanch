import Foundation
import CryptoKit
import Testing
@testable import MatindCore

@Suite("Rust宿主跨语言集成") @MainActor
struct RealLocalServiceHostTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MATIND_REAL_LOCAL_SERVICE"] != nil))
    func nativeIdentityAndRestart() async throws {
        let executable = ProcessInfo.processInfo.environment["MATIND_REAL_LOCAL_SERVICE"]!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("matind-native-integration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = LocalServiceHost()
        let key = Curve25519.Signing.PrivateKey()
        let identity = LocalServiceBootstrap(deviceId: UUID(), privateKey: key.rawRepresentation)
        let config = LocalServiceLaunch(executableURL: URL(fileURLWithPath: executable), dataDirectory: root)
        let first = try await host.start(configuration: config, identity: identity)
        #expect(first.identity.deviceId == identity.deviceId)
        #expect(first.identity.publicKey == identity.publicKey)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("device.key").path))
        host.stop()
        let second = try await host.start(configuration: config, identity: identity)
        #expect(second.identity == first.identity)
        host.stop()
    }
}

@Suite("本地执行宿主")
struct LocalServiceHostTests {
    @Test("未安装真实执行程序时拒绝启动，不退回健康检查占位服务")
    @MainActor
    func missingExecutableIsUnavailable() async throws {
        let host = LocalServiceHost()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = LocalServiceLaunch(executableURL: root.appendingPathComponent("missing"), dataDirectory: root)
        await #expect(throws: LocalServiceHostError.executableUnavailable) {
            try await host.start(configuration: config, identity: identity())
        }
        #expect(host.isRunning == false)
    }

    @Test("真实子进程的健康与设备身份都通过后才运行；身份通过stdin传递")
    @MainActor
    func readyRequiresHealthAndMatchingIdentity() async throws {
        let fixture = try SidecarFixture(mode: "ready")
        defer { fixture.clean() }
        let host = LocalServiceHost()
        defer { host.stop() }
        let bootstrap = identity()
        let ready = try await host.start(configuration: fixture.configuration(for: bootstrap), identity: bootstrap)
        #expect(ready.identity.deviceId == bootstrap.deviceId)
        #expect(ready.identity.publicKey == bootstrap.publicKey)
        #expect(ready.port > 0)
        #expect(host.isRunning)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("device.key").path))
        host.stop()
        #expect(!host.isRunning)
    }

    @Test("健康检查正常但设备不匹配时终止子进程")
    @MainActor
    func wrongIdentityFailsClosed() async throws {
        let fixture = try SidecarFixture(mode: "wrong-identity")
        defer { fixture.clean() }
        let host = LocalServiceHost()
        let bootstrap = identity()
        await #expect(throws: LocalServiceHostError.identityMismatch) {
            try await host.start(configuration: fixture.configuration(for: bootstrap), identity: bootstrap)
        }
        #expect(!host.isRunning)
    }

    @Test("不报告就绪的进程在启动超时后停止")
    @MainActor
    func startupTimeoutStopsProcess() async throws {
        let fixture = try SidecarFixture(mode: "never-ready")
        defer { fixture.clean() }
        let host = LocalServiceHost()
        await #expect(throws: LocalServiceHostError.startupTimedOut) {
            try await host.start(configuration: fixture.config, identity: identity())
        }
        #expect(!host.isRunning)
    }

    @Test("暂停启动后不能由旧异步启动把界面变回运行中")
    @MainActor
    func stopCancelsStartingGeneration() async throws {
        let fixture = try SidecarFixture(mode: "never-ready")
        defer { fixture.clean() }
        let host = LocalServiceHost()
        let task = Task { try await host.start(configuration: fixture.config, identity: identity()) }
        try await Task.sleep(for: .milliseconds(70))
        host.stop()
        await #expect(throws: LocalServiceHostError.startCancelled) { try await task.value }
        #expect(!host.isRunning)
    }

    private func identity() -> LocalServiceBootstrap {
        let key = Curve25519.Signing.PrivateKey()
        return LocalServiceBootstrap(deviceId: UUID(), privateKey: key.rawRepresentation)
    }
}

private struct SidecarFixture {
    let root: URL
    let config: LocalServiceLaunch

    init(mode: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("matind-host-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = root.appendingPathComponent("fixture.py")
        let source = #"""
#!/usr/bin/python3
import base64, http.server, json, os, pathlib, sys, time
from uuid import uuid4
bootstrap = json.loads(sys.stdin.readline())
mode = os.environ['FIXTURE_MODE']
if mode == 'never-ready':
    time.sleep(30)
    sys.exit(0)
identity = {'algorithm':'ed25519', 'deviceId':bootstrap['deviceId'], 'publicKey':os.environ['FIXTURE_PUBLIC_KEY']}
if mode == 'wrong-identity': identity['deviceId'] = str(uuid4())
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        value = identity if self.path == '/identity' else {'contractVersion':'local-server-v1','execution':'external-sidecar','loopback':True}
        body = json.dumps(value).encode()
        self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
server = http.server.HTTPServer(('127.0.0.1',0),Handler)
pathlib.Path(os.environ['MATIND_LOCAL_SERVICE_READY_FILE']).write_text(str(server.server_port))
server.serve_forever()
"""#
        try Data(source.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        config = LocalServiceLaunch(executableURL: script, dataDirectory: root, startupTimeout: mode == "never-ready" ? 0.5 : 10, environment: ["FIXTURE_MODE": mode])
    }

    func configuration(for identity: LocalServiceBootstrap) -> LocalServiceLaunch {
        var value = config
        value.environment["FIXTURE_PUBLIC_KEY"] = identity.publicKey
        return value
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
}
