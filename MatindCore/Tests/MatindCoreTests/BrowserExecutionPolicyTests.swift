import Foundation
import Testing
@testable import MatindCore

@Suite("浏览器本机授权")
struct BrowserExecutionPolicyTests {
    @Test("真实雪花编号以规范字符串往返，拒绝有损数字与非规范编号")
    func snowflakeWire() throws {
        let binding = BrowserAccountBinding(workspaceId: 300_000_000_000_000_001, connectionId: UUID(), actions: ["browser.observe"], allowedOrigins: ["https://example.com"])
        try binding.validated(allowedActions: ["browser.observe"])
        let bytes = try JSONEncoder().encode(binding)
        var wire = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        #expect(wire["workspaceId"] as? String == "300000000000000001")
        #expect(try JSONDecoder().decode(BrowserAccountBinding.self, from: bytes) == binding)
        for invalid: Any in [300_000_000_000_000_001 as Int64, "0300000000000000001", "0", "-1", "1e3", "9223372036854775808"] {
            wire["workspaceId"] = invalid
            let input = try JSONSerialization.data(withJSONObject: wire)
            #expect(throws: Error.self) { try JSONDecoder().decode(BrowserAccountBinding.self, from: input) }
        }
    }
    @Test("本机网站边界与Rust执行器规范一致")
    func originCanonicalization() throws {
        #expect(try BrowserAccountBinding.normalizedOrigin("https://EXAMPLE.com:443/") == "https://example.com")
        #expect(try BrowserAccountBinding.normalizedOrigin("https://example.com:8443") == "https://example.com:8443")
        let excessive = BrowserAccountBinding(workspaceId: 10, connectionId: UUID(), actions: ["browser.observe"], allowedOrigins: (1...21).map { "https://site\($0).example.com" })
        #expect(throws: BrowserPolicyError.self) { try excessive.validated(allowedActions: ["browser.observe"]) }
    }
    @Test("策略拒绝凭据URL、非origin与扩大动作")
    func rejectsUnsafeScope() throws {
        let binding = BrowserAccountBinding(workspaceId: 10, connectionId: UUID(), actions: ["browser.observe"], allowedOrigins: ["https://example.com"])
        #expect(throws: BrowserPolicyError.self) { try binding.validated(allowedActions: ["browser.navigate"]) }
        for origin in ["http://example.com", "https://user:password@example.com", "https://example.com/private", "https://example.com?token=x", "file:///tmp"] {
            let invalid = BrowserAccountBinding(workspaceId: 10, connectionId: UUID(), actions: ["browser.observe"], allowedOrigins: [origin])
            #expect(throws: BrowserPolicyError.self) { try invalid.validated(allowedActions: ["browser.observe"]) }
        }
    }

    @Test("策略落盘权限仅所有者，收窄与删除不保留旧绑定")
    func persistsAndRemoves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserPolicyStore(directory: root)
        let connectionId = UUID()
        var policy = BrowserExecutionPolicy(controlPlaneUrl: "https://api.example.com", driverManifestPath: "/opt/matind/browser/manifest.json", nodeExecutable: "/opt/matind/node")
        policy.enabled = true
        policy.bindings = [BrowserAccountBinding(workspaceId: 10, connectionId: connectionId, actions: ["browser.observe"], allowedOrigins: ["https://example.com"])]
        try store.save(policy)
        #expect(try store.load() == policy)
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("browser-policy.json").path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        policy.bindings.removeAll()
        try store.save(policy)
        #expect(try store.load()?.bindings.isEmpty == true)
    }

    @Test("损坏已有策略不能默默恢复为更大权限")
    func corruptPolicyFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: root.appendingPathComponent("browser-policy.json"))
        #expect(throws: Error.self) { try BrowserPolicyStore(directory: root).load() }
    }
}
