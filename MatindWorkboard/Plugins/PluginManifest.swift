import Foundation

// plugin.toml 的 Swift 结构体（使用 JSON-compatible 格式，因为 macOS 没有内置 TOML 解析）
// 实际项目中用 JSON 格式的 plugin.json 替代 TOML，功能等价

struct PluginManifest: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let type: PluginType
    let category: String
    let description: String?
    let permissions: PluginPermissions
    let ui: PluginUI

    enum PluginType: String, Codable, Sendable {
        case webview
        case native
        case service
        case hybrid
    }
}

struct PluginPermissions: Codable, Sendable {
    let network: [String]?
    let notification: Bool?
    let filesystem: Bool?
}

struct PluginUI: Codable, Sendable {
    let entry: String          // 入口 HTML 文件名
    let icon: String?
    let minWidth: Int?
    let minHeight: Int?
    let defaultWidth: Int?
    let defaultHeight: Int?
    let resizable: Bool?

    enum CodingKeys: String, CodingKey {
        case entry, icon, resizable
        case minWidth = "min_width"
        case minHeight = "min_height"
        case defaultWidth = "default_width"
        case defaultHeight = "default_height"
    }
}
