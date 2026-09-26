import Foundation
import Network

/// 本机服务只接受回环地址。
enum LoopbackBind {
    static let host = "127.0.0.1"
}

struct LoopbackHealth: Codable, Equatable, Sendable {
    let bind: String
    let contractVersion: String
}

enum LoopbackError: Error {
    case unbound
}

/// 只在回环接口上回答健康检查，不携带业务数据。
final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "matind.loopback.server")
    private var listener: NWListener?

    func start(health: LoopbackHealth) async throws -> UInt16 {
        stop()
        let body = try JSONEncoder().encode(health)
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        guard let ephemeral = NWEndpoint.Port(rawValue: 0) else {
            throw LoopbackError.unbound
        }
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .init(LoopbackBind.host),
            port: ephemeral
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                Self.resume(state, listener: listener, gate: gate, continuation: continuation)
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                Self.readRequest(connection: connection, buffer: Data(), health: body)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        let current = listener
        listener = nil
        current?.cancel()
    }

    private static func resume(
        _ state: NWListener.State,
        listener: NWListener,
        gate: ResumeGate,
        continuation: CheckedContinuation<UInt16, Error>
    ) {
        switch state {
        case .ready:
            gate.run {
                guard let port = listener.port?.rawValue, port > 0 else {
                    continuation.resume(throwing: LoopbackError.unbound)
                    return
                }
                continuation.resume(returning: port)
            }
        case .failed(let error):
            gate.run { continuation.resume(throwing: error) }
        case .cancelled:
            gate.run { continuation.resume(throwing: CancellationError()) }
        default:
            break
        }
    }

    private static func readRequest(connection: NWConnection, buffer: Data, health: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data, !data.isEmpty { next.append(data) }
            if requestReady(next, isComplete: isComplete) {
                respond(connection: connection, request: next, health: health)
                return
            }
            if data == nil {
                connection.cancel()
                return
            }
            readRequest(connection: connection, buffer: next, health: health)
        }
    }

    private static func requestReady(_ buffer: Data, isComplete: Bool) -> Bool {
        buffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete || buffer.count >= 8192
    }

    private static func respond(connection: NWConnection, request: Data, health: Data) {
        let header = String(data: request, encoding: .utf8) ?? ""
        let ok = header.hasPrefix("GET /health")
        let payload = ok ? health : Data(#"{"error":"not-found"}"#.utf8)
        let status = ok ? "200 OK" : "404 Not Found"
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var bytes = Data(head.utf8)
        bytes.append(payload)
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// 保证续体只恢复一次（监听状态、超时与取消可能同时到达）。
final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func run(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !resumed
        if shouldRun { resumed = true }
        lock.unlock()
        if shouldRun { body() }
    }
}
