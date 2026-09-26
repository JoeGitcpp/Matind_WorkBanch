import Foundation
import MatindCore
import Observation

/// 同一次新建失败后保留名称和幂等键，重试不会再开一块板。
enum BoardWrite: Equatable {
    case idle
    case creating(name: String, key: UUID)
    case failed(name: String, key: UUID, message: String)
}

@Observable
@MainActor
final class BoardViewModel {
    private(set) var catalog: LoadPhase<[Board]> = .idle
    private(set) var selectedBoardId: String?
    private(set) var write: BoardWrite = .idle

    var boards: [Board] {
        loadedBoards ?? []
    }

    private var loadedBoards: [Board]? {
        if case .loaded(let boards) = catalog {
            return boards
        }
        return nil
    }

    var writeNotice: String? {
        if case .failed(_, _, let message) = write {
            return message
        }
        return nil
    }

    private let repository: any BoardRepositoryProtocol
    private let storage = LocalStorage.shared

    init(repository: any BoardRepositoryProtocol = BoardRepository()) {
        self.repository = repository
    }

    func load(workbenchId: String) async {
        let refreshingLoadedCatalog = loadedBoards != nil
        if !refreshingLoadedCatalog {
            catalog = .loading
        }
        do {
            let boards = try await repository.fetchBoards(workbenchId: workbenchId)
            catalog = LoadPhase<[Board]>.resolve(boards)
            selectedBoardId = restoredSelection(workbenchId: workbenchId, boards: boards)
        } catch {
            catalog = .failed(failure(from: error))
        }
    }

    func createBoard(workbenchId: String) async {
        if case .creating = write { return }
        guard case .loaded = catalog else {
            guard case .empty = catalog else { return }
            await submitCreate(workbenchId: workbenchId, existing: [])
            return
        }
        await submitCreate(workbenchId: workbenchId, existing: boards)
    }

    func retryCreate(workbenchId: String) async {
        await createBoard(workbenchId: workbenchId)
    }

    func rename(workbenchId: String, board: Board, name: String, idempotencyKey: UUID) async throws {
        let updated = try await repository.renameBoard(
            workbenchId: workbenchId,
            boardId: board.id,
            name: name,
            idempotencyKey: idempotencyKey
        )
        replace(updated)
    }

    func delete(workbenchId: String, board: Board, reason: String?, idempotencyKey: UUID) async throws {
        do {
            try await repository.deleteBoard(
                workbenchId: workbenchId,
                board: board,
                reason: reason,
                idempotencyKey: idempotencyKey
            )
        } catch let error as ControlPlaneFailure {
            if case .conflict = error {
                await load(workbenchId: workbenchId)
            }
            throw error
        }
        var remaining = boards
        remaining.removeAll { $0.id == board.id }
        catalog = LoadPhase<[Board]>.resolve(remaining)
        if selectedBoardId == board.id {
            selectedBoardId = remaining.first?.id
        }
        rememberSelection(workbenchId: workbenchId)
    }

    func selectBoard(_ id: String, workbenchId: String) {
        selectedBoardId = id
        rememberSelection(workbenchId: workbenchId)
    }

    private func submitCreate(workbenchId: String, existing: [Board]) async {
        let pending = pendingCreate(existing: existing)
        write = .creating(name: pending.name, key: pending.key)
        do {
            let created = try await repository.createBoard(
                workbenchId: workbenchId,
                name: pending.name,
                idempotencyKey: pending.key
            )
            var next = existing
            if !next.contains(where: { $0.id == created.id }) {
                next.append(created)
            }
            selectedBoardId = created.id
            catalog = LoadPhase<[Board]>.resolve(next)
            write = .idle
            rememberSelection(workbenchId: workbenchId)
        } catch {
            write = .failed(name: pending.name, key: pending.key, message: PresentedFailure.message(for: error))
        }
    }

    private func pendingCreate(existing: [Board]) -> (name: String, key: UUID) {
        if case .failed(let name, let key, _) = write {
            return (name, key)
        }
        return (BoardPageName.next(among: existing.map(\.name)), UUID())
    }

    private func replace(_ board: Board) {
        var next = boards
        guard let index = next.firstIndex(where: { $0.id == board.id }) else { return }
        next[index] = board
        catalog = .loaded(next)
    }

    private func restoredSelection(workbenchId: String, boards: [Board]) -> String? {
        if let last = storage.get(LastVisited.self, forKey: AppConfig.lastVisitedKey),
           last.workbenchId == workbenchId,
           boards.contains(where: { $0.id == last.boardId }) {
            return last.boardId
        }
        return boards.first?.id
    }

    private func rememberSelection(workbenchId: String) {
        guard let selectedBoardId else { return }
        let visited = LastVisited(workbenchId: workbenchId, boardId: selectedBoardId)
        storage.set(visited, forKey: AppConfig.lastVisitedKey)
    }

    private func failure(from error: Error) -> ControlPlaneFailure {
        if let failure = error as? ControlPlaneFailure {
            return failure
        }
        return .unreachable
    }
}
