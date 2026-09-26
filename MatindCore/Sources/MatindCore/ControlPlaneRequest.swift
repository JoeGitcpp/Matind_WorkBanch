import Foundation

public enum RequestMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct PreparedRequest: Equatable, Sendable {
    public var method: RequestMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: RequestMethod, url: URL, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public enum ControlPlaneRequest {
    public static func prepare(
        baseURL: URL,
        method: RequestMethod,
        path: String,
        body: Data?,
        token: String?,
        requestID: String
    ) throws -> PreparedRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ControlPlaneFailure.undecodable
        }
        var headers = [
            "Accept": "application/json",
            "x-request-id": requestID
        ]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        if let token {
            headers["Authorization"] = "Bearer \(token)"
        }
        return PreparedRequest(method: method, url: url, headers: headers, body: body)
    }
}

public enum ResponseInterpreter {
    public static func failure(statusCode: Int, headers: [String: String], body: Data) -> ControlPlaneFailure {
        let document = try? JSONDecoder().decode(FailureDocument.self, from: body)
        switch statusCode {
        case 401:
            return .unauthenticated
        case 403:
            return .forbidden
        case 404:
            return .missing
        case 409, 412:
            return conflict(document)
        case 422:
            return .invalid(fields: document?.fieldErrors ?? [:])
        case 503:
            return unavailable(document, headers: headers)
        default:
            return .unavailable(retryAfterSeconds: retryAfter(headers))
        }
    }

    private static func conflict(_ document: FailureDocument?) -> ControlPlaneFailure {
        guard let precondition = document?.precondition else {
            return .conflict(precondition: "unknown", currentRevision: document?.currentRevision)
        }
        return .conflict(precondition: precondition, currentRevision: document?.currentRevision)
    }

    private static func unavailable(_ document: FailureDocument?, headers: [String: String]) -> ControlPlaneFailure {
        if document?.outcome == "pending", let operationID = document?.operationId {
            return .pending(operationId: operationID)
        }
        return .unavailable(retryAfterSeconds: document?.retryAfterSeconds ?? retryAfter(headers))
    }

    private static func retryAfter(_ headers: [String: String]) -> Int? {
        let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
        return value.flatMap(Int.init)
    }

    public static func envelope<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        guard let payload = envelope.data else {
            throw ControlPlaneFailure.undecodable
        }
        return payload
    }
}

public struct APIEnvelope<T: Decodable>: Decodable {
    public var code: Int
    public var msg: String
    public var data: T?
}

private struct FailureDocument: Decodable {
    var fieldErrors: [String: [String]]?
    var precondition: String?
    var currentRevision: String?
    var retryAfterSeconds: Int?
    var outcome: String?
    var operationId: String?
}
