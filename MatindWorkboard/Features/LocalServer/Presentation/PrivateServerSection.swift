import SwiftUI
import MatindCore

/// 设置里的本机服务器。所有者可以启动、授权、收窄和解除。
struct PrivateServerSection: View {
    @Environment(AuthState.self) private var authState
    @Environment(LocalServerState.self) private var localServer
    @State private var workspaceText = ""
    @State private var draft: Set<LocalCapability> = [.browserObserve, .browserNavigate]
    @State private var browserConnectionText = ""
    @State private var browserOriginsText = ""
    @State private var browserAllowsWrite = false

    var body: some View {
        GroupBox("本机服务器") {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务启动后才能执行本机任务。退出工作台会停止服务；离线任务等待设备上线。设备属于当前用户，工作区授权与本机网站许可同时生效，已有工作区授权只能收窄或解除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .startRefused(.ownedBySomeoneElse) = localServer.notice {
                    Text(ServerNoticeCopy.text(localServer.notice) ?? "")
                        .foregroundStyle(.red)
                } else {
                    identityBlock
                    runtimeButton
                    controlPlaneButton
                    authorizationForm
                    authorizationList
                    browserAccessForm
                }

                if let message = ServerNoticeCopy.text(localServer.notice),
                   !isOwnerConflict {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(messageColor)
                }
                if let message = localServer.accessNotice {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var isOwnerConflict: Bool {
        if case .startRefused(.ownedBySomeoneElse) = localServer.notice { return true }
        return false
    }

    private var messageColor: Color {
        switch localServer.notice {
        case .startRefused, .authorization(.refused):
            return .red
        case .none, .started, .authorization:
            return .secondary
        }
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("设备") {
                Text(localServer.ledger?.server.deviceId.uuidString ?? "尚未建立")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("监听") {
                Text(runtimeText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runtimeText: String {
        switch localServer.runtime {
        case .stopped:
            "未启动"
        case .running(let port):
            "\(LoopbackBind.host):\(port)"
        }
    }

    private var runtimeButton: some View {
        Button(runtimeButtonTitle) {
            Task { await changeRuntime() }
        }
        .buttonStyle(.bordered)
        .disabled(localServer.isStarting)
    }

    private var runtimeButtonTitle: String {
        if localServer.isStarting { return "正在启动执行服务…" }
        switch localServer.runtime {
        case .stopped: return "启动本机服务"
        case .running: return "停止本机服务"
        }
    }

    private var authorizationForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("工作区编号", text: $workspaceText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            ForEach(LocalCapability.allCases, id: \.self) { capability in
                Toggle(capability.title, isOn: binding(for: capability))
            }
            Button("提交授权") {
                Task { await submitAuthorization() }
            }
            .buttonStyle(.bordered)
            .disabled(!localServer.controlPlaneConnected || localServer.isUpdatingAccess)
        }
    }

    private var authorizationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(localServer.ledger?.activeRecords() ?? []) { record in
                HStack {
                    Text("工作区 \(record.workspaceId) · 版本 \(record.version)")
                    Spacer()
                    Button("解除") {
                        Task { await release(record) }
                    }
                    .buttonStyle(.borderless)
                }
                Text(record.capabilities.map(\.title).sorted().joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlPlaneButton: some View {
        HStack {
            Text(localServer.controlPlaneConnected ? "控制面已连接" : "控制面未连接").font(.caption)
            Button("连接控制面") {
                Task {
                    guard let user = authState.currentUser, let token = authState.accessToken else { return }
                    await localServer.connectControlPlane(actorUserId: user.id, token: token)
                }
            }
            .disabled(localServer.runtime == .stopped || localServer.isUpdatingAccess)
        }
    }

    private var browserAccessForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("本机浏览器许可").font(.headline)
            Text(localServer.browserStatusText).font(.caption).foregroundStyle(.secondary)
            if localServer.browserPolicy != nil {
                Toggle("启用本机浏览器执行", isOn: Binding(
                    get: { localServer.browserPolicy?.enabled == true },
                    set: { enabled in
                        guard let user = authState.currentUser else { return }
                        localServer.setBrowserEnabled(actorUserId: user.id, enabled: enabled)
                    }
                ))
            }
            Text("在网页自动化设置中添加本地浏览器账号，选择上面的设备编号，再把账号连接编号填入这里。每个账号使用独立浏览器登录环境。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("账号连接编号", text: $browserConnectionText).textFieldStyle(.roundedBorder)
            TextField("允许的网站，例如 https://example.com，多个用逗号分隔", text: $browserOriginsText).textFieldStyle(.roundedBorder)
            Toggle("允许填写与点击（每次写入仍需操作授权）", isOn: $browserAllowsWrite)
            Button("保存网站许可") {
                guard let user = authState.currentUser,
                      let connectionId = UUID(uuidString: browserConnectionText.trimmingCharacters(in: .whitespaces)),
                      let workspaceId = Int64(workspaceText.trimmingCharacters(in: .whitespaces)) else { return }
                localServer.saveBrowserBinding(actorUserId: user.id, workspaceId: workspaceId, connectionId: connectionId,
                    origins: browserOriginsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, allowWrite: browserAllowsWrite)
            }
            .disabled(!localServer.controlPlaneConnected || UUID(uuidString: browserConnectionText.trimmingCharacters(in: .whitespaces)) == nil)
            ForEach(localServer.browserPolicy?.bindings ?? []) { binding in
                HStack {
                    VStack(alignment: .leading) {
                        Text("工作区 \(binding.workspaceId) · \(binding.connectionId.uuidString)").font(.caption).textSelection(.enabled)
                        Text(binding.allowedOrigins.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开账号浏览器") {
                        Task {
                            guard let user = authState.currentUser else { return }
                            await localServer.openAccountBrowser(actorUserId: user.id, binding: binding)
                        }
                    }
                    .disabled(localServer.runtime == .stopped || localServer.isOpeningBrowser)
                    Button("解除网站许可") {
                        guard let user = authState.currentUser else { return }
                        localServer.removeBrowserBinding(actorUserId: user.id, connectionId: binding.connectionId)
                    }
                }
            }
        }
    }

    private func binding(for capability: LocalCapability) -> Binding<Bool> {
        Binding(
            get: { draft.contains(capability) },
            set: { isOn in
                if isOn {
                    draft.insert(capability)
                } else {
                    draft.remove(capability)
                }
            }
        )
    }

    private func changeRuntime() async {
        switch localServer.runtime {
        case .running:
            localServer.stop()
        case .stopped:
            guard let user = authState.currentUser else { return }
            _ = await localServer.start(ownerUserId: user.id)
            if let token = authState.accessToken {
                await localServer.connectControlPlane(actorUserId: user.id, token: token)
            }
        }
    }

    private func submitAuthorization() async {
        guard let user = authState.currentUser, let token = authState.accessToken else { return }
        let workspaceId = Int64(workspaceText.trimmingCharacters(in: .whitespaces)) ?? 0
        await localServer.authorizeRemotely(
            actorUserId: user.id,
            workspaceId: workspaceId,
            capabilities: draft,
            token: token
        )
    }

    private func release(_ record: WorkspaceAuthorization) async {
        guard let user = authState.currentUser, let token = authState.accessToken else { return }
        await localServer.releaseRemotely(actorUserId: user.id, record: record, token: token)
    }
}

enum ServerNoticeCopy {
    static func text(_ notice: ServerNotice) -> String? {
        switch notice {
        case .none:
            return nil
        case .started(let port):
            return "本机服务已在 \(LoopbackBind.host):\(port) 监听"
        case .startRefused(let refusal):
            return startText(refusal)
        case .authorization(let decision):
            return authorizationText(decision)
        }
    }

    private static func startText(_ refusal: ServerStartRefusal) -> String {
        switch refusal {
        case .ownedBySomeoneElse:
            return "这台电脑上的服务器属于另一个用户，不能改挂到当前账号"
        case .identityUnreadable:
            return "设备身份不完整，没有改写或重新生成密钥"
        case .listenerFailed:
            return "本机端口没有打开"
        case .hostUnavailable(let error):
            switch error {
            case .executableUnavailable: return "未安装本地执行服务，请安装包含执行服务的工作台版本"
            case .identityMismatch, .invalidIdentity: return "执行服务的设备身份不一致，已停止启动"
            case .contractMismatch: return "执行服务版本不兼容，已停止启动"
            case .startupTimedOut: return "执行服务启动超时，已停止"
            case .processExited: return "本地执行服务已退出，本地任务将等待设备上线"
            case .startCancelled: return "启动已取消"
            case .launchFailed: return "执行服务无法启动，请检查安装与系统权限"
            }
        }
    }

    private static func authorizationText(_ decision: AuthorizationDecision) -> String {
        switch decision {
        case .created(let record):
            return "已授权给工作区 \(record.workspaceId)"
        case .narrowed:
            return "已收窄授权，版本已更新"
        case .unchanged:
            return "授权没有变化"
        case .released(let record):
            return "已解除工作区 \(record.workspaceId) 的授权"
        case .refused(let refusal):
            return refusalText(refusal)
        }
    }

    private static func refusalText(_ refusal: AuthorizationRefusal) -> String {
        switch refusal {
        case .notOwner:
            return "只有服务器所有者能改授权"
        case .invalidWorkspace:
            return "工作区编号无效"
        case .emptyCapabilities:
            return "至少保留一项能力"
        case .expansionForbidden:
            return "不能扩大已有授权"
        case .missing:
            return "先启动本机服务，或这条授权已经不存在"
        }
    }
}
