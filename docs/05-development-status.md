# 开发状态与变更记录

本文是工程开发过程的状态入口。每次开始或完成一个阶段、发现验收差异、调整设计方案或改变范围时，必须先更新本文或关联设计文档，再提交代码。

## 当前状态

- 当前阶段：云端协调架构 Tasks 1-15、Android/Web 客户端边界 Tasks 1-8 及 Android 任务导航与刷新交互已实现；四象限 2×2 展示施工和 `v0.2.0` APK 发布完成。任务参与人模型移除和单分类模型已完成本地代码、迁移、客户端和测试收口。线上 API 已升级至 `0013_remove_default_class`，不再生成系统“默认”分类。下一阶段先按 R0-R4 产品路线补齐单人起步、双人验收、同步可靠性和任务可发现性，不开始提醒或重复任务扩展。
- 当前产品和运行时设计：[产品需求](./01-product.md)、[产品路线与单人起步、双人验收设计](./superpowers/specs/2026-09-10-product-roadmap-and-bootstrap-completion-design.md)、[移除任务参与人模型设计](./superpowers/specs/2026-09-01-remove-task-participants-design.md)、[我的页审批、设备管理与用户资料设计](./superpowers/specs/2026-09-02-my-tab-approval-device-profile-design.md)、[云端协调架构规格](./superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md)、[开发路线](./03-roadmap.md)、[已确认决策](./04-decisions.md)。
- 当前范围：只交付 Android 与 Web；Android 需要 APK/AAB，Web 由 TypeScript + Vite 构建静态文件；iOS 留作未来协议兼容，不进入本轮构建、发布或验收。
- 当前数据与同步边界：PostgreSQL 是明文事实源；REST cursor 同步为正确性路径，WebSocket 仅为通知；不允许离线提交；首版不引入 Elasticsearch/OpenSearch。
- 当前任务契约：每项任务只保留一个 `current_handler_id`；同一 Workspace 的两位 ACTIVE 成员可读取全部未删除父任务和子任务；当前负责人可直接写入，非当前负责人的成员写入受保护字段时继续提交给对方审批；“我的任务”只按当前负责人筛选。
- 当前分类契约：单人 Workspace 自动提供唯一的个人起步分类，允许第一位用户立即创建任务；第二位 ACTIVE 成员加入后，起步分类转为只读迁移分类。双人阶段新任务必须显式选择已批准共享分类，首个共享分类由一方发起 `CLASSIFICATION_CREATE` 并经另一位成员批准。
- 当前完成契约：任务完成始终需要另一位成员验收。负责人一次提交验收会在同一事务内将任务改为 `REVIEW` 并自动创建唯一验收审批；批准后进入 `DONE`，驳回并填写原因后回到 `IN_PROGRESS`。单人阶段不能直接完成，也不创建没有审批人的验收请求。
- 当前 Android 账户概览：从现有 Workspace snapshot 统计当前用户负责的全部未删除父任务和子任务，并显示任务、完成和延期汇总；匹配对象头像打开另一位 ACTIVE 成员的同口径概览。
- 当前 Android 入口与资料边界：任务审批和 Web 扫码只从“我的”页 AppBar 进入；短信验证成功的每台 Android 设备直接为 `ACTIVE` 且可写；设备管理只能在二次确认后撤销同一账号的其他设备，当前设备不可撤销；个人资料只编辑 `display_name`，头像继续使用默认 `CircleAvatar`。
- 当前 Workspace bootstrap 契约：只返回 ACTIVE 成员的 `match_status`、成员数量、名称、脱敏手机号和 `is_current`；零或一名成员为 `waiting_partner`，两名成员为 `matched`，未匹配时客户端只显示默认占位头像和“匹配中”，不伪造对方身份。
- 当前迁移与缓存：Alembic `0005_remove_task_assignees` 校验非删除任务的 `current_handler_id` 必须是同一 Workspace 的 ACTIVE 成员，`0006_trust_sms_devices` 将未撤销的遗留 `PENDING` 设备转为 `ACTIVE` 并使旧设备授权请求过期；开发迁移会有意删除旧 `task_assignees` 参与人数据和所有已废弃的 `ASSIGNEE_UPDATE` 记录。Flutter 快照缓存命名空间为 `muyu.workspace.snapshot.v2.$workspaceId`，旧命名空间不会作为当前契约读取。
- 历史基线：首轮工程、Phase 2/3、固定密码认证和 Local-first P2P 的规格、计划、实现与验收记录只用于理解待替换资产，不可作为新实现依据。
- 历史工程规格：[工程基础与双人认证设计规格](./superpowers/specs/2026-08-16-project-foundation-design.md)。
- 历史实施计划：[Project Foundation And Auth Implementation Plan](./superpowers/plans/2026-08-16-project-foundation-auth.md)。
- 历史 Phase 2 规格：[Phase 2 Task Core Design](./superpowers/specs/2026-08-17-task-core-design.md)。
- 历史 Phase 2 实施计划：[Phase 2 Task Core Implementation Plan](./superpowers/plans/2026-08-17-task-core.md)。
- 历史 Phase 3 规格：[Phase 3 Delay And Blocking Design](./superpowers/specs/2026-08-17-delay-blocking-design.md)。
- 历史 Phase 3 实施计划：[Phase 3 Delay And Blocking Implementation Plan](./superpowers/plans/2026-08-17-delay-blocking.md)。
- 历史 P2P 架构规格：[Local-first P2P 双人同步架构设计](./superpowers/specs/2026-08-21-local-first-p2p-architecture-design.md)。
- 历史 P2P 实施计划：[Local-first P2P Implementation Plan](./superpowers/plans/2026-08-21-local-first-p2p.md)。
- Git：本地 `main` 已跟踪 GitHub `origin/main`；本轮云端替换直接在 `main` 完成，提交前保留完整验证记录。

### 2026-09-10 - Android 前台 REST Cursor 自动同步施工完成

- 类型：Android 同步可靠性 / 生命周期 / 测试。
- 变更：正式 `CloudWorkspaceScreen` 使用的 `WorkspaceSyncController` 现在通过
  `changes(after_cursor=...)` 每 30 秒轮询增量；进入前台时立即补拉，进入后台或非活跃状态时暂停。
  定时器、手动刷新和前台恢复共用同一个游标请求，并合并并发请求，继续保留快照缓存和手动刷新。
- 边界：本轮不引入 WebSocket、Redis、推送或后台常驻服务；应用被系统杀死或长期后台时不承诺实时同步，
  下一次回到前台会依据本地游标追平服务端变更。REST Cursor 仍是同步正确性来源。
- 验证：Dart format、`flutter analyze` 和 Flutter 全量测试 `206 passed`；另覆盖初始化期间进入后台的生命周期回归；
  `git diff --check` 通过。
- 提交：`35a4168`；后续生命周期竞态修复为 `2280989`。

### 2026-09-10 - 双人任务验收自动审批施工完成

- 类型：后端任务状态 / 双人审批 / Android 与 Web 兼容施工。
- 变更：负责人提交“待验收”时，服务端在同一事务内执行 `IN_PROGRESS -> REVIEW`，并自动创建唯一的 `STATUS_UPDATE` 验收审批；审批只允许另一位 ACTIVE 成员处理。批准后任务进入 `DONE`，驳回必须填写原因并将任务回到 `IN_PROGRESS`，审批结果和任务快照一并返回，避免客户端等待下一次同步才能恢复状态。
- 单人边界：ACTIVE 成员不足两人时，提交验收直接拒绝且不会留下 `REVIEW` 任务或无审批人的请求；负责人不能绕过验收直接完成。
- 客户端：Android 详情、审批中心和同步控制器识别验收审批及任务快照；Web 审批列表隐藏内部 `review_submission` 标记并展示“任务验收 / 待验收”。
- 验证：后端 PostgreSQL 全量 `245 passed, 3 skipped, 1 warning`；Web TypeScript
  typecheck、Vitest `264 passed` 和 Vite 生产构建通过；Flutter Dart format、`flutter analyze`
  和 `flutter test` `201 passed` 通过；`git diff --check` 与 Python compileall 通过。
- Android：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-d5caaa2.apk`，大小约
  `173 MB`，SHA-256 为
  `f15a0c4304453ab99d487b62302514128906876bf55b983a4c0c1c351312f8f7`；包内 API 地址检查和
  `unzip -tq` 通过。本轮不创建版本 Release，正式包仍由 tag/release CI 生成。

### 2026-09-08 - Android 日程紧凑月历施工完成

- 类型：Android 日程 TAB / 分类筛选 / 月历交互。
- 变更：日程与清单、四象限共用顶部结构，中央分类下拉默认“全部任务”，分类状态跨任务 TAB 保持一致；正文改为紧凑完整月历，支持月份前后切换，右侧周列选择周范围，今天默认选中，相邻月份日期降低亮度；点击日期或周号后更新下方日期任务清单。
- 兼容：保留任务点击进入详情、下拉刷新和无新增任务入口，移除日程正文中的重复分类筛选。
- 验证：Flutter 全量 `192 passed`，日程专项与工作区专项通过；`flutter analyze`、Dart format 和 `git diff --check` 通过。
- 提交：`eb235a7` 已推送 `origin/main`。
- 产物：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-eb235a7.apk`，大小 `203394652` 字节，SHA-256 为 `09a99059af59e27b5a752b07958118578e6fe8e6d49c842f75d02cde5c3fae25`；归档校验和线上 API 地址检查通过。

