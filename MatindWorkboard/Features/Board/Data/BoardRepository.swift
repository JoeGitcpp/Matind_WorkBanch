import Foundation

protocol BoardRepositoryProtocol: Sendable {
    func fetchBoards(workbenchId: String) async throws -> [Board]
    func deleteBoard(boardId: String) async throws
}

struct BoardRepository: BoardRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchBoards(workbenchId: String) async throws -> [Board] {
        let response: BoardListResponse = try await client.get("/board/list?workbench_id=\(workbenchId)")
        return response.boards
    }

    func deleteBoard(boardId: String) async throws {
        struct DeleteResponse: Codable { let success: Bool? }
        let _: DeleteResponse = try await client.post("/board/delete", body: ["id": boardId])
    }
}
