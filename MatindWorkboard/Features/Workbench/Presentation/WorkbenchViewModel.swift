import Foundation
import Observation

@Observable
@MainActor
final class WorkbenchViewModel {
    private(set) var workbenches: [Workbench] = []
    private(set) var selectedWorkbenchId: String?
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository: any WorkbenchRepositoryProtocol
    private let storage = LocalStorage.shared

    init(repository: any WorkbenchRepositoryProtocol = WorkbenchRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            workbenches = try await repository.fetchWorkbenches()
            // 恢复上次访问的工作台
            if let last = storage.get(LastVisited.self, forKey: AppConfig.lastVisitedKey) {
                if workbenches.contains(where: { $0.id == last.workbenchId }) {
                    selectedWorkbenchId = last.workbenchId
                    return
                }
            }
            selectedWorkbenchId = workbenches.first?.id
        } catch {
            self.error = PresentedFailure.message(for: error)
        }
    }

    func selectWorkbench(_ id: String) {
        selectedWorkbenchId = id
        // 持久化 workbenchId（boardId 重置，由 BoardViewModel.load 后重新写入）
        let visited = LastVisited(workbenchId: id, boardId: "")
        storage.set(visited, forKey: AppConfig.lastVisitedKey)
    }
}
