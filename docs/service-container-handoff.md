# 服务容器：交接说明（交给 Mac 侧继续）

日期：2026-10-16
状态：第 1 至 12 步已在 Windows 上做完并提交；本文说明做到哪里、下一步做什么、还缺什么。
读法：先读第 1、2 节弄清分支和合并顺序，再按第 6 节的清单在 Mac 上验证；第 7 节是后续要做的事。
设计依据与实施要求见同目录的 `service-container-architecture.md`、`service-container-implementation.md`。

---

## 1. 一句话状态

服务容器的后端（目录、权限、蓝图批准、等价组、队列、计量扣点、数据通道）、宿主（清单、驱动、任务循环、字节流）、网页端（服务管理页、表单生成、试用、上传下载）和第一个官方服务（网络盘）都已写完并通过各自的自动化测试。**还没有做过的事**：Mac 上的任何构建与测试、Swift 客户端的一切、宿主与真实后端的联调、网页在真实浏览器里的检查、其余三个官方服务。

## 2. 分支地图与合并顺序

三个仓库的分支都已推送到 `origin`，都还没有合并到 `dev`。

### 2.1 后端 `MatindBackend_Rust`（已变基到 2026-10-16 的 `origin/dev` 455b062d）

| 分支 | 提交 | 内容 | 包含 |
|------|------|------|------|
| `feat/service-contracts` | `23e08660` | 共享契约校验器和一致性样例（第 1 步） | |
| `feat/data-channel` | `31e9f0ae` | 数据通道：句柄、范围中继、签名上传、限速、传输账本（第 8 步） | contracts |
| `feat/service-catalog` | `a0dadc8b` | 目录、判定链、蓝图批准、等价组、队列、管理页读接口、`service.call` 节点、计量与扣点、服务任务数据通道、调用者上传（第 9、10、11、12 步） | contracts、data-channel |
| `feat/device-login` | `9a25891c` | 设备码和令牌登记，无桌面服务器登录（第 4 步） | 独立，不含上面三个 |

合并顺序：`feat/service-catalog`（带上前两个）→ `feat/device-login`。两条线从未在同一棵树上一起编译过，合并后先跑一遍编译和各自的测试。

### 2.2 前端 `MatrixFactoryFrontend`（基于 `origin/dev`，落后 0）

| 分支 | 提交 | 内容 |
|------|------|------|
| `feat/service-contracts` | `f6f80f3a3` | TypeScript 契约校验器（第 1 步）。独立一条，网页和宿主目前都没有用它 |
| `feat/host-windows-kernel` | `57a1a97ab` | 宿主 Windows 层、通用内核、无桌面登记、CI 与打包、清单与驱动与 MCP、模型资源、数据面、服务平面（第 2 至 9 步的宿主部分）和设备码确认页 |
| `feat/service-management-page` | `298744e1e` | 含上一条；网页服务管理页、表单生成、`action.service` 蓝图节点、价格与点数（第 10、11 步） |
| `feat/service-streams` | `c0e4cf09f` | 含上一条；调用者上下文、字节流暂存与发布、文件字段与上传、网络盘服务、官方服务打包脚本（第 12 步） |

后三条是一条链，合并时合 `feat/service-streams` 即可。

### 2.3 桌面端 `WorkBoardDesktop`

| 分支 | 提交 | 内容 |
|------|------|------|
| `feat/service-contracts` | `db9be7e` | Swift 契约校验器和样例（第 1 步），**从未编译或运行过** |
| `docs/service-container` | 本分支 | 架构文档、实施要求、本交接说明 |

### 2.4 合并前必须做的一件事：重新钉住后端版本

前端 CI 从 `apps/desktop/source-lock.json` 读后端的确切提交，克隆到 `apps/desktop/.backend-source` 来编译宿主。宿主现在依赖后端的 `matrix_automation::service_contract`，而原来锁定的提交 `f20e33cc…` **没有这个模块**，所以前端分支在 CI 里不改锁就编不过。

