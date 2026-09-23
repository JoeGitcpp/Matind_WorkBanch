import SwiftUI

@main
struct MatindWorkboardApp: App {
    @State private var authState = AuthState()
    @State private var localServer = LocalServerState()

    init() {
        // 初始化通知服务（设置 delegate）
        _ = NotificationService.shared

        // 禁用系统 tab bar（避免出现两层标签栏）
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authState)
                .environment(localServer)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // 替换系统"新建窗口"为我们的操作
            CommandGroup(replacing: .newItem) {}

            // 工具菜单
            CommandMenu("工具") {
                Button("设置") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("自动化蓝图") {
                    NotificationCenter.default.post(name: .openAutomation, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - 菜单通知

extension Notification.Name {
    static let openSettings = Notification.Name("matind.openSettings")
    static let openAutomation = Notification.Name("matind.openAutomation")
}
