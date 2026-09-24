import SwiftUI

/// 设置页面
/// 作为标签页打开，包含应用设置项
struct SettingsView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 标题
                Text("设置")
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                // 账户信息
                GroupBox("账户") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let user = authState.currentUser {
                            LabeledContent("邮箱", value: user.email ?? "未设置")
                            LabeledContent("用户名", value: user.displayName)
                        }

                        Button(role: .destructive) {
                            authState.logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("本机服务") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("服务的安装、启停和授权在本机服务页。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("打开本机服务") {
                            NotificationCenter.default.post(name: .openLocalServices, object: nil)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                }

                // 通用设置
                GroupBox("通用") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("配置", value: AppConfig.configName)
                        LabeledContent("服务器地址") {
                            Text(AppConfig.apiBaseURL)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("网页地址") {
                            Text(AppConfig.webBaseURL)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        LabeledContent("版本") {
                            Text(AppConfig.appVersion)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // 快捷操作
                GroupBox("快捷操作") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("从此处可以快速打开其他功能页面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Spacer()
            }
            .padding(24)
        }
    }
}
