import SwiftUI

struct LoginView: View {
    @Environment(AuthState.self) private var authState

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo + 标题
            VStack(spacing: 12) {
                Image(systemName: "squares.leading.rectangle")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                Text("Matind Workboard")
                    .font(.system(size: 28, weight: .bold))
                Text("MatrixIndustry 工作板")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            // 登录表单
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("邮箱")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("you@example.com", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("密码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit { Task { await handleLogin() } }
                }

                if let errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 4)
                }

                Button(action: { Task { await handleLogin() } }) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
            }
            .frame(width: 320)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func handleLogin() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authState.loginWithCredentials(email: email, password: password)
        } catch let apiError as APIError {
            errorMessage = apiError.localizedDescription
        } catch {
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }
}
