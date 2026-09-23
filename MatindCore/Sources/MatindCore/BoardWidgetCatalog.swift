import Foundation

/// 桌面端能放上工作板的组件。种类名与网页端注册表一致。
public enum BoardWidgetKind: String, CaseIterable, Sendable {
    case hyperTable = "HyperTable"

    public var title: String {
        switch self {
        case .hyperTable:
            return "多维表"
        }
    }

    public var summary: String {
        switch self {
        case .hyperTable:
            return "和网页同一张表，可建表、改字段、改单元格"
        }
    }

    public var placement: BoardWidgetPlacement {
        switch self {
        case .hyperTable:
            return BoardWidgetPlacement(width: 12, height: 6)
        }
    }
}

public struct BoardWidgetPlacement: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// 多维表嵌入页地址。页面本身在网页端，桌面端只负责打开它。
public enum HyperTableLocation {
    public static func page(webBase: URL, datasetId: String) -> URL? {
        guard var components = URLComponents(url: webBase, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let prefix = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = prefix + "/zh/embed/hyper-table"
        if !datasetId.isEmpty {
            components.queryItems = [URLQueryItem(name: "datasetId", value: datasetId)]
        }
        return components.url
    }
}
