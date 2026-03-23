import Foundation

protocol WorkbenchRepositoryProtocol: Sendable {
    func fetchWorkbenches() async throws -> [Workbench]
}

struct WorkbenchRepository: WorkbenchRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchWorkbenches() async throws -> [Workbench] {
        let response: ApiResponse<[Workbench]> = try await client.get("/api/v1/workbenches")
        return response.data ?? []
    }
}