- 已把前端 `feat/service-streams` 的锁改到后端 `feat/service-catalog` 的提交（见 2.5 的实际值）。
- 后端分支合并进 `dev` 之后，如果提交号变了（合并提交、压缩合并），要把锁再改成合并后的 `dev` 提交，并重跑两个平台的宿主测试。

### 2.5 已推送的实际提交

见本文末尾「附：推送记录」。

## 3. 各步完成情况

| 步 | 内容 | 状态 | 主要位置 | 怎么验证过 |
|----|------|------|----------|------------|
| 1 | 共享契约 | 完成 | 后端 `crates/matrix-automation/src/service_contract.rs` 与 `contracts/service-v1/`；TS、Swift 镜像 | Rust、TS 测试通过；**Swift 未运行** |
| 2 | 宿主 Windows 等价实现 | 完成 | `apps/desktop/local-server/src/kernel/platform/windows.rs` | Windows 全部测试 |
| 3 | 通用内核 | 完成 | `kernel/{identity,transport,operation_store,...}` | 同上，Linux 容器也通过 |
| 4 | 无桌面登记 | 完成 | 宿主 `cli.rs`、`enroll.rs`；后端 `device_control/enrollment.rs`；网页 `local-servers/enroll` | 单测；`install-service` 只做了 Linux |
| 5 | CI 与打包 | 完成 | `.github/workflows/*`、`scripts/desktop/package-{windows,linux}.sh` | Windows、Linux；**macOS 打包脚本未随之更新和运行** |
| 6 | 清单、驱动、MCP、模型服务迁移 | 完成 | `kernel/{manifest,driver,mcp,registry}.rs`、`builtin.rs` | 宿主测试，含签名进程包 |
| 7 | 模型资源 | 完成 | `src/models/*` | 宿主测试 |
| 8 | 数据通道 | 完成 | 后端 `modules/data_channel`；宿主 `data_plane.rs`；网页 `data-handle-service.ts` | 后端 7 个集成测试；宿主和网页单测 |
| 9 | 目录、权限、蓝图批准、等价组、队列 | 完成 | 后端 `modules/service_catalog/*`；宿主 `service_plane.rs` | 后端集成测试；宿主桩控制面端到端 |
| 10 | 服务管理页 | 完成（网页） | 网页 `.../settingInfo/workspace/_components/services/*`、`components/services/*` | 单测和类型检查；**未在真实浏览器里看过** |
| 11 | 计量与扣除 | 完成 | 后端 `service_catalog/metering.rs`、迁移 `20261015000003`；网页价格与用量 | 后端 8 个集成测试 |
| 12 | 网络盘（第一个官方服务） | 完成 | 宿主 `src/bin/network_disk.rs`、`streams.rs`；`scripts/desktop/package-official-service.mjs` | 宿主端到端：签名清单、签名包、进程驱动、上传输入、读出句柄 |

最近一次完整验证的数字（Linux 容器，后端用 PostgreSQL）：后端 `service_catalog` 15 个、`data_channel` 7 个、`service_metering` 8 个测试通过；宿主 118 个加网络盘自带 9 个通过；网页服务相关 42 个（第 12 步新增部分）和此前 94 个文件 660 个测试通过。变基到最新 `dev` 之后的复验结果见「附：推送记录」。

## 4. 验收对照（实施要求 5.3 与第 6 章）

