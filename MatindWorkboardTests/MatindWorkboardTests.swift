import Testing
import Foundation
@testable import MatindWorkboard

@Suite("AppConfig Tests")
struct AppConfigTests {
    @Test("API base URL is correct")
    func apiBaseURL() {
        #expect(AppConfig.apiBaseURL == "https://api.matind.com")
    }

    @Test("Keychain service name is correct")
    func keychainService() {
        #expect(AppConfig.keychainService == "matind-workboard")
    }
}

@Suite("AuthService Tests")
struct AuthServiceTests {
    @Test("Token save and load roundtrip")
    func tokenRoundtrip() throws {
        let service = AuthService()
        let testToken = "test-token-\(UUID().uuidString)"

        try service.saveToken(testToken)
        let loaded = service.loadToken()
        #expect(loaded == testToken)

        service.clearToken()
        #expect(service.loadToken() == nil)
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - APIClient Tests

@Suite("APIClient Tests")
struct APIClientTests {

    func makeMockClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(session: session)
    }

    @Test("GET request includes Bearer token in Authorization header")
    func getRequestIncludesBearerToken() async throws {
        let client = makeMockClient()
        await client.setToken("test-token-abc")

        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONEncoder().encode(["key": "value"])
            return (response, data)
        }

        let _: [String: String] = try await client.get("/test")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-abc")
    }

    @Test("401 response throws APIError.unauthorized")
    func unauthorizedResponseThrowsCorrectError() async throws {
        let client = makeMockClient()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            let _: [String: String] = try await client.get("/protected")
            Issue.record("Expected APIError.unauthorized but no error was thrown")
        } catch APIError.unauthorized {
            // 期望的错误
        } catch {
            Issue.record("Expected APIError.unauthorized but got: \(error)")
        }
    }

    @Test("Malformed JSON throws APIError.decodingError")
    func malformedJSONThrowsDecodingError() async throws {
        let client = makeMockClient()

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, "not json".data(using: .utf8)!)
        }

        do {
            let _: User = try await client.get("/user")
            Issue.record("Expected decoding error")
        } catch APIError.decodingError {
            // 期望的错误
        } catch {
            Issue.record("Expected APIError.decodingError but got: \(error)")
        }
    }
}

// MARK: - BoardViewModel Tests

@Suite("BoardViewModel Tests")
struct BoardViewModelTests {
    @Test("Deleting current board selects default board")
    @MainActor
    func deletingCurrentBoardSelectsDefault() async {
        let boards = [
            Board(id: "b1", workspaceId: "ws1", name: "主板", isDefault: true, config: nil, createdAt: nil),
            Board(id: "b2", workspaceId: "ws1", name: "副板", isDefault: false, config: nil, createdAt: nil)
        ]
        let vm = BoardViewModel(repository: MockBoardRepository(boards: boards))
        await vm.load(workspaceId: "ws1")
        #expect(vm.selectedBoardId == "b1") // 默认板被选中

        await vm.deleteBoard("b1", workspaceId: "ws1")
        // 删除后应回退到下一个可用板
        #expect(vm.selectedBoardId == "b2")
        #expect(vm.boards.count == 1)
    }

    @Test("lastVisited is persisted on board selection")
    @MainActor
    func lastVisitedIsPersistedOnSelection() {
        let vm = BoardViewModel(repository: MockBoardRepository(boards: []))
        vm.selectBoard("b99", workspaceId: "ws1")
        let loaded = LocalStorage.shared.get(LastVisited.self, forKey: AppConfig.lastVisitedKey)
        #expect(loaded?.boardId == "b99")
        #expect(loaded?.workspaceId == "ws1")
    }
}

// Mock 实现
struct MockBoardRepository: BoardRepositoryProtocol {
    let boards: [Board]

    func fetchBoards(workspaceId: String) async throws -> [Board] { boards }
    func deleteBoard(boardId: String) async throws {}
}
