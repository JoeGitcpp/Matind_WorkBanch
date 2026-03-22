import SwiftUI

struct ContentView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        Group {
            if authState.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}

struct MainView: View {
    @State private var workspaceVM = WorkspaceViewModel()
    @State private var boardVM = BoardViewModel()

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebarView(
                selectedWorkspaceId: Binding(
                    get: { workspaceVM.selectedWorkspaceId },
                    set: { workspaceVM.selectWorkspace($0 ?? "") }
                ),
                workspaces: workspaceVM.workspaces,
                isLoading: workspaceVM.isLoading,
                error: workspaceVM.error
            )
        } detail: {
            if let wsId = workspaceVM.selectedWorkspaceId {
                BoardTabView(
                    selectedBoardId: Binding(
                        get: { boardVM.selectedBoardId },
                        set: { id in
                            if let id { boardVM.selectBoard(id, workspaceId: wsId) }
                        }
                    ),
                    boards: boardVM.boards,
                    workspaceId: wsId,
                    onDelete: { boardId in
                        await boardVM.deleteBoard(boardId, workspaceId: wsId)
                    }
                )
                .task(id: wsId) {
                    await boardVM.load(workspaceId: wsId)
                }
            } else {
                ContentUnavailableView("选择协作空间", systemImage: "folder")
            }
        }
        .navigationTitle("Matind Workboard")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {}) {
                    Image(systemName: "bell")
                }
                .help("通知中心")
            }
        }
        .task {
            await workspaceVM.load()
        }
    }
}

// LoginPlaceholderView 已由 LoginView 替代
