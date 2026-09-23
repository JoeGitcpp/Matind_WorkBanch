import SwiftUI

/// 设置里的本机服务器。所有者可以启动、授权、收窄和解除。
struct PrivateServerSection: View {
    @Environment(AuthState.self) private var authState
    @Environment(LocalServerState.self) private var localServer
    @State private var workspaceText = ""
    @State private var draft: Set<LocalCapability> = [.blueprintRun, .healthRead]

    var body: some View {
        GroupBox("本机服务器") {
            VStack(alignment: .leading, spacing: 12) {
                Text("这台电脑上的服务器属于当前登录用户。它可以授权给工作区；已有授权只能收窄或解除，不能扩大，也不能改挂到别的账号。服务只监听 127.0.0.1。短时操作授权由网页签发，最长 15 分钟，并且必须落在已有授权里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .startRefused(.ownedBySomeoneElse) = localServer.notice {
                    Text(ServerNoticeCopy.text(localServer.notice) ?? "")
                        .foregroundStyle(.red)
                } else {
                    identityBlock
                    runtimeButton
                    authorizationForm
                    authorizationList
                }

                if let message = ServerNoticeCopy.text(localServer.notice),
                   !isOwnerConflict {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(messageColor)
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
    }

    private var runtimeButtonTitle: String {
        switch localServer.runtime {
        case .stopped: "启动本机服务"
        case .running: "停止本机服务"
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
                submitAuthorization()
            }
            .buttonStyle(.bordered)
            .disabled(localServer.ledger == nil)
        }
    }

    private var authorizationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(localServer.ledger?.activeRecords() ?? []) { record in
                HStack {
                    Text("工作区 \(record.workspaceId) · 版本 \(record.version)")
                    Spacer()
                    Button("解除") {
                        release(record)
                    }
                    .buttonStyle(.borderless)
                }
                Text(record.capabilities.map(\.title).sorted().joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
    }

    private func submitAuthorization() {
        guard let user = authState.currentUser else { return }
        let workspaceId = Int64(workspaceText.trimmingCharacters(in: .whitespaces)) ?? 0
        _ = localServer.propose(
            actorUserId: user.id,
            workspaceId: workspaceId,
            capabilities: draft
        )
    }

    private func release(_ record: WorkspaceAuthorization) {
        guard let user = authState.currentUser else { return }
        _ = localServer.release(actorUserId: user.id, authorizationId: record.id)
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