### 2026-09-08 - Android 四象限动画生命周期断言修复

- 类型：Android 稳定性修复 / 生命周期回归。
- 变更：四象限展开由 `AnimatedSwitcher` 调整为单子树 `AnimatedSize`。切换或卸载页面时不再保留退出中的旧象限子树，避免 `InheritedElement.debugDeactivated` 的 `_dependents.isEmpty` 断言。
- 验证：新增展开动画进行中由 Tab 容器移除页面的 widget 回归测试；Flutter 全量 `188 passed`，`flutter analyze`、Dart format 与 `git diff --check` 通过。
- 提交：`6628df3` 已推送 `origin/main`。
- 产物：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-6628df3.apk`，大小 `203379026` 字节，SHA-256 为 `f10e04dd2945bbaf112f4e201bcb4e5216365ddcb0cd0309952f308a6d5119da`；归档校验和线上 API 地址检查通过。

### 2026-09-08 - Android 四象限四宫格展示

- 类型：Android 任务视图 / 视觉令牌 / 分类筛选。
- 变更：四象限页改为轻量 2×2 宫格，Q1/Q2/Q3/Q4 标题条分别使用主题中的浅珊瑚、浅琥珀、浅绿和浅蓝灰背景；任务行保持白底并复用清单摘要。每格最多预览四项，超过四项只显示“更多任务”，点击后当前象限扩展为全宽完整列表并隐藏其他象限，可返回宫格。
- 顶栏：四象限与清单共用分类下拉，默认“全部任务”；四象限正文不再放置独立分类筛选，也不提供新增任务或清单专用更多菜单。
- 验证：新增四象限 widget 测试覆盖宫格、颜色标题、四项预览、展开/返回和分类筛选；Flutter 全量 `187 passed`、`flutter analyze`、Dart format 与 `git diff --check` 通过。提交 `66a864b` 已推送 `origin/main`。
- 产物：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-66a864b.apk`，大小 `203379618` 字节，SHA-256 为 `b1b3389763105c8382a2f0959775639660b7c13cfce49ec14dfafe5a8fab6cc3`；归档校验通过，包内 API 地址为 `https://muyu.bkverse.space`。本轮不创建版本 Release，正式包继续由 tag/release CI 生成。

### 2026-09-08 - 移除系统默认分类

- 类型：任务分类契约 / Workspace 初始化 / 数据迁移 / 跨端回归。
- 变更：Workspace 创建与双人绑定不再自动生成“默认”分类。首个及后续分类均需通过
  `CLASSIFICATION_CREATE` 双人审批；没有已批准分类时，任务创建在 Android、Web 与 API
  三层均被拒绝或禁用。
- 迁移：Alembic `0013_remove_default_classification` 清理既有系统“默认”分类，并将仅
  使用该分类（含首尾空格变体）的历史任务转换为遗留空分类；其他已批准分类和任务标签
  保持不变。历史空分类仅保留读取兼容，不能绕过新写入的必选分类规则。
- 验证：迁移专项及相关 Workspace/API 测试 `13 passed`；容器化 PostgreSQL 后端全量
  `239 passed, 3 skipped`；Web TypeScript typecheck、Vitest `263 passed` 和生产构建
  通过；Flutter 格式检查、`flutter analyze` 和 `flutter test` `184 passed` 通过；
  `alembic heads` 确认 `0013_remove_default_class (head)`，`git diff --check` 与
  Python compileall 通过。

### 2026-09-04 - Workspace 分类与单分类任务契约施工完成

- 类型：跨端任务模型 / 双人审批 / 数据迁移 / 测试。
- 变更：新增 `workspace_classifications` 已批准分类表和 `CLASSIFICATION_CREATE`
  双人审批类型；分类名去空格、大小写归一化并限制为最多 5 个字符，且归一化后的
  持久化比较值也受相同长度限制，重复已批准分类或重复待审批请求会被拒绝。任务创建、
  负责人直接修改和非负责人审批应用均只允许一个已批准分类。
- 兼容边界：API 和数据库字段继续使用 `labels` 数组，旧快照可读取空数组；
  Alembic `0009_workspace_classifications` 创建分类及审批所需结构，
  `0010_single_task_classification` 将历史多值数组收敛为首项并增加单值检查。所有
  新建、显式分类修改和审批中的分类变更拒绝空分类或多个不同分类；历史空分类
  任务仍可读取和编辑无关字段，但不能借此写入空分类。
- 客户端：Android 和 Web 均改为单选分类控件，分类创建入口只产生待审批请求；
  Web 直接同步调用和通用审批调用也在发送前执行单分类和已批准分类校验。快照、首页
  投影与增量同步在声明分类资源后校验任务分类归属；不一致增量会回拉权威快照，旧缓存
  缺少该资源时只保留一次读取兼容。界面文案统一使用“分类”，不再提供多标签编辑器。
- 验证：后端 PostgreSQL 全量 `237 passed, 3 skipped, 1 warning`；Web Vitest 全量
  `262 passed`，TypeScript typecheck 和 Vite build 通过；Flutter 全量 `179 passed`，
  `flutter analyze` 与 Dart format 通过；`git diff --check`、Python compileall 通过。
  迁移专项已覆盖从干净 schema 建立 `0009/0010` 的结构与单值约束。公共测试数据库
  仍保留旧版 `0003_delay_blocking` 版本号，不能用它做当前 head 的直接 `alembic check`。
  线上迁移与新 APK 不属于本轮验收。

### 2026-09-03 - 默认截止时间与清单日期分组交付

- 类型：任务契约 / 数据迁移 / Android 交互 / 线上 API 更新。
- 变更：创建任务省略 `due_at` 时由服务端按请求创建时刻加 14 天生成；幂等重试使用原始请求指纹，不会因默认时间重新计算而产生冲突。新增 Alembic `0008_default_task_due_at`，仅为历史 `due_at IS NULL` 任务回填 `created_at + 14 天`，已有明确日期保持不变。Android 清单移除“无时间”分组，遗留 null 日期任务归入“今天 / 即将到期”以保持可见。
- 验证：后端 PostgreSQL 全量 `226 passed, 3 skipped`；迁移专项覆盖 null 回填和显式日期保留；Flutter 全量 `161 tests`、`flutter analyze` 和 Dart format 通过；线上数据库 revision 为 `0008_default_task_due_at`，任务总数 `6`、null 截止时间 `0`。
- 线上 API：本地构建镜像 `muyu-cloud-api:local-1911beb`（digest `sha256:62c9403392f06a84506d2da36c0a5244e9b8c2610041f293bb2620ccc7ad8cf7`），已更新 `api` 与 `web-session-cleanup`；公网 `/health/live`、`/health/ready` 返回 `200`，未授权任务接口返回 `401 authentication_required`。
- Android：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-1911beb.apk`，大小 `203310783` 字节，SHA-256 为 `d4b57b934bea518654e8bb534d7ca06cf7556fd767acdcd4e77d97723a82e928`；使用 `https://muyu.bkverse.space` 构建并通过 `unzip -tq` 和 origin 检查。本轮不创建版本 Release，正式包仍由 tag/release CI 生成。

### 2026-09-03 - 六状态任务契约施工与全量验收

- 类型：工程实施 / 跨端契约审计 / 全量验收。
- 变更：完成六状态任务模型从数据库、FastAPI 状态机、审批、cursor 同步、Web 行动首页到 Android 清单/详情的贯通；统一 `TODO`、`IN_PROGRESS`、`BLOCKED`、`REVIEW`、`DONE`、`CANCELLED` 内部标识和六种中文展示。`REVIEW` 由另一位 ACTIVE 成员验收，退回必须填写原因；`BLOCKED` 必须保留阻塞原因和恢复负责人；首页只显示当前用户可行动的当前任务、阻塞任务和待我验收任务。
- 审计：清理活动测试与云协议中的旧 `WAITING`/直接完成流程，迁移回滚和读边界测试仍保留旧值以验证兼容映射；`current_handler_id` 仍是唯一负责人，没有恢复参与人模型。
- 验证：后端 PostgreSQL 全量 `224 passed, 3 skipped`；Web Vitest `257 passed`、TypeScript typecheck 和 Vite build 通过；Flutter 全量 `160 tests`、`flutter analyze` 和 Dart format 通过；受影响的 Android/Web 状态回归均通过。
- 流程优化：后续施工按“单一行为 -> 先写失败测试 -> 最小实现 -> 受影响模块回归 -> 独立提交 -> 全量门禁”的节奏执行；只有接口契约已经稳定的独立模块才并行处理，环境问题单独隔离，不与业务修改混在同一轮。
- 下一步：保留真实 Android 设备、线上服务和正式 APK 发布作为独立验收批次；本轮不创建 Release，不把未执行的真机验收标记为完成。

