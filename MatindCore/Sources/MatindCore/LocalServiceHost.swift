import CryptoKit
import Foundation

/// The workbench manages the existing Rust host; it never executes Agent actions itself.
public struct LocalServiceLaunch: Sendable {
    public var executableURL: URL
    public var dataDirectory: URL
    public var startupTimeout: TimeInterval
    public var environment: [String: String]

    public init(executableURL: URL, dataDirectory: URL, startupTimeout: TimeInterval = 10, environment: [String: String] = [:]) {
        self.executableURL = executableURL
        self.dataDirectory = dataDirectory
        self.startupTimeout = startupTimeout
        self.environment = environment
    }
}

/// Secret material travels only through an inherited pipe, never process arguments or disk.
public struct LocalServiceBootstrap: Sendable {
    public let deviceId: UUID
    private let privateKey: Data

    public init(deviceId: UUID, privateKey: Data) {
        self.deviceId = deviceId
        self.privateKey = privateKey
    }

    public var publicKey: String {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey) else { return "" }
        return Self.encode(key.publicKey.rawRepresentation)
    }

    fileprivate func pipeDocument() throws -> Data {
        guard privateKey.count == 32, !publicKey.isEmpty else { throw LocalServiceHostError.invalidIdentity }
        var data = try JSONSerialization.data(withJSONObject: [
            "deviceId": deviceId.uuidString.lowercased(), "privateKey": Self.encode(privateKey)
        ])
        data.append(0x0a)
        return data
    }

    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct LocalServiceIdentity: Codable, Equatable, Sendable {
    public var algorithm: String
    public var deviceId: UUID
    public var publicKey: String

    public init(algorithm: String = "ed25519", deviceId: UUID, publicKey: String) {
        self.algorithm = algorithm; self.deviceId = deviceId; self.publicKey = publicKey
    }
}

public struct LocalServiceReady: Equatable, Sendable {
    public var port: UInt16
    public var identity: LocalServiceIdentity

    public init(port: UInt16, identity: LocalServiceIdentity) {
        self.port = port; self.identity = identity
    }
}

public enum LocalServiceHostError: Error, Equatable, Sendable {
    case executableUnavailable, invalidIdentity, launchFailed, startupTimedOut
    case contractMismatch, identityMismatch, startCancelled, processExited
}

@MainActor
public protocol LocalServiceHosting: AnyObject {
    var isRunning: Bool { get }
    func start(configuration: LocalServiceLaunch, identity: LocalServiceBootstrap) async throws -> LocalServiceReady
    func stop()
}

@MainActor
public final class LocalServiceHost: LocalServiceHosting {
    private var process: Process?
    private var stopping: [Process] = []
    private var startupDirectory: URL?
    private var generation = 0
    private var ready: LocalServiceReady?
    public var isRunning: Bool { process?.isRunning == true && ready != nil }

    public init() {}

    public func start(configuration: LocalServiceLaunch, identity: LocalServiceBootstrap) async throws -> LocalServiceReady {
        stop()
        let current = generation
        // Keep the retiring child until it releases its singleton/profile locks.
        let stopDeadline = Date().addingTimeInterval(6)
        while stopping.contains(where: \.isRunning) {
            guard current == generation, !Task.isCancelled else { throw LocalServiceHostError.startCancelled }
            guard Date() < stopDeadline else { throw LocalServiceHostError.startupTimedOut }
            try await Task.sleep(for: .milliseconds(30))
        }
        stopping.removeAll()
        guard configuration.executableURL.isFileURL,
              FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw LocalServiceHostError.executableUnavailable
        }
        let bootstrap = try identity.pipeDocument()
        let directory = configuration.dataDirectory.appendingPathComponent("startup-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        startupDirectory = directory
        let readyFile = directory.appendingPathComponent("port")
        let child = Process()
        child.executableURL = configuration.executableURL
        child.arguments = ["--health"]
        var environment = ProcessInfo.processInfo.environment.filter { ["PATH", "HOME", "TMPDIR", "LANG"].contains($0.key) }
        environment.merge(configuration.environment) { _, value in value }
        environment["MATIND_LOCAL_IDENTITY_STDIN"] = "1"
        environment["MATIND_LOCAL_DATA"] = configuration.dataDirectory.path
        environment["MATIND_LOCAL_SERVICE_ADDR"] = "127.0.0.1:0"
        environment["MATIND_LOCAL_SERVICE_READY_FILE"] = readyFile.path
        child.environment = environment
        let input = Pipe()
        child.standardInput = input
        // Upstream diagnostics can include untrusted content; UI uses stable error codes.
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        process = child
        do {
            try child.run()
            try input.fileHandleForWriting.write(contentsOf: bootstrap)
            try input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(max(0.1, min(configuration.startupTimeout, 30)))
            while Date() < deadline {
                guard current == generation, !Task.isCancelled else { throw LocalServiceHostError.startCancelled }
                guard child.isRunning else { throw LocalServiceHostError.processExited }
                if let portText = try? String(contentsOf: readyFile, encoding: .utf8),
                   let port = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 {
                    let result = try await verify(port: port, expected: identity)
                    guard current == generation, child.isRunning, !Task.isCancelled else { throw LocalServiceHostError.startCancelled }
                    ready = result
                    try? FileManager.default.removeItem(at: directory)
                    startupDirectory = nil
                    return result
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            throw LocalServiceHostError.startupTimedOut
        } catch {
            if current == generation { stop() }
            if let known = error as? LocalServiceHostError { throw known }
            if error is CancellationError { throw LocalServiceHostError.startCancelled }
            throw LocalServiceHostError.launchFailed
        }
    }

    public func stop() {
        generation += 1
        ready = nil
        if let child = process, child.isRunning {
            child.terminate()
            stopping.append(child)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                // PID belongs to this retained, unreaped Process; do not kill a reused pid.
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        if let startupDirectory { try? FileManager.default.removeItem(at: startupDirectory) }
        startupDirectory = nil
    }

    private func verify(port: UInt16, expected: LocalServiceBootstrap) async throws -> LocalServiceReady {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let healthData = try await response(session: session, port: port, path: "health")
        guard let health = try JSONSerialization.jsonObject(with: healthData) as? [String: Any],
              health["contractVersion"] as? String == "local-server-v1",
              health["execution"] as? String == "external-sidecar",
              health["loopback"] as? Bool == true else { throw LocalServiceHostError.contractMismatch }
        let identityData = try await response(session: session, port: port, path: "identity")
        let identity = try JSONDecoder().decode(LocalServiceIdentity.self, from: identityData)
        guard identity.algorithm == "ed25519", identity.deviceId == expected.deviceId,
              identity.publicKey == expected.publicKey else { throw LocalServiceHostError.identityMismatch }
        return LocalServiceReady(port: port, identity: identity)
    }

    private func response(session: URLSession, port: UInt16, path: String) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(path)") else { throw LocalServiceHostError.contractMismatch }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 16_384,
              response.url?.host == "127.0.0.1", response.url?.port == Int(port) else {
            throw LocalServiceHostError.contractMismatch
        }
        return data
    }
}