| 验收项 | 状态 |
|--------|------|
| 5.3-1 只有清单的第三方服务，不改代码就出现在目录、权限组对话框、蓝图节点面板、试用面板 | 目录、权限组对话框、试用面板已做到。蓝图节点面板只有一个通用的「调用服务」节点（服务和操作靠填写，不是下拉）。**未在真实环境里走过** |
| 5.3-2 没有能力的成员看得到服务，调用被拒并写明原因 | 通过（后端集成测试和网页单测） |
| 5.3-3 以蓝图身份：批准后无权成员可用；改任一固定参数后被拒 | 后端通过。**网页画布放不出以蓝图身份运行的节点**，只能批准已存在的 |
| 5.3-4 等价组一台下线，新任务落到另一台；已下发的失败；重排改挑在线成员 | 后端通过 |
| 5.3-5 并发不超限，排队中的任务可取消 | 后端通过 |
| 第 6 章-1 同一回执重发三次只扣一次、只记一次收益 | 通过 |
| 第 6 章-2 无人在场的定时蓝图从负责人扣费，额度不足被拒且通知负责人 | 通过（站内通知，没有邮件或推送） |
| 第 6 章-3 失败后冻结的点数全部释放 | 通过 |
| 第 6 章-4 所有者收益可以抵扣订阅，界面上没有提现入口 | **只做了一半**：没有提现入口；点数可用于 AI 用量和服务调用；**没有用点数抵扣订阅的接口** |
| 第 4 章数据通道 4 条验收 | 通过（后端集成测试和宿主测试）；2 GB 断网续传没有真机跑过 |

## 5. 第 12 步引入的通用约定（后续服务和 Swift 客户端都要遵守）

这些是为让网络盘能用而补进容器的，已在宿主、后端、网页实现，**没有改 `service-operation-v1` 契约**，所以三个仓库的契约副本不用同步。

1. **调用者上下文**：后端投递任务时带 `context`：`callerId`、`workspaceId`、`identity`（`executor` 或 `blueprint`）、`blueprintId`、`serverOwnerId`（均为字符串）。宿主放进 MCP `tools/call` 的 `_meta["matind.dev/context"]`。服务用它判断谁在调用；没有上下文就当作没有调用者。
2. **字节流**：服务从不碰数据通道。
   - 输入：宿主把 `data-handle-v1` 取成暂存文件，替换成 `{"$file": 路径, "sizeBytes", "sha256", "mediaType"?}`。
   - 输出：服务返回 `{"$file": 路径, "mediaType"?}`，宿主发布成句柄并替换。
   - 只认顶层字段和顶层列表项，每次最多 16 个。输出文件只能来自任务暂存区或 `service-data/<serviceId>/`，其他路径一律拒绝（`stream_path_refused`）。
   - 服务自己的文件不会被拿走，宿主在暂存区建硬链接（跨卷则复制）再发布。
3. **清单里声明哪些操作带流**：`streams.consumes` 和 `streams.produces`。输入表单里要上传文件的字段，在 JSON Schema 里写 `"x-matind-data-handle": true`，网页据此生成文件选择器。
4. **服务数据目录**：进程服务通过环境变量 `MATIND_SERVICE_DATA` 得到自己的目录（`<数据目录>/service-data/<serviceId>/`）。
5. **数据通道对服务任务**：
   - 服务器登记输出流用 `taskId`（旧的操作用 `operationId`，二选一）。
   - 读者需要调用该操作所需的权限，或是发起人。
   - 输入流在排队时用调用者的权限检查，服务器只能取任务输入里点名的流。
   - 任务结果只能点名它自己产生的流。
6. **调用者上传**：`POST /api/v1/workspaces/:ws/data-handles`（声明大小和 SHA-256）→ 把字节传到返回的地址 → `POST .../:handle/complete`。得到的句柄只有上传者能读。
7. **计量**：一次成功调用算 1 个单位，失败、取消、结果未知算 0。点数用现有的个人点数账户：下单时冻结，成功后结算，失败退回；所有者赚到的点数成为自己账户里的一份「service_earning」点数，不提现。价格由服务器所有者按操作设置，缺省免费，上限 10000 点一次。
8. **官方清单**：官方服务的清单必须在后端 `official_service_v1` 里登记（服务号加清单哈希）才会被目录接受；未登记的官方清单被跳过并在上报回执里列出，不影响同一台服务器上其他服务的心跳。