### 2026-09-03 - 当前工作区 API/Web 部署与 Android 调试包

- 类型：线上部署 / 数据库迁移 / 发布后验收。
- 构建：在本地使用阿里云 PyPI 镜像构建当前工作区；API 与
  `web-session-cleanup` 使用镜像 `sha256:fd4f1017b951bd3ced673135ff108ef0e1ace3ed706cb38439d53fec9b21b5af`，Web/Caddy 使用镜像
  `sha256:dd40e57d46c3813d2a982d131aff96dc523465a0b886aba371aeef9ee9d7a265`。
- 数据库：线上 `muyu` 从 `0006_trust_sms_devices` 升级到
  `0007_six_state_task_status (head)`，未重置、删除或改写业务数据。
- 外部 PG：`deploy/docker-compose.external-db.yml` 让连接 URI 不包含密码，密码通过
  `PGPASSWORD` 注入，避免 `@` 密码字符导致主机解析错误；API 与 worker 均已按该配置重建。
- Android：本地调试包为
  `client/build/app/outputs/flutter-apk/Muyu-c0145b0.apk`，大小 `203301838` 字节，SHA-256 为
  `1afc256d356fb2a21da5e71c3f89f6473b5587e097b33e4b0d5c84d9c5fbbf2f`；构建内容包含当前工作区变更，API 地址为 `https://muyu.bkverse.space`。
- 验收：API 容器 `healthy`，worker 运行，公网 `/health/live` 与 `/health/ready` 返回 `200`，公网首页返回新 Web 资源 `index-DRwfyBMH.js` / `index-fssons5N.css`，未授权 `/api/v1/home` 返回预期 `401`。

### 2026-09-03 - Android 新建任务图标化输入

- 类型：Android 交互施工 / 任务创建回归。
- 变更：新建任务弹层打开后自动聚焦标题输入；标题下方提供截止时间、分类标签、四象限三个图标入口。时间入口依次选择日期和时间，标签入口支持已有分类、多选和新建，四象限入口使用 Q1-Q4 选择器；四象限仍为创建必选项，创建请求继续使用 `title`、`due_at`、`labels`、`quadrant`，状态和负责人规则不变。
- 验证：受影响 Flutter 测试 `22 passed`；Flutter 全量 `161 tests`、`flutter analyze` 无问题；APK 通过 `unzip -tq` 和线上 API 地址检查。
- 产物：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-c0145b0.apk`，大小 `203312837` 字节，SHA-256 为 `bd2a82e86c58b1bd553791f653df6e71e32d5905f5c8f28e753deb31dabff8bc`；本轮不创建 Release。

### 2026-09-03 - Android 新建任务象限色彩与中文截止时间

- 类型：Android 视觉交互施工 / 新建任务回归。
- 变更：为 Q1-Q4 增加深色独立主题色及浅色表面令牌（Q1 深珊瑚、Q2 琥珀橙 `#C47A20`、Q3 暗绿色、Q4 蓝灰）；新建任务选择象限后，仅通过右侧圆形感叹号按钮的背景颜色识别象限，不再显示象限文字 chip。截止时间统一显示为 `09月03日 周五 18:30`，不显示年份；选择后时间按钮动态扩展并在窄屏与标签、象限按钮保持同一行，三个工具均为圆形背景图标。
- 验证：主题令牌、中文时间格式、象限图标颜色和 320px 窄屏布局均有 widget 测试覆盖；Flutter 全量 `161 tests`、`flutter analyze` 和 Dart format 通过。
- 产物：重新构建本地调试包 `client/build/app/outputs/flutter-apk/Muyu-c0145b0.apk`，大小 `203311667` 字节，SHA-256 为 `ccabe48b9e81d58cfe712d12d1d408bf7874cc7fb20bdc4b74059fc679a37dc6`；本轮不创建 Release。

### 2026-09-02 - Android 视觉系统令牌化施工完成

- 类型：工程实施 / 全量客户端验证。
- 变更：Android 客户端统一使用 Web 视觉基线映射的 Material 3 `ColorScheme` 与 `MuyuThemeExtension`；收敛冷白页面、表面白、深绿主色、浅绿重点、珊瑚提示、独立错误色、4/8/12/16/24/32 间距、最多 8px 圆角和低阴影。清单、四象限、日程共用任务系统顶部栏；任务行、任务详情、新建任务、审批、冲突、扫码、登录、Workspace 引导、资料和设备页面移除旧的散落样式值并改用主题令牌。保留四个底部 Tab、任务字段、同步、审批、资料和设备行为不变。
- 代码：`05244d2`（`feat(client): finish Android visual token alignment`）。
- 验证：`dart format --output=none --set-exit-if-changed .` 通过；`flutter analyze` 无问题；Flutter 全量 `123 tests` 通过；旧蓝色/旧种子色扫描仅剩主题文件中的正式令牌定义；APK 通过 `unzip -tq` 完整性检查。
- 产物：本地调试包为 `client/build/app/outputs/flutter-apk/Muyu-05244d2.apk`，大小 `203269394` 字节，SHA-256 为 `374afe28e922907e90293f06152f08fb46814fea93299f4a6b73774fd1b99364`；构建使用线上 API 地址，仅作为 commit 命名调试包，不创建 Release。
- 下一步：在真实 Android 设备上进行安装和视觉巡检；正式版本继续由 tag/release CI 生成 `Muyu-v<version>.apk`。

### 2026-09-02 - Web 行动工作台状态与中文展示设计收口

- 类型：设计收口 / 待施工。
- 变更：确认 Web 端采用六种用户可见状态：待进行、进行中、阻塞中、待验收、已完成、已取消；内部状态标识继续使用英文枚举，页面、筛选、详情、首页、通知和无障碍名称统一只显示中文。首页按“当前任务（最多 5）/当前阻塞（最多 3）/待我验收（最多 3）”组织，已完成和已取消只在全部任务与历史中查看。
- 协作规则：`BLOCKED` 仅显示当前用户负责且暂时无法推进的任务；`REVIEW` 默认由另一位成员验收，通过进入 `DONE`，退回必须填写原因并回到 `IN_PROGRESS`。阻塞原因、阻塞时长、等待对象和验收结果均保留活动历史。
- 兼容边界（历史设计记录，当时待施工）：当时计划将旧内部 `WAITING` 迁移为 `BLOCKED` 并新增 `REVIEW`；当前实现已由 2026-09-03 条目收口。
- 权威文档：[Web 行动工作台任务状态与首页模块设计](./superpowers/specs/2026-09-02-web-action-workbench-task-status-design.md)。本条仅记录设计，不代表已开始工程施工。

### 2026-09-02 - Android 与后端任务状态契约同步设计

- 类型：设计同步 / 待施工。
- 变更：确认 Android 与 Web 使用同一套六状态中文展示：待进行、进行中、阻塞中、待验收、已完成、已取消；后端、数据库、API、同步和测试继续使用 `TODO`、`IN_PROGRESS`、`BLOCKED`、`REVIEW`、`DONE`、`CANCELLED` 内部标识。补充 Review 验收元数据、状态转换、阻塞字段清理规则和活动事件要求。
- 后端设计：`IN_PROGRESS -> REVIEW` 时由服务端指定另一位 ACTIVE 成员为 `reviewer_user_id`；验收通过进入 `DONE`，退回必须带原因并回到 `IN_PROGRESS`。`BLOCKED` 使用 `blocked_reason`、`blocked_since`、`resume_handler_id` 和可选 `waiting_for_user_id`，解除后清除阻塞信息。
- 兼容边界（历史设计记录，当时待施工）：当时尚未完成数据库枚举、状态机、快照、增量、审批和两端文案迁移；当前实现已由 2026-09-03 条目收口。
- 权威文档：[后端技术设计](./02-technical-design.md) 与 [Web 行动工作台任务状态与首页模块设计](./superpowers/specs/2026-09-02-web-action-workbench-task-status-design.md)。

### 2026-09-02 - 我的页、可信设备与 bootstrap 匹配契约

