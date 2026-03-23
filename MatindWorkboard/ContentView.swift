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
    @State private var workbenchVM = WorkbenchViewModel()
    @State private var boardVM = BoardViewModel()
    @State private var tabManager = TabManager()
    @State private var notificationVM = NotificationViewModel()
    @State private var showNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            // 唯一的标签栏
            AppTabBar(
                tabs: tabManager.tabs,
                selectedTabId: tabManager.selectedTabId,
                onSelect: { tabManager.select($0) },
                onClose: { tabManager.close($0) },
                onAdd: {}
            )

            Divider()

            // 内容区
            if let tab = tabManager.selectedTab {
                tabContent(for: tab)
            } else {
                ContentUnavailableView("选择工作台", systemImage: "folder")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(navigationTitle)
        .toolbar {
            // 工作台选择器（左侧）
            ToolbarItem(placement: .navigation) {
                WorkbenchPicker(
                    workbenches: workbenchVM.workbenches,
                    selectedId: workbenchVM.selectedWorkbenchId,
                    isLoading: workbenchVM.isLoading,
                    onSelect: { workbenchVM.selectWorkbench($0) }
                )
            }

            // 通知按钮（右侧）
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
        .task { await workbenchVM.load() }
        .task {
            await notificationVM.requestNotificationPermission()
            await notificationVM.loadUnreadCount()
        }
        .onChange(of: workbenchVM.selectedWorkbenchId) { _, newId in
            handleWorkbenchChange(newId)
        }
        .onChange(of: boardVM.boards) { _, boards in
            tabManager.syncBoardTabs(boards, selectedBoardId: boardVM.selectedBoardId)
        }
        .onChange(of: tabManager.selectedBoardId) { _, newBoardId in
            handleTabBoardChange(newBoardId)
        }
        // 监听系统菜单命令
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            tabManager.openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAutomation)) { _ in
            tabManager.openAutomation()
        }
    }

    // MARK: - 导航标题（显示当前标签名）

    private var navigationTitle: String {
        tabManager.selectedTab?.title ?? "Matind Workboard"
    }

    // MARK: - 标签内容路由

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .board(let id, _):
            BoardContentView(boardId: id)
        case .settings:
            SettingsView()
        case .automation:
            AutomationView()
        }
    }

    // MARK: - 事件处理

    private func handleWorkbenchChange(_ newId: String?) {
        guard let wbId = newId else { return }
        Task { await boardVM.load(workbenchId: wbId) }
    }

    private func handleTabBoardChange(_ newBoardId: String?) {
        guard let boardId = newBoardId,
              let wbId = workbenchVM.selectedWorkbenchId else { return }
        boardVM.selectBoard(boardId, workbenchId: wbId)
    }
}

// MARK: - 工作台选择器

struct WorkbenchPicker: View {
    let workbenches: [Workbench]
    let selectedId: String?
    let isLoading: Bool
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            if isLoading {
                Text("加载中...")
            } else if workbenches.isEmpty {
                Text("暂无工作台")
            } else {
                ForEach(workbenches) { wb in
                    Button {
                        onSelect(wb.id)
                    } label: {
                        HStack {
                            Text(wb.name)
                            if wb.id == selectedId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12))
                Text(selectedName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedName: String {
        if isLoading { return "加载中..." }
        guard let id = selectedId,
              let wb = workbenches.first(where: { $0.id == id }) else {
            return "选择工作台"
        }
        return wb.name
    }
}
