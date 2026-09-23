import Foundation
import MatindCore

/// 把准备好的请求发出去，并把控制面的状态码翻译成领域错误。
struct ControlPlaneTransport: Sendable {
    static let shared = ControlPlaneTransport()

    func data(for request: PreparedRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw ControlPlaneFailure.unreachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ControlPlaneFailure.undecodable
        }
        guard (200..<300).contains(http.statusCode) else {
            let failure = ResponseInterpreter.failure(
                statusCode: http.statusCode,
                headers: headerMap(http),
                body: data
            )
            if case .unauthenticated = failure {
                NotificationCenter.default.post(name: .unauthorizedResponse, object: nil)
            }
            throw failure
        }
        return data
    }

    func send(_ method: RequestMethod, path: String, body: Data?, token: String) async throws -> Data {
        guard let baseURL = AppConfig.apiBase else {
            throw ControlPlaneFailure.undecodable
        }
        let request = try ControlPlaneRequest.prepare(
            baseURL: baseURL,
            method: method,
            path: path,
            body: body,
            token: token,
            requestID: UUID().uuidString
        )
        return try await data(for: request)
    }

    func envelope<T: Decodable>(
        _ method: RequestMethod,
        path: String,
        body: Data? = nil,
        token: String,
        as type: T.Type
    ) async throws -> T {
        guard let baseURL = AppConfig.apiBase else {
            throw ControlPlaneFailure.undecodable
        }
        let request = try ControlPlaneRequest.prepare(
            baseURL: baseURL,
            method: method,
            path: path,
            body: body,
            token: token,
            requestID: UUID().uuidString
        )
        let data = try await data(for: request)
        return try ResponseInterpreter.envelope(data, as: type)
    }

    /// 兑换或续期桌面会话（后端代理，不经客户端直连身份服务）。
    func desktopSession(for request: PreparedRequest) async throws -> IdentityGrant {
        let data = try await data(for: request)
        return try DesktopSessionParser.parse(data, now: Date())
    }

    private func headerMap(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (field, value) in response.allHeaderFields {
            guard let field = field as? String, let value = value as? String else { continue }
            headers[field] = value
        }
        return headers
    }
}