- 类型：当前契约收口 / 客户端 helper / 活动文档更新。
- 变更：任务审批入口固定在 Android“我的”页 AppBar，设备短信验证直接建立 `ACTIVE` 可写设备，设备撤销需要确认且不能撤销当前设备，个人资料仅支持名称编辑；Workspace bootstrap 明确返回 ACTIVE 成员的匹配状态、数量、成员名称、脱敏手机号和当前成员标记。
- 匹配规则：零或一名 ACTIVE 成员返回 `waiting_partner`；恰好两名 ACTIVE 成员返回 `matched`；客户端只有在服务端状态、数量和两个成员状态同时一致时才返回 partner，否则显示默认头像和“匹配中”，不泄露或伪造占位成员身份。
- 设备边界：首版不创建设备授权请求；`0006_trust_sms_devices` 负责迁移未撤销的历史 `PENDING` 设备并使遗留请求过期，`REVOKED` 设备、移动会话和审计历史不恢复。未来的任务化设备审批设计记录在[延期说明](./superpowers/superseded/2026-09-02-device-approval-task-design-note.md)。
- 验证：后端 bootstrap matching contract `9 passed`；Flutter `test/workspace/workspace_bootstrap_repository_test.dart` `7 passed`；两组测试覆盖零/一/二成员、ACTIVE 过滤、当前成员标记和无 phantom partner 的客户端占位行为。
- 下一步：继续执行 Task 7 的全量后端、Flutter、Web、迁移和 APK 验证；没有连接真实 Android 设备时，不把扫码、安装和短信链路标记为人工通过。

### 2026-09-01 - 移除任务参与人模型与 Android 账户概览

- 类型：当前契约收口 / 数据库迁移 / 客户端缓存失效。
- 任务规则：任务只以 `current_handler_id` 表示当前负责人；同一 Workspace 的两位 ACTIVE 成员读取全部未删除任务和子任务，负责人直写，另一位成员的受保护写入继续使用既有对方审批流程。
- Android：`“我的”` 概览独立统计当前用户负责的全部未删除父任务和子任务，汇总任务、完成和延期次数/分钟；匹配对象头像进入对方的同口径概览。数据来自 Workspace snapshot，不引入独立 analytics API、表或缓存。
- 数据库：`0005_remove_task_assignees` 在执行破坏性步骤前拒绝空或非同 Workspace ACTIVE 负责人的非删除任务；迁移会有意删除开发数据库中的旧参与人关联和所有已废弃的 `ASSIGNEE_UPDATE` 记录，保留负责人、任务历史、评论、延期、阻塞、活动和其他审批记录，不伪造替代负责人。
- 客户端缓存：快照键从 `muyu.workspace.snapshot.$workspaceId` 递增为 `muyu.workspace.snapshot.v2.$workspaceId`，旧契约缓存不会被当作当前快照读取；刷新失败继续保留最后一次有效快照。
- 当前权威：[移除任务参与人模型设计](./superpowers/specs/2026-09-01-remove-task-participants-design.md)。

### 2026-08-31 - 线上后端与 PostgreSQL 迁移到当前版本

- 类型：生产部署 / 数据库迁移 / 回归验证。
- 源码与镜像：后端运行时对应 `24741f7`；在本地使用
  `http://mirrors.aliyun.com/pypi/simple/` 构建，线上 `api` 与
  `web-session-cleanup` 使用同一镜像 ID `sha256:e9f5836157da58c23a54a3371adc8bee5dccee6b08193204347db3de89f477e9`。
- 数据库：生产 `muyu` 在迁移前为 `0002_device_session_indexes`；已完成
  `0003_two_person_task_approval` 和 `0004_task_labels_quadrant`，当前 head 为
  `0004_task_labels_quadrant`。`tasks` 已具备非空 `task_number`、`quadrant`、`labels` 约束，
  `task_approval_requests` 与 `task_number_sequences` 已创建。
- 数据保护：迁移前完整 custom-format 备份为
  `/root/backups/muyu-pre-migration-20260831T085657Z.dump`，大小 `93731` 字节，
  SHA-256 为 `3af2fd9ab3bb7552aa8034d648cec2d3d9df2538d314bdf617649a76718bb8fc`；服务器原工作树另有快照备份。
- 遗留数据：异常任务 `8cb70e53-ebc2-470a-b2c5-80f6a86e0ff1` 保持软删除，迁移时为不可见历史行补齐 `Q4`，未删除活动审计记录；当前活动任务数为 `0`。
- 服务验收：API 容器健康为 `healthy`，数据库 URL 解析到 `1Panel-postgresql-lJTO:5432/muyu`；
  `https://muyu.bkverse.space/health/live` 和 `/health/ready` 均返回 HTTP `200`，近 5 分钟 API/Caddy 无错误日志。
- 环境说明：外部数据库 Compose 需要 URL 编码密码（本次启动使用 `POSTGRES_PASSWORD=Conti%401234`
  覆盖值）；不得把明文凭据写入仓库或日志，后续部署命令需继续使用同等编码方式。

### 2026-08-31 - Android 清单交互与同步刷新施工完成并发布 v0.1.3

