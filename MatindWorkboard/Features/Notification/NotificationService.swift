import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        // 监听插件发送的通知请求（Notification.Name.pluginRequestedNotification 在 WebViewPluginHost.swift 中定义）
        NotificationCenter.default.addObserver(
            forName: .pluginRequestedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let title = note.userInfo?["title"] as? String,
                  let body = note.userInfo?["body"] as? String else { return }
            Task { await self.sendSystemNotification(title: title, body: body, identifier: UUID().uuidString) }
        }
    }

    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[NotificationService] Permission request failed: \(error)")
            return false
        }
    }

    /// 发送系统通知
    func sendSystemNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // 立即触发
        )

        do {
            try await center.add(request)
        } catch {
            print("[NotificationService] Failed to send notification: \(error)")
        }
    }

    /// 前台收到通知时在应用内显示 banner（而不是系统 alert）
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound]
    }
}
