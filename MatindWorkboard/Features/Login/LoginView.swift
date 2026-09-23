import SwiftUI

/// 登录页：只提供浏览器授权入口，客户端不收集密码。
struct LoginView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            heading
            actions
                .frame(width: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var heading: some View {
        VStack(spacing: 12) {
            Image(systemName: "squares.leading.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Matind Workboard")
                .font(.system(size: 28, weight: .bold))
            Text("使用网页账户登录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(AppConfig.configName) · \(AppConfig.apiBaseURL)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 16) {
            switch authState.signIn {
            case .waiting:
                waiting
            case .idle, .failed:
                signInButton
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("没有账号？在网页注册") { authState.openRegistration() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    private var signInButton: some View {
        Button(action: authState.signInWithBrowser) {
            Label("在浏览器中登录", systemImage: "safari")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.borderedProminent)
        .disabled(AppConfig.webBase == nil)
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("请在浏览器中确认授权…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("取消", action: authState.cancelSignIn)
        }
    }

    private var failure: String? {
        if case .failed(let message) = authState.signIn { return message }
        if AppConfig.webBase == nil { return "构建配置缺少网页地址" }
        return authState.notice
    }
}
