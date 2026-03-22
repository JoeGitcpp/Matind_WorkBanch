import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceViewModel {
    private(set) var workspaces: [Workspace] = []
    private(set) var selectedWorkspaceId: String?
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository: any WorkspaceRepositoryProtocol
    private let storage = LocalStorage.shared

    init(repository: any WorkspaceRepositoryProtocol = WorkspaceRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            workspaces = try await repository.fetchWorkspaces()
            // 恢复上次访问的工作区
            if let last = storage.get(LastVisited.self, forKey: AppConfig.lastVisitedKey) {
                if workspaces.contains(where: { $0.id == last.workspaceId }) {
                    selectedWorkspaceId = last.workspaceId
                    return
                }
            }
            selectedWorkspaceId = workspaces.first?.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectWorkspace(_ id: String) {
        selectedWorkspaceId = id
    }
}
