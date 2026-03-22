import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "未授权，请重新登录"
        case .networkError(let err): return "网络错误：\(err.localizedDescription)"
        case .decodingError(let err): return "数据解析失败：\(err.localizedDescription)"
        case .serverError(let code, let msg): return "服务器错误 \(code)：\(msg ?? "未知错误")"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var token: String?

    // 允许注入 session（用于测试）
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: config)
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func buildRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: AppConfig.apiBaseURL + path) else {
            throw APIError.networkError(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            switch http.statusCode {
            case 200..<300:
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw APIError.decodingError(error)
                }
            case 401:
                Task { @MainActor in
                    NotificationCenter.default.post(name: .unauthorizedResponse, object: nil)
                }
                throw APIError.unauthorized
            default:
                let message = String(data: data, encoding: .utf8)
                throw APIError.serverError(statusCode: http.statusCode, message: message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

extension Notification.Name {
    static let unauthorizedResponse = Notification.Name("com.matrixindustry.unauthorizedResponse")
}
