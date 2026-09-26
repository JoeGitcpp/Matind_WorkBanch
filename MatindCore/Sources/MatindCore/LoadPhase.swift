import Foundation

/// 界面加载的五种状态。空和失败分开，不靠并列的布尔值表达。
public enum LoadPhase<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(ControlPlaneFailure)

    public static func resolve<Element: Equatable & Sendable>(_ values: [Element]) -> LoadPhase<[Element]> {
        values.isEmpty ? .empty : .loaded(values)
    }
}

public enum ControlPlaneFailure: Equatable, Error, Sendable {
    case unauthenticated
    case forbidden
    case missing
    case invalid(fields: [String: [String]])
    case conflict(precondition: String, currentRevision: String?)
    case pending(operationId: String)
    case unavailable(retryAfterSeconds: Int?)
    case unreachable
    case undecodable

    public var message: String {
        switch self {
        case .unauthenticated:
            return "登录已过期"
        case .forbidden:
            return "没有权限"
        case .missing:
            return "内容不存在"
        case .invalid:
            return "提交的内容不符合要求"
        case .conflict:
            return "内容已在别处被修改"
        case .pending:
            return "操作仍在处理"
        case .unavailable:
            return "服务暂时不可用"
        case .unreachable:
            return "无法连接服务器"
        case .undecodable:
            return "服务器返回了无法识别的内容"
        }
    }
}
