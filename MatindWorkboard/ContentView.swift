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
    @State private var notificationVM = NotificationViewModel()
    @State private var showNotifications = false

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
                    selectedBoardId: boardVM.selectedBoardId,
                    boards: boardVM.boards,
                    workspaceId: wsId,
                    onSelect: { boardId in
                        boardVM.selectBoard(boardId, workspaceId: wsId)
                    },
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
                Button(action: { showNotifications.toggle() }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        NotificationBadge(count: notificationVM.unreadCount)
                            .offset(x: 6, y: -6)
                    }
                }
                .help("通知中心")
                .popover(isPresented: $showNotifications, arrowEdge: .bottom) {
                    NotificationCenterView(viewModel: notificationVM)
                }
            }
        }
        .task {
            await workspaceVM.load()
        }
        .task {
            await notificationVM.requestNotificationPermission()
            await notificationVM.loadUnreadCount()
        }
    }
}

// LoginPlaceholderView 已由 LoginView 替代
