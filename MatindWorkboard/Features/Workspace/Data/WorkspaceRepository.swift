import Foundation

protocol WorkspaceRepositoryProtocol: Sendable {
    func fetchWorkspaces() async throws -> [Workspace]
}

struct WorkspaceRepository: WorkspaceRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchWorkspaces() async throws -> [Workspace] {
        let response: WorkspaceListResponse = try await client.get("/workspace/list")
        return response.workspaces
    }
}
