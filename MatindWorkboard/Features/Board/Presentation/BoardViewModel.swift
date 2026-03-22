import Foundation
import Observation

@Observable
@MainActor
final class BoardViewModel {
    private(set) var boards: [Board] = []
    private(set) var selectedBoardId: String?
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository: any BoardRepositoryProtocol
    private let storage = LocalStorage.shared

    init(repository: any BoardRepositoryProtocol = BoardRepository()) {
        self.repository = repository
    }

    func load(workspaceId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            boards = try await repository.fetchBoards(workspaceId: workspaceId)
            // 恢复上次访问的工作板
            if let last = storage.get(LastVisited.self, forKey: AppConfig.lastVisitedKey),
               last.workspaceId == workspaceId,
               boards.contains(where: { $0.id == last.boardId }) {
                selectedBoardId = last.boardId
                return
            }
            // 选默认板
            selectedBoardId = boards.first(where: { $0.isDefault == true })?.id ?? boards.first?.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 删除工作板，若删除的是当前板则自动回退
    func deleteBoard(_ boardId: String, workspaceId: String) async {
        do {
            try await repository.deleteBoard(boardId: boardId)
            boards.removeAll { $0.id == boardId }
            if selectedBoardId == boardId {
                selectedBoardId = boards.first(where: { $0.isDefault == true })?.id ?? boards.first?.id
            }
            // 删除后刷新 lastVisited（避免冷启动时加载已删除的板）
            if let newSelectedId = selectedBoardId {
                let visited = LastVisited(workspaceId: workspaceId, boardId: newSelectedId)
                LocalStorage.shared.set(visited, forKey: AppConfig.lastVisitedKey)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectBoard(_ id: String, workspaceId: String) {
        selectedBoardId = id
        // 持久化 lastVisited
        let visited = LastVisited(workspaceId: workspaceId, boardId: id)
        LocalStorage.shared.set(visited, forKey: AppConfig.lastVisitedKey)
    }
}
