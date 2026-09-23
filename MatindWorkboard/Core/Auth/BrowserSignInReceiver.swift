import Foundation
import MatindCore
import Network

enum BrowserSignInFailure: Error, Equatable {
    case denied
    case timedOut
    case unbound
}

/// 浏览器授权的本机回跳接收端（RFC 8252 回环重定向）。
/// 只绑定 127.0.0.1 的临时端口；只认本次授权的 state，其余请求一律 404 并继续等待。
final class BrowserSignInReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "matind.signin.loopback")
    private var listener: NWListener?
    /// 以下状态只在 queue 上读写。
    private var authorization: BrowserAuthorization?
    private var waiter: CheckedContinuation<String, Error>?
    /// 每次等待递增，过期的超时计时器据此失效。
    private var attempt = 0

    /// 启动监听，返回回跳地址。
    func start() async throws -> URL {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        guard let ephemeral = NWEndpoint.Port(rawValue: 0) else {
            throw BrowserSignInFailure.unbound
        }
        parameters.requiredLocalEndpoint = .hostPort(host: .init(LoopbackBind.host), port: ephemeral)
        let listener = try NWListener(using: parameters)
        queue.sync { self.listener = listener }
        let gate = ResumeGate()
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.run {
                        if let port = listener.port?.rawValue, port > 0 {
                            continuation.resume(returning: port)
                        } else {
                            continuation.resume(throwing: BrowserSignInFailure.unbound)
                        }
                    }
                case .failed(let error):
                    gate.run { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
        guard let url = URL(string: "http://\(LoopbackBind.host):\(port)/callback") else {
            throw BrowserSignInFailure.unbound
        }
        return url
    }

    /// 等待本次授权的回跳；监听就绪后才调用 `open` 打开浏览器，避免回跳早于等待。
    func awaitCode(
        for authorization: BrowserAuthorization,
        timeout: TimeInterval,
        open: @escaping @Sendable () -> Void
    ) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.attempt += 1
                    let current = self.attempt
                    self.authorization = authorization
                    self.waiter = continuation
                    self.queue.asyncAfter(deadline: .now() + timeout) {
                        guard self.attempt == current else { return }
                        self.finish(.failure(BrowserSignInFailure.timedOut))
                    }
                    open()
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    /// 只在 queue 上调用：恢复等待者一次并关闭监听。
    private func finish(_ result: Result<String, Error>) {
        let pending = waiter
        waiter = nil
        authorization = nil
        attempt += 1
        listener?.cancel()
        listener = nil
        pending?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            let headerEnded = next.range(of: Data("\r\n\r\n".utf8)) != nil
            if headerEnded || isComplete || next.count >= 8192 {
                self.respond(connection, request: next)
            } else {
                self.read(connection, buffer: next)
            }
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        let outcome = requestTarget(request).map { authorization?.outcome(of: $0) ?? .unrelated } ?? .unrelated
        switch outcome {
        case .granted(let code):
            send(connection, status: "200 OK", page: "登录成功，可以关闭此页，回到 Matind Workboard。")
            finish(.success(code))
        case .denied:
            send(connection, status: "200 OK", page: "已取消授权，可以关闭此页。")
            finish(.failure(BrowserSignInFailure.denied))
        case .unrelated:
            send(connection, status: "404 Not Found", page: "")
        }
    }

    /// 只接受 `GET <target> HTTP/1.x` 请求行。
    private func requestTarget(_ request: Data) -> String? {
        guard let head = String(data: request, encoding: .utf8)?.split(separator: "\r\n").first else {
            return nil
        }
        let parts = head.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/1.") else {
            return nil
        }
        return String(parts[1])
    }

    private func send(_ connection: NWConnection, status: String, page: String) {
        let body = Data("<!doctype html><meta charset=\"utf-8\"><title>Matind Workboard</title><p>\(page)</p>".utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var bytes = Data(head.utf8)
        bytes.append(body)
        connection.send(content: bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
