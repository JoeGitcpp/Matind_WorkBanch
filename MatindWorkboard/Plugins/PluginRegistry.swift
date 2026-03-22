import Foundation

@MainActor
final class PluginRegistry: ObservableObject {
    static let shared = PluginRegistry()

    @Published private(set) var plugins: [PluginManifest] = []

    private init() {}

    /// 从 Bundle Resources/Plugins/ 加载所有内置插件
    func loadBuiltinPlugins() {
        guard let pluginsURL = Bundle.main.url(forResource: "Plugins", withExtension: nil) else {
            print("[PluginRegistry] Plugins directory not found in bundle")
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil
            )
            plugins = contents.compactMap { dir in
                let manifestURL = dir.appendingPathComponent("plugin.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
                    print("[PluginRegistry] Failed to load manifest at \(dir.path)")
                    return nil
                }
                return manifest
            }
            print("[PluginRegistry] Loaded \(plugins.count) builtin plugins")
        } catch {
            print("[PluginRegistry] Error loading plugins: \(error)")
        }
    }

    /// 按 ID 查找插件
    func plugin(id: String) -> PluginManifest? {
        plugins.first { $0.id == id }
    }
}