- 类型：工程实施 / 全量客户端验证 / 发布 `v0.1.3`。
- 变更：清单汉堡菜单改为左侧 Drawer；清单、四象限和日程统一使用顶部下拉刷新，短列表也可触发；任务页移除刷新和 Web 扫码入口，扫码授权仅保留在“我的”；同步控制器对快照刷新和游标增量拉取增加单飞保护，避免手动刷新、WebSocket 提示和写入后同步重复请求。
- 版本：Android 客户端更新为 `0.1.3+1`，正式发布资产命名为 `Muyu-v0.1.3.apk`；本地调试资产继续使用 `Muyu-<short-commit>.apk`。
- 验证：本地 Flutter 全量 `88 tests`、`flutter analyze`、Web typecheck/Vitest `72 tests`、Vite build、客户端边界和旧运行时检查均通过；tag 触发的 CI（run `33373152135`）和 Release（run `33373152112`）均成功。
- 发布：GitHub Release [木鱼协作 v0.1.3](https://github.com/Astro24002/Muyu/releases/tag/v0.1.3) 仅包含 `Muyu-v0.1.3.apk`，大小 `180841850` 字节，SHA-256 为 `6a79ffef56dd1d6340f42fcb8cb9ba145c4e04345dcb1b533e9f1fa807cc78cc`。
- 线上数据清理：异常旧任务 `111`（ID `8cb70e53-ebc2-470a-b2c5-80f6a86e0ff1`）已执行单条软删除，活动任务数降为 `0`，相关历史记录保留。
- 线上阻塞：只读检查显示生产数据库 Alembic 版本仍为 `0002_device_session_indexes`，且旧 `tasks` 表没有 `quadrant`、`task_number`、`labels` 列；客户端报错的根因是客户端契约已升级而线上 schema/服务尚未迁移。后续必须先按部署流程升级到当前 migration head，再进行新任务创建验收。

### 2026-08-31 - Android 任务导航与多标签施工完成

- 历史说明：本条记录的多标签规则已由 2026-09-04 单分类任务契约替代；当前任务
  只能选择一个已批准分类，详见[单分类任务模型设计](./superpowers/specs/2026-09-04-single-task-classification-design.md)。
- 类型：工程实施 / 全量验证。
- 变更：任务数据新增必选四象限 `Q1`-`Q4` 与任务内多标签；服务端 PostgreSQL
  迁移 `0004_task_labels_quadrant` 设置 `tasks.quadrant NOT NULL`、`labels JSONB`
  非空数组，并贯通创建、编辑、字段版本、双人审批、快照和 cursor 增量。
  Android 工作区改为四项底部导航“清单 / 四象限 / 日程 / 我的”，移除看板入口；
  创建和详情编辑支持象限与最多 10 个标签（单标签 32、总长度 320）；非负责人修改
  继续返回待审批且不乐观修改。Web 保持原页面布局并发送相同字段与校验。
- 验证：PostgreSQL 后端全量 `142 passed, 3 skipped`；Flutter 格式检查、`flutter analyze`
  和全量 `74 tests` 通过；Android debug APK 构建成功并确认嵌入
  `https://muyu.bkverse.space`；Web `71 tests`、typecheck、Vite build 通过；客户端边界、
  旧运行时、部署拓扑和 CI tag/release 触发器检查通过。
- 数据与发布：验证使用 disposable PostgreSQL 容器，未操作线上数据；本轮不创建新 tag、
  Release 或 iOS 安装包。真实 Android 设备安装、扫码和线上任务操作仍需单独人工验收。

### 2026-08-28 - 双人任务审批闭环与 0.1.2 发布准备

- 类型：实施完成 / 全量验收 / 发布准备。
- 变更：完成双人任务审批模型、任务负责人约束、四象限与进行中进度、评论软删除、
  审批状态机、快照/增量同步，以及 Android 和 TypeScript + Vite Web 两端的审批收件箱。
  同一 Workspace 严格保持两位 ACTIVE 成员；非负责人写入返回 `202` 待审批，不会乐观修改任务。
  新增可重复的 PostgreSQL smoke 入口，并统一使用 Python 3.12 容器和清华 PyPI 源。
- 代码：`cc5b6ed`（Web 审批闭环）、`848053b`（Web 交互和兼容性修正）；客户端版本为
  `0.1.2+1`，正式发布资产命名为 `Muyu-v0.1.2.apk`。
- 验证：后端全量 `124 passed, 3 skipped`；审批专项 `make test-task-approval` 为
  `40 passed`；两人 smoke `1 passed`，输出任务编号、审批请求标识、`APPROVED` 和最终游标；
  Flutter format 无改动、`flutter analyze` clean、`61 tests`；Web `10` 个测试文件、
  `65 tests`，typecheck 和 Vite build 均通过；客户端边界、旧运行时、CI 触发器和 Compose
  部署拓扑检查均通过。后端保留既有 Starlette/httpx 弃用警告。
- 数据库：验证使用 disposable PostgreSQL 容器 `muyu-task1-postgres`，未操作生产数据；开发阶段
  允许丢失旧数据，生产迁移仍需在新空库执行并复核。
- 范围：仍只交付 Android 与 Web；不引入离线写队列、P2P、iOS、附件、Elasticsearch 或密码登录。
- 待发布：尚未创建 GitHub `v0.1.2` Release；需完成 release APK 构建、SHA-256 记录、推送 tag，
  并等待 GitHub Actions 成功后才可标记发布完成。真实 Android 扫码/安装验收仍取决于连接设备。

### 2026-08-31 - 0.1.2 发布前最终验证

- 类型：最终验证 / 发布门禁。
- 运行时源提交：`89bd456ce655b995af5a8a484950580667c6e761`。
- Android：在该提交上生成正式发布资产 `Muyu-v0.1.2.apk`，`versionName=0.1.2`、
  `versionCode=1`，SHA-256 为 `ae119c802e0d40f51b639eb5ac1f084a51d3d2c3f24e231705117128fca51f1e`；
  APK 内确认包含 `https://muyu.bkverse.space`。
- 验证：后端 `124 passed, 3 skipped`，审批专项 `40 passed`，两人 smoke `1 passed`；
  Flutter `61 tests`、Web `65 tests`，Web typecheck/Vite build、边界、旧运行时、CI
  触发器和 Compose 拓扑检查均通过。Web 会话测试已注入固定时钟，避免随系统日期过期。
- 环境说明：清华 PyPI 镜像在一次全新依赖安装中返回 HTTP 403；审批专项随后使用已准备的
  Python 3.12 依赖镜像复跑通过，不影响代码测试结果。
- 首次 tag 验证发现 schema 测试在公共 schema 与隔离 schema 同时存在时重复聚合枚举值；已在
  `89bd456` 中限定当前 schema，并在全新数据库复跑通过。随后将 `v0.1.2` 安全更新到
  `7fa7762`，CI（[33348660152](https://github.com/Astro24002/Muyu/actions/runs/33348660152)）和
  Release（[33348660116](https://github.com/Astro24002/Muyu/actions/runs/33348660116)）均成功。
  GitHub Release 仅包含 `Muyu-v0.1.2.apk`，大小 `180,784,798` 字节，SHA-256 为
  `5abca32227b80e822bfb07b25538fb8dfadcfb27145358606a3a713486e2ca67`；公开健康检查
  `/health/live` 与 `/health/ready` 均返回 HTTP 200。真实 Android 扫码/安装验收仍取决于连接设备。

### 2026-08-31 - v0.1.2 已发布

- 类型：发布完成 / CI 验收。
- Tag：`v0.1.2` 指向 `7fa776284b8dace75b827d3057cabffda1e606e8`。
- GitHub Release：[木鱼协作 v0.1.2](https://github.com/Astro24002/Muyu/releases/tag/v0.1.2)，仅发布
  `Muyu-v0.1.2.apk`；资产 SHA-256 为
  `5abca32227b80e822bfb07b25538fb8dfadcfb27145358606a3a713486e2ca67`。
- CI 的 Android、Web、后端和部署检查均成功；云协议和 Android 真机 job 按当前触发条件跳过。

### 2026-08-27 - Task Domain Completion: PostgreSQL Acceptance

- 类型：验收 / 文档 / 发布准备。
- 变更：补充可选执行的两用户 PostgreSQL 任务闭环验收，覆盖创建、另一用户
  snapshot/cursor 可见性、并发字段冲突与 proposed 解决、`WAITING`/`DONE` 状态流转、
  评论、延期、软删除和恢复；补充 Android/Web 任务工作流操作说明。
- 验证：disposable PostgreSQL focused E2E `1 passed`；`make backend-test`
  `64 passed, 3 skipped`，并完成 `compileall`；`make client-test` 的 format、
  `flutter analyze` 和 `33 tests` 通过；Web `npm ci && npm run typecheck &&
  npm test -- --run && npm run build` 通过（`7` 个测试文件、`51 tests`）；
  `make boundary-check` 和 `make check-deployment` 均通过。后端测试保留既有
  Starlette/httpx 弃用警告；云协议测试保持 opt-in，未开启时会 skip。
- Android 发布证据：源 commit `5e1fa66` 上，
  `API_BASE_URL=https://muyu.bkverse.space make client-build` 成功；产物为
  `client/build/app/outputs/flutter-apk/Muyu-5e1fa66.apk`，SHA-256 为
  `cb9b2d07901442a3bca746aa08d4aa44827a33d8f57894989fa6ea992941c5c4`。
  APK 检查确认包含该 API origin。
- 范围：本轮没有新增生产 API、数据库结构、离线写队列、P2P、iOS、附件、项目层级、
  Elasticsearch 或密钥；测试只使用 disposable PostgreSQL schema。
- 真机验收：待执行。必须在 `adb devices` 显示真实 Android 设备后再安装
  commit-named APK；没有设备时不得把扫码、任务创建和冲突交互标记为通过。
- 详细操作：[轻量任务工作流](./operations/task-workflow.md)；发布核对项见
  [Release Checklist](./operations/release-checklist.md)。

### 2026-08-26 - Android 与独立 Web 客户端边界完成

- 类型：实施完成 / 发布流水线收口
- 变更：完成 Web API/二维码登录/Workspace 同步与 SPA 组装；Flutter 客户端固定为 Android，删除浏览器运行时和静态入口；Caddy 改为构建并服务 `web/dist`；CI 与 Release 仅响应版本 tag 和已发布 Release；Makefile、边界检查和运行文档同步更新。
- 验证：Web Vitest 全量（42 tests）、typecheck、Vite build；Flutter format、analyze、test（14 tests）与 Android debug APK；PostgreSQL 后端全量 50 passed、2 skipped；Compose 拓扑、CI 触发器、旧运行时和客户端边界脚本通过。真实短信、真机和生产部署仍需在具备外部依赖的环境中执行。
- 交付物：Android debug APK、受保护签名 Android AAB、`web-release.tar.gz`、`SHA256SUMS` 和 `SOURCE_COMMIT`；不生成 iOS 安装包。

### 2026-08-26 - Android 首个共享空间引导

- 类型：实施完成 / 发布验收记录
- 变更：登录后先读取当前 Workspace；没有 ACTIVE membership 时显示
  `创建共享空间`，创建成功后才进入任务页和 Web 扫码入口。补充首个 Workspace
  操作说明、发布后核对项和本次验收记录入口。
- 原因：新用户登录成功不等于已经加入共同 Workspace；必须先完成首个空间创建，
  才能满足 Web 扫码授权所需的 ACTIVE membership。
- 影响文件：`client/lib/workspace/`、`client/lib/screens/workspace_bootstrap_screen.dart`、
  `client/lib/screens/workspace_gate.dart`、`client/lib/app.dart`、`client/lib/main.dart`、
  `docs/operations/first-workspace-setup.md`、`docs/operations/release-checklist.md`、
  `docs/README.md`。
- 源 commit：`0a6a49d3473cd58adba53c5beb03b150ac213bfd`。
- APK：`client/build/app/outputs/flutter-apk/app-debug.apk`；SHA-256：
  `62093cdde48089d3b00cddda3bb5ca9f2f786dc639c727cf910dcb1e7f5e5b4d`。
- 自动验证：`TEST_DATABASE_URL=... make backend-test` 退出 0（`55 passed, 2 skipped`，
  1 条既有 Starlette/httpx 弃用警告）；`make client-test` 退出 0（格式检查、
  `flutter analyze`、`26 tests`）；`make boundary-check` 退出 0；
  `make check-deployment` 退出 0；
  `API_BASE_URL=https://muyu.bkverse.space make client-build` 退出 0并生成上述 APK。
- 公开站点只读检查：`GET https://muyu.bkverse.space/health/live` 返回 `200` 和
  `{"status":"live"}`；首页 HTTPS 返回 `200`；未认证请求
  `/api/v1/workspaces/current` 返回 `401 authentication_required`。
- 真机验收：未执行。`adb devices` 当时只有表头，没有连接的 Android 设备；因此首空间
  创建、扫码批准、注销后复登等人工项目仍标记为待执行，不能声称已完成。
- 公开站点：操作目标为 `https://muyu.bkverse.space`；无真机时不改变生产数据库、
  不手工创建 Workspace，也不绕过 membership 校验。人工验收应按
  [首个共享空间操作说明](./operations/first-workspace-setup.md)执行。

## 已完成

### 2026-08-16

- 完成产品、技术、路线和决策文档审阅。
- 初始化 Git 仓库并建立 `main` 分支。
- 将当前设计内容同步到 `Astro24002/Muyu` 的 `origin/main`。
- 形成并提交首轮工程规格。
- 形成首轮工程实施计划。
- 完成 Python 3.12/FastAPI 运行时骨架、配置校验、Dockerfile、Compose 和健康检查。
- 完成 SQLAlchemy 模型、Alembic `users`/`sessions` 迁移、固定用户幂等初始化、用户仓库和启动生命周期接线。

## 历史实施顺序（Phase 0-3）

以下顺序已经完成并仅记录旧基线；它不约束当前云端架构的后续实现：

1. 仓库与运行时骨架；
2. PostgreSQL 迁移与两名固定用户初始化；
3. 密码、JWT 和 Refresh Session；
4. FastAPI HTTP API 与统一错误契约；
5. Flutter Android/Web 登录与账户页；
6. Compose、CI 和端到端验收。

## 设计变更

### 2026-08-24 - 云端协调架构替代 Local-first P2P

- 类型：设计变更 / 新运行时规格
- 变更：任务事实源回到 PostgreSQL；FastAPI 模块化单体通过 REST cursor 同步和通知型 WebSocket 协调 Android 与 Web；认证改为 Android 短信验证码、长期设备审批和 Web 扫码会话；任务内容允许云端明文保存。
- 原因：产品需要稳定的多设备与 Web 协作体验，用户已明确选择云端中继和默认云端同步，而非仅两台机器 P2P 直连。
- 影响文件：云端架构规格、技术设计、路线图、已确认决策、文档索引与本状态记录；后续将替换旧 P2P、固定密码认证和旧后端运行时。
- 数据迁移影响：从空 Workspace 与新数据库模型开始，不导入旧任务、延期、活动、用户或 P2P 事件，不保留兼容 API。
- 验收影响：新增 PostgreSQL 事务/锁、短信验证码、设备审批、扫码会话、cursor、冲突、Android APK/AAB 与 Web 静态构建的共同验收；iOS 不进入本轮。
- 当前状态：云端实施计划和代码改造已完成，旧密码/P2P 运行时已删除；新数据库必须以空库启动，不执行旧数据迁移。
- 下一步：将已验证的镜像部署到明确的新空 PostgreSQL 实例，再执行 Android 真机、Chrome Web 和短信供应商联调。

### 2026-08-16 - 后端从 Go 切换为 Python 3.12

- 类型：设计变更
- 变更：后端由 Go 切换为 Python 3.12 + FastAPI + SQLAlchemy 2.0 + Alembic + psycopg + pytest；REST API、数据库模型、客户端和验收标准保持不变。
- 原因：项目维护者更熟悉 Python；当前只有 Go 测试契约，尚无 Go 业务实现，切换风险低。
- 影响文件：`docs/02-technical-design.md`、`docs/superpowers/specs/2026-08-16-project-foundation-design.md`、`docs/superpowers/plans/2026-08-16-project-foundation-auth.md`。
- 替代方案：保留 Go、改用 Flask 或采用 Django REST Framework；综合开发熟悉度、自动 API 契约和项目规模后选择 FastAPI。
- 迁移影响：无数据库迁移；后端工程骨架和依赖安装方式重新生成。
- 验收影响：服务端测试命令改为 `pytest`，容器镜像改为 Python 3.12；API 行为验收不变。

## 实施进度

### 2026-08-25 - 云端协调架构 Tasks 1-15 收口

- 类型：实施完成 / 发布前验收
- 变更（历史基线，设备策略已由 2026-09-02 契约取代）：完成 PostgreSQL 权威数据模型、短信验证码移动会话、双人工作区与设备签名审批、设备恢复/撤销、二维码 Web 会话、任务冲突与幂等、评论/延期/循环/重要日期、cursor 同步和通知型 WebSocket；客户端切换为 Android SMS + Web QR；删除旧密码、JWT、P2P 和旧任务运行时。
- 验证：隔离 PostgreSQL 后端 `37 passed, 1 skipped`；真实 Uvicorn API 云协议端到端 `1 passed`；脚本 smoke、旧运行时检查、Compose 拓扑检查和 shell 语法检查通过；Flutter analyze 与 `17 tests passed`；Android debug APK 和 Web release bundle 构建成功。
- 范围（旧设备策略，已不再作为当前验收依据）：本轮只交付 Android 与 Web，不生成 iOS 安装包；旧版本曾存在 `PENDING` 设备，现由 `0006_trust_sms_devices` 兼容迁移处理。当前改为短信验证成功即 `ACTIVE`，详见本页 2026-09-02 记录。
- 下一步：使用新的独立 PostgreSQL/Compose 项目部署，执行 Android 真机、Chrome Web、短信供应商和备份恢复演练。

### 2026-08-25 - 接入国阳云生产短信 Provider

- 类型：供应商接入 / 生产配置
- 变更：保留手机号验证码认证，生产 Provider 改为国阳云阿里云市场接口；请求使用 `APPCODE` 认证和 query 参数，只有响应 JSON 的业务 `code == "0"` 才视为发送成功；新增 `SMS_SIGN_ID` 与 `SMS_TEMPLATE_ID` 配置校验；登录输入支持 11 位大陆手机号并在 API 内补全 `+86`。
- 模板：当前使用“验证码：`**code**`，`**minute**`分钟内有效，请勿泄漏于他人！”模板，模板 ID 为 `908e94ccf08b4476ba6c876d13f084ad`；验证码 AppCode 仍只通过服务器 Secret 注入。
- 验证：Provider 请求/业务响应测试和生产配置测试通过；隔离 PostgreSQL 后端认证回归 `13 passed`；已在生产域名通过真实供应商链路向验收号码发送测试短信并收到 `202`。
- 风险边界：AppCode 仅写入服务器 Secret；验证码不会进入日志、客户端构建参数或源代码。

### 2026-08-16 - Task 1 Python 运行时与配置骨架

- 类型：实施进度 / 验收
- 变更：新增 Python 3.12 项目元数据、Pydantic Settings 配置、FastAPI 应用和 `/healthz`、Python Dockerfile、PostgreSQL Compose 和开发 Makefile。
- 原因：为 Phase 0/1 的迁移、固定用户初始化、认证 API 和 Flutter 联调提供可复现的运行底座。
- 影响文件：`.gitignore`、`Makefile`、`backend/`、`deploy/`。
- 验证命令与结果：在 `m.daocloud.io/docker.io/library/python:3.12-slim` 中运行 pytest，9 项通过；`python -m compileall -q app` 通过；`docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config` 通过；镜像构建成功；容器 `GET /healthz` 返回 `{"status":"ok"}`。
- 下一步：Task 2，使用 Alembic 创建 `users`/`sessions` 迁移，并实现两名固定用户的幂等初始化。

### 2026-08-16 - Docker 镜像源调整

- 类型：设计变更 / 工程配置
- 变更：所有 Docker 基础镜像统一改用 `m.daocloud.io/docker.io` 前缀。
- 原因：默认 Docker Registry 拉取不稳定，Daocloud 镜像源已验证可用。
- 影响文件：`backend/Dockerfile`、`deploy/docker-compose.yml`、技术规格和实施计划。
- 验证命令与结果：成功拉取 `m.daocloud.io/docker.io/library/python:3.12-slim`，并用该镜像运行测试和构建 API 镜像。
- 下一步：后续新增 Docker 镜像继续使用该镜像源并在文档中记录。

### 2026-08-16 - Task 2 数据库与固定用户初始化实现

- 类型：实施进度 / 部分验收
- 变更：新增 SQLAlchemy 2.0 数据模型、Alembic 首个迁移、用户仓库、固定用户初始化服务，并将迁移和初始化接入 FastAPI lifespan；新增启动顺序测试。
- 原因：完成首个持久化垂直切片，保证 API 只有在迁移和两名固定用户初始化成功后才报告健康。
- 影响文件：`backend/alembic.ini`、`backend/alembic/`、`backend/app/db/`、`backend/app/user/`、`backend/app/main.py`、`backend/tests/`。
- 验证命令与结果：容器内 `python -m compileall -q app alembic` 通过；使用 `sqlite:////tmp/muyu-test.db` 运行 `tests/core tests/test_main.py tests/test_main_startup.py tests/db tests/user`，14 项通过；启动生命周期顺序测试通过。PostgreSQL 集成测试尚未完成：`m.daocloud.io/docker.io/library/postgres:16-alpine` manifest 返回 `403 DENIED`，无法启动 Compose 数据库。
- 下一步：恢复可用的 DaoCloud PostgreSQL 镜像访问后，运行 Compose 集成测试，确认迁移、重复初始化和 `users` 数量为 2，再关闭 Task 2 验收并进入 Task 3。

### 2026-08-17 - Task 2 PostgreSQL Compose 集成验收

- 类型：验收 / 阻塞解除
- 变更：使用 Docker Compose 启动 PostgreSQL，并在同一 Compose 网络中启动 API、运行完整后端测试和重复初始化验证。
- 原因：此前未完成 PostgreSQL 容器集成验收；当前 Docker 权限恢复且镜像可用后，需要验证真实 PostgreSQL 路径而非仅 SQLite 测试路径。
- 影响文件：无运行时代码变更。
- 验证命令与结果：`docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml build api` 成功；PostgreSQL 健康检查通过；Compose 网络内的 `python -m pytest -q` 测试容器以退出码 0 完成；API 两次启动后内部 `GET /healthz` 均返回 `{"status":"ok"}`；`SELECT count(*) FROM users` 返回 `2`。宿主机 8080 已被其他项目占用，因此本次 API 使用 `docker compose run --no-deps` 在内部网络验收，未修改默认 Compose 端口配置。
- 下一步：进入 Task 3，实现密码、JWT 和 Refresh Session。

### 2026-08-17 - Task 3 密码、JWT 和 Refresh Session

- 类型：实施进度 / 验收
- 变更：新增 bcrypt 密码散列校验、严格区分 Access/Refresh 的 JWT 管理器、Refresh Token SHA-256 哈希会话仓储，以及登录、刷新轮换和幂等登出服务；认证测试目录增加包标记，避免同名测试模块冲突。
- 原因：完成认证服务垂直切片，为后续 FastAPI 路由提供稳定的领域接口。
- 影响文件：`backend/app/auth/`、`backend/tests/auth/`、`backend/tests/user/__init__.py`。
- 验证命令与结果：认证测试 `12 passed`；PostgreSQL Compose 网络内完整后端测试 `26 passed`；`python -m compileall -q app alembic` 通过。测试覆盖密码正确/错误校验、JWT 签名/类型/过期校验、登录、Refresh 轮换撤销、无效凭据、过期令牌和幂等登出。
- 下一步：进入 Task 4，实现 FastAPI 认证与用户资料路由、鉴权依赖和统一错误响应。

### 2026-08-17 - Task 4 FastAPI 路由、鉴权依赖和错误契约

- 类型：实施进度 / 验收
- 变更：新增统一错误响应与 `X-Request-ID` 中间件、数据库和 Bearer Token 依赖、认证路由、当前用户资料路由及双方用户列表路由；应用生命周期创建 TokenManager 并接入路由。
- 原因：将认证领域服务接入可供 Flutter/Web 消费的 HTTP JSON 契约。
- 影响文件：`backend/app/httpapi/`、`backend/app/auth/routes.py`、`backend/app/user/routes.py`、`backend/app/main.py`、`backend/tests/httpapi/`、启动测试 mock。
- 验证命令与结果：HTTP API 测试 `5 passed`；PostgreSQL Compose 网络内完整后端测试 `31 passed`；`python -m compileall -q app alembic` 通过；真实 Compose API 生命周期健康检查返回 `{"status":"ok"}`，认证冒烟验证登录、`/api/me`、Refresh 轮换、旧令牌拒绝、登出和撤销后拒绝全部通过。测试输出有 1 条现有 Starlette/httpx 弃用警告，不影响结果。
- 下一步：进入 Task 5，实现 Flutter Android/Web 登录与账户页。

### 2026-08-17 - Task 5 Flutter 环境准备

- 类型：阻塞解除 / 工程环境
- 变更：在当前用户目录安装 Flutter 3.47.0、Dart 3.13.0、Temurin JDK 17.0.20、Android SDK 36、Build Tools 36.0.0 和 Platform Tools，并在 `~/.bashrc` 配置用户级环境变量。
- 原因：Flutter Android/Web 客户端必须通过 Flutter SDK 生成、测试、分析和构建。
- 影响文件：用户级 `~/.bashrc` 和 `/home/muyu/develop/` 工具目录；无客户端代码变更。
- 验证命令与结果：`flutter --version`、`dart --version`、`java -version` 和 `adb --version` 均通过；`flutter doctor -v` 的 Flutter 与 Android toolchain 检查通过，Android 许可证全部接受。Chrome 和 Linux desktop 工具未安装，不影响计划中的 Web 编译和 Android 构建。
- 下一步：生成 `client/` Flutter Android/Web 工程并继续 Task 5。

### 2026-08-17 - Task 5 Flutter Android/Web 客户端

- 类型：实施进度 / 验收
- 变更：生成仅包含 Android/Web 的 Flutter 工程；实现 API 配置、JSON 模型、平台 Token 存储、登录/刷新/登出仓库、401 单次刷新、会话控制器、登录页和账户资料页；后端增加本地 Web CORS 预检支持；Android 主清单加入网络权限，debug 仅允许明文 HTTP。
- 原因：完成首个可操作客户端垂直切片，覆盖两名固定用户的登录态恢复、资料修改和退出流程。
- 影响文件：`client/`、`backend/app/main.py`、`backend/tests/httpapi/test_cors.py`。
- 兼容性决策：`flutter_secure_storage 11.0.0` 要求 Android compile SDK 37，而 Flutter 3.47 工程默认 compile SDK 为 36；锁定 `flutter_secure_storage 10.0.0`，保持 Android SDK 36 基线并避免依赖平台命名兼容问题。
- 验证命令与结果：客户端 `dart format --output=none --set-exit-if-changed .`、`flutter analyze` 和 `flutter test` 通过（12 项）；`flutter build web --dart-define=API_BASE_URL=http://localhost:8090` 成功；`flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8090` 成功；后端完整测试 32 项通过；CORS 预检、API 健康检查和真实登录冒烟通过。Linux desktop feature 保持关闭。
- 下一步：Task 6，补充 Compose/API/Flutter CI 和完整认证端到端脚本。

### 2026-08-17 - Task 6 Compose、CI 和端到端验收启动

- 类型：实施进度
- 变更：开始补充 Compose API 健康检查、可配置宿主端口、认证 smoke 脚本、Makefile 统一入口和 GitHub Actions。
- 原因：将前五项垂直切片收敛为可重复启动、测试和验收的工程流程。
- 影响文件：`.github/workflows/ci.yml`、`scripts/smoke-auth.sh`、`deploy/`、`Makefile`、`docs/README.md`。
- 验证命令与结果：随后完成干净 PostgreSQL Compose 卷、认证 smoke、完整测试和 API 重启持久性验收，详见下方 Task 6 完成记录。
- 下一步：先完成 smoke 脚本和 Compose/CI wiring，再用干净 PostgreSQL 卷运行完整验收。

### 2026-08-17 - Task 6 Compose、CI 和端到端验收

- 类型：验收 / 实施完成
- 变更：新增 API 容器健康检查和可配置宿主端口；新增不输出 Token/密码的双用户认证 smoke 脚本；Makefile 增加后端、客户端、Compose、清理和 smoke 入口；GitHub Actions 增加 PostgreSQL 后端测试与 Flutter format/analyze/test；补充跨 SQLite/PostgreSQL 的 UTC datetime 类型。
- 原因：把首轮垂直切片收敛为可重复执行的本地和 CI 验收流程，并修复 SQLite 测试环境中的 naive/aware datetime 差异。
- 影响文件：`.github/workflows/ci.yml`、`scripts/smoke-auth.sh`、`deploy/docker-compose.yml`、`deploy/.env.example`、`Makefile`、`backend/app/db/types.py`、`backend/app/user/models.py`、`docs/README.md`。
- 验证命令与结果：`make backend-test` 通过（32 passed，SQLite）；`make client-test` 通过（12 tests，format/analyze clean）；隔离全新 PostgreSQL Compose 项目 `task6` healthcheck 通过；`AUTH_PASSWORD=change-this-shared-password API_BASE_URL=http://localhost:8091 ./scripts/smoke-auth.sh` 通过；PostgreSQL 网络内完整后端测试 32 passed；API 重启后仍 healthy，数据库用户数保持 2 且资料未被重置；Compose config、Shell syntax 和 CI YAML 检查通过。
- 下一步：首轮基础与认证验收完成，进入路线图后续任务/事件功能开发。

### 2026-08-17 - Phase 2 Task Core 启动

- 类型：实施进度
- 变更：按照产品、技术设计和路线图启动 Task Core；范围包括任务/一层子任务、参与人、当前负责人、基础状态动作、个人排序、追加式活动审计和 Flutter 任务工作区。
- 原因：认证底座已完成，下一条产品价值链必须让两名用户真实创建、转交并完成共同任务。
- 影响文件：`docs/superpowers/specs/2026-08-17-task-core-design.md`、`docs/superpowers/plans/2026-08-17-task-core.md`，后续将新增 `backend/app/task/`、`backend/app/activity/`、任务迁移、Flutter 任务模块和验收脚本。
- 验证命令与结果：规格已对照 `docs/01-product.md`、`docs/02-technical-design.md`、`docs/03-roadmap.md` 和 `docs/04-decisions.md` 收敛；代码验证将在每个计划任务完成后追加。
- 验证命令与结果：迁移、仓储/服务和 HTTP 契约测试已完成；SQLite 后端全量 `41 passed`，任务专项测试 `8 passed`，`python -m compileall -q app alembic` 通过。Flutter format/analyze clean，客户端全量 `19 passed`，Web 和 Android debug 构建成功。PostgreSQL Compose 任务 smoke 尚未完成。
- 下一步：运行干净 PostgreSQL Compose 的双用户任务闭环、API 重启持久性和最终全量验收。

### 2026-08-17 - Phase 2 Task Core 完成

- 类型：验收 / 实施完成
- 变更：完成任务、一级子任务、参与人、当前负责人、基础状态动作、个人排序、软删除和追加式活动审计；FastAPI 任务 API 接入认证路由；Flutter 登录后默认进入任务工作区，支持任务列表、创建、详情、启动、完成、取消、重开和转交；新增 `make smoke-tasks` 双用户验收入口。
- 原因：落地路线图 Phase 2 的首个可用任务闭环，并保留延期、阻塞、冲突、评论、循环任务和统计到后续阶段。
- 影响文件：`backend/app/task/`、`backend/app/activity/`、`backend/alembic/versions/0002_task_core.py`、`client/lib/task/`、`client/lib/screens/`、`scripts/smoke-tasks.sh`、`Makefile`、`docs/README.md`。
- 验证命令与结果：`make test` 通过（后端 SQLite `41 passed`，Flutter `19 passed`，`flutter analyze` clean）；`bash -n scripts/smoke-tasks.sh` 和 `docker compose config` 通过；Web 构建成功，Android debug APK 成功生成于 `client/build/app/outputs/flutter-apk/app-debug.apk`。隔离 PostgreSQL Compose 项目 `phase2` 在端口 `8093` 运行，双用户任务 smoke 通过（创建、启动、转交、子任务、完成、双方可见、审计事件）；API 重启后 Alembic 版本为 `0002_task_core`，任务和活动事件仍可读取；PostgreSQL 网络内完整后端测试 `41 passed`。现有 `8090` API 已升级到同一版本，固定用户数量保持为 `2`，原有昵称保持不变，登录和任务列表均返回 `200`。Flutter Web 在桌面 `1280x900` 和移动 `390x844` 视口完成登录、任务列表和创建任务检查，`scrollWidth == clientWidth`；旧 3000 端口 DDC 进程已重启，当前页面可正常加载。
- 下一步：进入 Phase 3，实现延期和阻塞规则、相关状态历史及客户端交互，并按文档继续记录每项验收结果。

### 2026-08-17 - Phase 3 延期和阻塞启动

- 类型：实施进度
- 变更：完成 Phase 3 延期和阻塞设计，明确 `DelayRecord` 不可变记录、延期原因校验、`WAITING` 状态、恢复负责人、HTTP 契约、Flutter 交互和验收边界。
- 原因：Phase 2 已完成，按照路线图进入 MVP-Core 的最后阶段，使任务可以保留真实延期与等待事实。
- 影响文件：`docs/superpowers/specs/2026-08-17-delay-blocking-design.md`，后续将新增 `0003_delay_blocking`、领域动作、任务 API、Flutter 详情交互和 Phase 3 smoke。
- 验证命令与结果：规格已对照产品、技术设计、路线图和已确认决策完成一致性检查；未包含状态冲突、评论、事件、循环任务、首页或统计。
- 下一步：按照 Phase 3 实施计划，以 TDD 顺序完成迁移、领域服务、API、Flutter 和 PostgreSQL 验收。

### 2026-08-19 - Phase 3 延期和阻塞实现与自动化验收

- 类型：验收 / 实施完成
- 变更：完成 Flutter 延期和阻塞对话框、任务详情阻塞元数据与延期历史、延期统计、`WAITING` 条件动作和列表状态样式；新增不输出凭据的双用户 Phase 3 smoke 脚本，并接入 Makefile 和本地验收文档。
- 原因：完成 MVP-Core 最后一条任务行为闭环，让延期原因、等待事实和恢复负责人在客户端与服务端保持一致。
- 影响文件：`client/lib/screens/task_action_dialogs.dart`、`client/lib/screens/task_detail_screen.dart`、`client/lib/screens/task_list_screen.dart`、`client/test/widget/task_workspace_test.dart`、`client/test/support/fake_task_repository.dart`、`scripts/smoke-delay-blocking.sh`、`Makefile`、`docs/README.md`。
- 验证命令与结果：后端 Docker 测试 `57 passed`（1 条既有 Starlette/httpx 弃用警告）；Flutter `dart format` 无变化、`flutter analyze` 无问题、`flutter test` `28 passed`；Web 构建成功，Android debug APK 构建成功；`bash -n scripts/smoke-delay-blocking.sh` 和 Compose config 通过。隔离 PostgreSQL Compose 项目 `muyu-phase3-final` 使用端口 `8094` 运行 `scripts/smoke-delay-blocking.sh` 和 `make smoke-delay-blocking` 均通过，覆盖三次延期、累计 `4320` 分钟、双方读取、阻塞/解除、负责人恢复和事件顺序；API 重启后 `/healthz` 返回 `{"status":"ok"}`，Alembic 版本为 `0003_delay_blocking`，延期记录、任务状态和事件仍然存在。当前未修改宿主机已有的 8090 服务，也未进行真实设备上的人工视觉巡检。
- 下一步：由维护者决定是否提交并部署 Phase 3；之后进入 Phase 4 状态冲突（`status_version`、409 冲突记录和冲突解决流程）。

### 2026-08-19 - Phase 4 状态冲突设计

- 类型：设计 / 待复核
- 变更：确定采用基于 `status_version` 的乐观并发控制；新增冲突快照、双方审批、`SUPERSEDED` 替代规则、409 HTTP 契约、Flutter 冲突专区和 PostgreSQL 验收边界的设计规格。
- 原因：在两台设备同时修改同一任务状态时避免静默覆盖，并保留可审计的协商与解决过程。
- 影响文件：`docs/superpowers/specs/2026-08-19-status-conflicts-design.md`。
- 验证命令与结果：已对照产品、技术设计、路线图和已确认决策；代码和迁移验证将在规格复核通过后按 TDD 计划执行。
- 下一步：请复核规格；确认后创建 Phase 4 实施计划，再开始迁移、领域服务、API、Flutter 和 PostgreSQL smoke 实现。

### 2026-08-21 - 历史：Local-first P2P 架构转向

- 类型：设计变更 / 架构规格
- 变更：任务事实源从 FastAPI/PostgreSQL 转为两台 Android 客户端的本地追加式 Event Store；同步改为二维码接触匹配后的局域网或设备热点直连；新增设备身份、Epoch/事件密钥、每设备 hash 链、因果合并、双方状态冲突确认和换机撤销规则。
- 原因：项目当前目标是不引入云端内容，数据只在两台机器之间同步；服务端状态版本冲突无法表达离线事件分支和端到端密钥边界。
- 影响文件：docs/superpowers/specs/2026-08-21-local-first-p2p-architecture-design.md、docs/02-technical-design.md、docs/03-roadmap.md、docs/04-decisions.md、docs/README.md。
- 迁移影响：新 P2P 首版从新建 Workspace 开始，不自动导入现有 PostgreSQL 任务；旧服务端实现保留为 Phase 0-3 历史基线，不进入新客户端运行时路径。
- 验证命令与结果：P2P 规格自审通过，规格文件无 TODO/TBD/待定/未决占位；git diff --check 通过；实现计划已完成接口依赖自审和占位符扫描。
- 下一步：架构规格已获确认；实现计划已创建，待选择 Subagent-Driven 或 Inline Execution 后开始 Task 1。

## 文档变更规则

### 2026-08-26 - Lightweight action-first Tasks 2-6

- 范围：延期、评论、活动、统一 Web/Android 模型与同步写入、列表/看板/我的任务界面、双用户验收入口。
- 契约：固定五状态；客户端不离线写入；无附件、依赖图、自定义工作流或新增层级；本轮无数据库迁移。
- 验证：Web 42 tests、typecheck、Vite build 通过；Flutter analyze 与 12 tests 通过；后端 compileall 通过。PostgreSQL pytest 与真实双用户 smoke 未运行，当前环境缺少 pytest/数据库服务；APK 未在本轮重新构建。

- 新方案先写入对应规格或决策文档，再进入代码实现。
- 设计变化必须说明：变更原因、影响范围、替代方案、是否需要迁移，以及对验收标准的影响。
- 每个实施任务完成后，更新本文的状态、测试命令和验收结果。
- 测试失败、环境阻塞和未完成项必须如实记录，不用“已完成”掩盖。
- 代码提交信息应能对应一个文档中的实施任务或文档变更。

## 记录模板

```markdown
### YYYY-MM-DD - [任务或变更名称]

- 类型：实施进度 / 设计变更 / 验收 / 阻塞
- 变更：
- 原因：
- 影响文件：
- 验证命令与结果：
- 下一步：
```
