# Matind Workbench

**矩阵工业工作台** — macOS 原生桌面客户端，基于 SwiftUI 构建。

工作台是矩阵工业（MatrixIndustry）数字化基础设施的桌面操作界面，提供可定制的小组件面板、多工作板管理、插件系统和自动化蓝图能力。

## 功能

- **工作台管理** — 多工作台切换，每个工作台包含多个工作板
- **标签页系统** — 统一标签栏，支持工作板 / 设置 / 自动化蓝图等标签类型
- **12 列网格布局** — 响应式小组件网格，支持拖拽定位和调整大小
- **插件系统** — 基于 WKWebView 的 Web 插件架构，支持 JS Bridge 通信
- **通知中心** — 系统级通知推送和应用内通知中心
- **身份认证** — Token 安全存储于 macOS Keychain，支持自动登录

## 技术栈

| 技术 | 用途 |
|------|------|
| **SwiftUI** | UI 框架 |
| **Observation** | 状态管理（`@Observable`） |
| **WKWebView** | 插件宿主 |
| **Keychain Services** | Token 安全存储 |
| **UserNotifications** | 系统通知 |

**最低要求：** macOS 14.0 (Sonoma) · Xcode 16.0 · Swift 6.0

## 项目结构

```
MatindWorkboard/
├── MatindWorkboardApp.swift       # 应用入口 + 系统菜单
├── ContentView.swift              # 主布局（标签栏 + 内容路由）
│
├── Core/
│   ├── Auth/                      # 认证（Keychain + Token）
│   ├── Config/                    # 配置常量
│   ├── Models/                    # 基础模型（User, LastVisited）
│   ├── Network/                   # HTTP 客户端
│   ├── Storage/                   # 本地持久化
│   └── Tab/                       # 标签页系统
│       ├── AppTab.swift           # 标签类型枚举
│       ├── TabManager.swift       # 标签管理器
│       └── AppTabBar.swift        # 标签栏 UI
│
├── Features/
│   ├── Automation/                # 自动化蓝图（占位）
│   ├── Board/                     # 工作板（CRUD + 网格布局）
│   ├── Login/                     # 登录表单
│   ├── Notification/              # 通知中心
│   ├── Settings/                  # 设置页面
│   └── Workbench/                 # 工作台（数据 + 选择器）
│
├── Plugins/                       # 插件系统
│   ├── PluginRegistry.swift       # 插件注册表
│   ├── PluginManifest.swift       # 插件清单模型
│   └── WebViewPluginHost.swift    # WebView 宿主 + JS Bridge
│
└── Resources/Plugins/             # 内置插件
    ├── com.matind.chart/
    ├── com.matind.kanban/
    └── com.matind.showcase-card/
```

## 架构

采用 **Clean Architecture** 分层：

```
Domain (模型)  →  Data (仓库)  →  Presentation (ViewModel + View)
```

- **ViewModel** 使用 `@Observable` 宏，轻量响应式
- **Repository** 协议抽象数据源，便于测试和替换
- **插件** 通过 `MatindBridge` JS 对象与宿主通信

## 快速开始

```bash
# 克隆
git clone git@github.com:JoeGitcpp/Matind_WorkBanch.git
cd Matind_WorkBanch

# 用 Xcode 打开
open MatindWorkboard.xcodeproj

# 或命令行构建
xcodebuild -scheme MatindWorkboard -destination "platform=macOS" build
```

**开发模式：** 默认连接 `http://localhost:8800`（后端服务）。

## 键盘快捷键

| 快捷键 | 操作 |
|--------|------|
| `⌘,` | 打开设置 |
| `⇧⌘B` | 打开自动化蓝图 |

##www.matind.com

## 许可证

[Apache License 2.0](LICENSE)

Copyright 2026 MatrixIndustry
