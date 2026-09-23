import Foundation
import MatindCore

protocol BoardRepositoryProtocol: Sendable {
    func fetchBoards(workbenchId: String) async throws -> [Board]
    func createBoard(workbenchId: String, name: String, idempotencyKey: UUID) async throws -> Board
    func renameBoard(workbenchId: String, boardId: String, name: String, idempotencyKey: UUID) async throws -> Board
    func deleteBoard(workbenchId: String, board: Board, reason: String?, idempotencyKey: UUID) async throws
}

struct BoardRepository: BoardRepositoryProtocol {
    private let transport: ControlPlaneTransport

    init(transport: ControlPlaneTransport = .shared) {
        self.transport = transport
    }

    func fetchBoards(workbenchId: String) async throws -> [Board] {
        let data = try await transport.send(
            .get,
            path: "/api/v1/workbenches/\(workbenchId)/boards",
            body: nil,
            token: try await accessToken()
        )
        return try BoardReceiptParser.catalog(data).boards.map(Board.init)
    }

    func createBoard(workbenchId: String, name: String, idempotencyKey: UUID) async throws -> Board {
        let body = try BoardDocuments.create(name: name, idempotencyKey: idempotencyKey)
        let data = try await transport.send(
            .post,
            path: "/api/v1/workbenches/\(workbenchId)/boards",
            body: body,
            token: try await accessToken()
        )
        return Board(try BoardReceiptParser.mutation(data).board)
    }

    func renameBoard(workbenchId: String, boardId: String, name: String, idempotencyKey: UUID) async throws -> Board {
        let body = try BoardDocuments.rename(name: name, idempotencyKey: idempotencyKey)
        let data = try await transport.send(
            .patch,
            path: "/api/v1/workbenches/\(workbenchId)/boards/\(boardId)",
            body: body,
            token: try await accessToken()
        )
        return Board(try BoardReceiptParser.mutation(data).board)
    }

    func deleteBoard(workbenchId: String, board: Board, reason: String?, idempotencyKey: UUID) async throws {
        let body = try BoardDocuments.delete(
            expectedName: board.name,
            expectedAccessRevision: board.accessRevision,
            idempotencyKey: idempotencyKey,
            reason: reason
        )
        let data = try await transport.send(
            .delete,
            path: "/api/v1/workbenches/\(workbenchId)/boards/\(board.id)",
            body: body,
            token: try await accessToken()
        )
        _ = try BoardReceiptParser.deletion(data)
    }

    private func accessToken() async throws -> String {
        guard let token = await APIClient.shared.currentToken(), !token.isEmpty else {
            throw ControlPlaneFailure.unauthenticated
        }
        return token
    }
}