### 5.1 接口速查（后端）

宿主侧（设备签名）：
`POST /api/v1/local-servers/services/{catalog,tasks/claim,tasks/start,tasks/result}`；
`POST /api/v1/local-servers/data/{handles,handles/complete,handles/download,relay/claim,relay/chunk,relay/fail}`。

人侧（登录用户）：
`GET /api/v1/workspaces/:ws/services/{catalog,group-capabilities,blueprint-nodes,usage,notices,tasks,equivalence-groups}`；
`PUT .../services/groups/:group/service-capabilities`；
`POST .../services/{tasks,blueprint-approvals,notices,equivalence-groups}` 与各自的 `:id/{cancel,reorder,requeue,revoke}`；
`PUT /api/v1/local-servers/devices/:device/services/:service/concurrency`；
`PUT /api/v1/local-servers/devices/:device/services/:service/operations/:operation/price`；
`POST /api/v1/workspaces/:ws/data-handles`、`.../:handle/complete`；
`GET /api/v1/data-handles/:handle`、`.../content`（带 Range）。

## 6. 在 Mac 上要验证的事（按顺序）

### 6.1 先拿到代码

```bash
git clone <后端> && git fetch origin feat/service-catalog feat/device-login
git clone <前端> && git fetch origin feat/service-streams feat/service-contracts
git clone <桌面端> && git fetch origin feat/service-contracts docs/service-container
```

### 6.2 Swift 契约镜像（从未运行过，最先做）

```bash
cd WorkBoardDesktop   # 切到 feat/service-contracts
cd MatindCore && swift test
```

预期：样例目录 `Tests/MatindCoreTests/Resources/service-v1` 的有效样例全部通过、无效样例全部被拒，`SHA256SUMS` 校验通过。Swift 6.0 工具链、macOS 14。失败时以 Rust 实现 `service_contract.rs` 为准修 Swift。

### 6.3 宿主在 macOS 上编译和测试

```bash
# 在前端仓库切到 feat/service-streams
python3 scripts/desktop/bootstrap.py          # 按 source-lock.json 克隆后端到 apps/desktop/.backend-source，需要仓库凭据
cargo +1.93.1 test --manifest-path apps/desktop/local-server/Cargo.toml --features fixtures
node --test scripts/desktop/package-official-service.test.mjs scripts/desktop/sign-browser-module.test.mjs
```

预期：宿主 118 个测试和 `matind-network-disk` 的 9 个测试通过；Node 测试通过（Windows 上被跳过或因路径失败，Linux 容器里没有 node 没跑，这是第一次真正运行）。重点看：
- `kernel::service_tests::network_disk`：签名的官方包在 macOS 上能启动、能创建数据目录、文件移动和硬链接工作。
- `streams` 里的链接测试（Unix 才跑）。
- macOS 的受保护数据目录权限（0700）和 `child_environment`。

### 6.4 把网络盘装进 macOS 打包

现在 `scripts/desktop/package-macos.sh` 只打包宿主，**没有**把网络盘二进制放进去，也没有签名它。要做：
1. 编译 `matind-network-disk`。
2. 用 `scripts/desktop/package-official-service.mjs BINARY OUT_DIR KEY PUBLIC_ROOT` 生成签名包和签名清单，放到应用包里宿主能找到的 `services/netdisk/`。
3. 处理 macOS 代码签名和公证：平台签名清单里的文件哈希是对二进制本身算的，Apple 签名会改变二进制，要么先 Apple 签名再算哈希，要么把清单签名放在最后一步。需要在 Mac 上试一遍确定顺序。
4. 同样的打包对 Windows、Linux 脚本也还没接上（脚本能单独运行，但没有被 `package-*.sh` 调用）。

### 6.5 宿主和真实后端联调（还没有任何人做过）

