import Foundation
import Darwin

public enum BrowserPolicyError: Error, Equatable, Sendable {
    case invalidScope, invalidOrigin, invalidLocation
}

public struct BrowserAccountBinding: Codable, Equatable, Sendable, Identifiable {
    public let workspaceId: Int64
    public let connectionId: UUID
    public var actions: [String]
    public var allowedOrigins: [String]
    public var id: UUID { connectionId }

    public init(workspaceId: Int64, connectionId: UUID, actions: [String], allowedOrigins: [String]) {
        self.workspaceId = workspaceId
        self.connectionId = connectionId
        self.actions = actions
        self.allowedOrigins = allowedOrigins
    }

    private enum CodingKeys: String, CodingKey { case workspaceId, connectionId, actions, allowedOrigins }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let text = try values.decode(String.self, forKey: .workspaceId)
        guard let id = Int64(text), id > 0, String(id) == text else {
            throw DecodingError.dataCorruptedError(forKey: .workspaceId, in: values, debugDescription: "Expected a canonical positive decimal identifier")
        }
        workspaceId = id
        connectionId = try values.decode(UUID.self, forKey: .connectionId)
        actions = try values.decode([String].self, forKey: .actions)
        allowedOrigins = try values.decode([String].self, forKey: .allowedOrigins)
    }

    public func encode(to encoder: any Encoder) throws {
        guard workspaceId > 0 else { throw BrowserPolicyError.invalidScope }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(String(workspaceId), forKey: .workspaceId)
        try values.encode(connectionId, forKey: .connectionId)
        try values.encode(actions, forKey: .actions)
        try values.encode(allowedOrigins, forKey: .allowedOrigins)
    }

    public func validated(allowedActions: Set<String>) throws {
        let supported: Set<String> = ["browser.observe", "browser.navigate", "browser.fill", "browser.click"]
        guard workspaceId > 0,
              !actions.isEmpty, Set(actions).isSubset(of: supported.intersection(allowedActions)),
              !allowedOrigins.isEmpty, allowedOrigins.count <= 20 else { throw BrowserPolicyError.invalidScope }
        for value in allowedOrigins {
            guard let url = URLComponents(string: value), url.scheme == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  url.path.isEmpty, url.port == nil || (1...65535).contains(url.port!) else {
                throw BrowserPolicyError.invalidOrigin
            }
            guard try Self.normalizedOrigin(value) == value else { throw BrowserPolicyError.invalidOrigin }
        }
    }

    public static func normalizedOrigin(_ value: String) throws -> String {
        guard var url = URLComponents(string: value), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.port == nil || (1...65535).contains(url.port!) else {
            throw BrowserPolicyError.invalidOrigin
        }
        url.scheme = "https"
        url.host = host.lowercased()
        url.path = ""
        if url.port == 443 { url.port = nil }
        guard let result = url.string else { throw BrowserPolicyError.invalidOrigin }
        return result
    }
}

public struct BrowserExecutionPolicy: Codable, Equatable, Sendable {
    public var contractVersion = "external-action-v1"
    public var enabled = false
    public var controlPlaneUrl: String
    public var driverManifestPath: String
    public var nodeExecutable: String
    public var bindings: [BrowserAccountBinding] = []

    public init(controlPlaneUrl: String, driverManifestPath: String, nodeExecutable: String) {
        self.controlPlaneUrl = controlPlaneUrl
        self.driverManifestPath = driverManifestPath
        self.nodeExecutable = nodeExecutable
    }
}

public struct BrowserPolicyStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> BrowserExecutionPolicy? {
        let url = directory.appendingPathComponent("browser-policy.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 65536 else { throw BrowserPolicyError.invalidScope }
        return try JSONDecoder().decode(BrowserExecutionPolicy.self, from: data)
    }

    public func save(_ policy: BrowserExecutionPolicy) throws {
        guard policy.contractVersion == "external-action-v1", policy.driverManifestPath.hasPrefix("/"),
              policy.nodeExecutable.hasPrefix("/"), policy.bindings.count <= 64 else { throw BrowserPolicyError.invalidLocation }
        for binding in policy.bindings { try binding.validated(allowedActions: Set(binding.actions)) }
        guard Set(policy.bindings.map { "\($0.workspaceId):\($0.connectionId)" }).count == policy.bindings.count else {
            throw BrowserPolicyError.invalidScope
        }
        let fm = FileManager.default
        let bytes = try JSONEncoder().encode(policy)
        guard bytes.count <= 65536 else { throw BrowserPolicyError.invalidScope }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Create with 0600 before publishing; never expose an atomic temp file as 0644.
        let temporary = directory.appendingPathComponent(".policy-\(UUID().uuidString)")
        guard fm.createFile(atPath: temporary.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else {
            throw BrowserPolicyError.invalidLocation
        }
        defer { try? fm.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        guard rename(temporary.path, directory.appendingPathComponent("browser-policy.json").path) == 0 else {
            throw BrowserPolicyError.invalidLocation
        }
        // Persist the rename itself before reporting a revocation or disable as saved.
        let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        guard directoryDescriptor >= 0 else { throw BrowserPolicyError.invalidLocation }
        defer { close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else { throw BrowserPolicyError.invalidLocation }
    }
}