1. 起后端（PostgreSQL、迁移全部应用）；把官方清单登记进 `official_service_v1`（`package-official-service.mjs` 会打印那条 SQL）。
2. 用 `matind-local-service login --control-plane <url> --token-file <文件>` 把宿主登记到一个账号。
3. 在网页「设置 → 服务」里把这台服务器授权给一个工作区，开放网络盘的操作，给权限组勾选。
4. 用试用面板：创建共享盘、写一个文件（上传）、读它（保存到本地）；再建私人盘，用另一个成员验证看不见。
5. 蓝图：在蓝图编辑器放一个「调用服务」节点跑一次；批准页确认状态。

### 6.6 网页在真实浏览器里过一遍

「设置 → 服务」的七个页签；权限组对话框里的服务权限；蓝图自动化里的「服务与权限」入口（是普通链接，没验证 `/home` 会补语言前缀）；试用面板的文件上传和结果保存（File System Access 只在 Chromium 内核里有，Safari 走内存下载，上限 256 MB）。

## 7. 下一步要做的事

### 7.1 先补的功能缺口（不补，上面的东西在真实环境里会不完整）

1. **桌面 App 启动的宿主还没有接入服务平面。** 服务平面线程只在宿主有 `enrollment.json`（无桌面登记，即 `login` 命令）时启动（`service.rs` 里 `crate::enroll::load(root)`）。由 Tauri 或 Swift 启动的宿主没有这个文件，所以不会上报目录、不会取任务。要让 App 内的宿主也能当服务器，需要定下控制面地址和身份怎么传（Swift 启动契约用 stdin 传身份，控制面地址可以放新的环境变量或策略文件，只能新增，不能改旧契约），再让 `service_plane` 和 `data_plane` 在这种模式下启动。
2. **定时清理没有挂上。** 后端的 `tasks::sweep`（把下线服务器手里的任务判失败、把排队中的任务移到在线成员）和 `metering::reconcile` 只在任务状态变化时顺带跑，没有周期任务。要在后端启动时起一个每 30 秒一次的循环，否则服务器掉线后，已下发的任务要等别的事件才会被判失败。
3. **蓝图里以蓝图身份调用服务。** 服务端引擎里有 `service.call` 节点（`matrix-automation::service_node`，在 worker 里注册），但网页画布只能放浏览器端执行的 `action.service`（只支持执行者身份）。要让用户能画出服务端运行的节点，需要先弄清网页的蓝图词表（board、agent 两套）和 `matrix-automation` 的图格式怎么对应，现在没有对应关系。
4. **节点的服务和操作是手填的文字**，应该改成从目录里选，并按所选操作的输入结构生成参数表单（表单生成组件已有，没接到节点检查器）。
5. **点数抵扣订阅费**没有接口：订阅是走支付订单的，没有用点数付款的路径。
6. **计量单位**现在固定一次成功调用算 1 个单位。按结果大小、令牌数等算，需要控制面自己得出数值（宿主自报的不能当依据），做第二个官方服务时再定。
7. **官方清单发布**是手工执行打印出来的 SQL，没有自动化。

### 7.2 剩下的官方服务（每个一个会话，按依赖）

| 服务 | 卡点 | 建议 |
|------|------|------|
| 本地大模型 | **流式输出**：任务结果现在只在结束时一次返回。内置的 `com.matind.local-model` 的 `infer` 已经迁到容器上 | 先定流式怎么走。可选做法：用进度通知带增量文字，控制面存到任务上由网页轮询；或输出一个持续增长的流句柄。要改共享契约就先回报 |
| LAYA | 实施前核实 LAYA 的推理方式；权重走模型资源流程（第 7 步已做） | 看是进程还是外接服务，再定驱动 |
| ComfyUI | 适配程序处理提交、轮询、取图；产物落到工作区存储（`produces: workspace_storage`，已支持） | 用外接驱动或进程适配程序 |

做每一个时都要遵守实施要求第 7 章：如果必须改通用代码，先回报缺口再改。

### 7.3 桌面端 Swift 要做的

1. 跑通 6.2。
2. 桌面端的服务管理（架构文档第 8 章说网页端和桌面端都有）完全没开始。至少要有：宿主上报的服务和状态展示、所有者对本机服务的并发调整和定价、私人盘创建时的物理接触提示。可以先做成指向网页端的入口。
3. Swift 启动契约保持不变，`/health` 里新增了 `services` 字段（只增不改）。

### 7.4 已知的小问题

- 网络盘的盘只能放在宿主数据目录下，不能指到别的磁盘。
- 网络盘的已用量每次操作都重新数文件，文件很多时会慢。
- `x-matind-data-handle` 以外的输入类型（如颜色、日期）表单生成只当文本，复杂结构退化成 JSON 文本框。

## 8. 环境和坑

- 后端集成测试需要 PostgreSQL：`TEST_DATABASE_URL`（有建库权限的管理连接，如 `postgresql://postgres:postgres@127.0.0.1:5432/matrix_test`）和 `TEST_DATABASE_ADMIN_URL`；部分测试要名为 `supabase_admin` 的角色。每个测试自己建临时库。
- 后端这几个测试文件的迁移列表是手写的，改迁移要同步：`tests/service_catalog.rs`、`tests/service_metering.rs`、`tests/data_channel.rs`。`service_catalog.rs` 里用桩表代替了点数钱包，真实钱包在 `service_metering.rs` 里。
- 已知的基线失败（在没有我的改动的 `dev` 上也失败）：后端 `local_server_device_control::signed_commands_are_lease_checked_and_reconnect_audit_is_idempotent`；网页 `HomeDockBoard`、`FileManagerView`、`homeOwnershipBoundary` 共 10 个测试（`AuthGateProvider` 缺失等，与本工作无关）；Windows 上 `sign-browser-module.test.mjs` 的路径用法。
- 前端提交有 husky 钩子：网页文件必须过 prettier 和 eslint 的错误级检查。
- 迁移版本号：`20261015000003_service_metering_v1.sql` 和 `dev` 上的 `20261015000001_ai_worker_turn_access_fingerprint_v1.sql` 版本前缀不同，账本按文件名去重，没有冲突。
- 本机的 `uat` 工作区里用户有未提交的改动（`EngineTagManager.tsx` 等），推送是从独立的工作树做的，没有碰它们。
- Windows 工作树里行尾会被转成 CRLF；拷到 Linux 前要去掉 `\r`。

## 9. 约定

- 提交只在本地和这些分支上，不直接动 `dev`、`uat`、`main`。
- 每个会话结束时回报：改了哪些文件、验收项逐条结果、与文档不一致的地方（实施要求 8 节的规定）。
- 出现「必须改通用代码」的情况，先回报缺口。

---

## 附：推送记录（2026-10-16）

后端 `JoeGitcpp/MatindBackend_Rust`：`feat/service-contracts` 23e08660、`feat/device-login` 9a25891c、`feat/data-channel` 31e9f0ae、`feat/service-catalog` a0dadc8b。
变基到 dev 455b062d 后在 Linux 容器复验：service_catalog 15、data_channel 7、service_metering 8、matrix-automation 全部、automation_job_lifecycle_test 14、local_server_enrollment 2，全部通过。

前端 `JoeGitcpp/MatrixFactoryFrontend`：`feat/service-contracts` f6f80f3a3、`feat/host-windows-kernel` 57a1a97ab、`feat/service-management-page` 298744e1e、`feat/service-streams` 991c5f37c（比 c0e4cf09f 多一个提交：`source-lock.json` 已钉到后端 a0dadc8b）。
`scripts/tests/desktop-boundary-test.py` 在本机（无 Python）没有运行，Mac 上先跑一次。

桌面端 `JoeGitcpp/Matind_WorkBanch`：`feat/service-contracts` db9be7e、`docs/service-container`（本文所在分支）。
