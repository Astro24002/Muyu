# 开发状态与变更记录

本文是工程开发过程的状态入口。每次开始或完成一个阶段、发现验收差异、调整设计方案或改变范围时，必须先更新本文或关联设计文档，再提交代码。

## 当前状态

- 当前阶段：云端协调架构 Tasks 1-15、Android/Web 客户端边界 Tasks 1-8 及 Android 任务导航与刷新交互已实现，`v0.1.3` 已完成 CI 验证并发布；任务参与人模型移除已完成代码与文档收口，后续只剩真实 Android 设备验收和线上数据库迁移。
- 当前产品和运行时设计：[产品需求](./01-product.md)、[移除任务参与人模型设计](./superpowers/specs/2026-09-01-remove-task-participants-design.md)、[云端协调架构规格](./superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md)、[开发路线](./03-roadmap.md)、[已确认决策](./04-decisions.md)。
- 当前范围：只交付 Android 与 Web；Android 需要 APK/AAB，Web 由 TypeScript + Vite 构建静态文件；iOS 留作未来协议兼容，不进入本轮构建、发布或验收。
- 当前数据与同步边界：PostgreSQL 是明文事实源；REST cursor 同步为正确性路径，WebSocket 仅为通知；不允许离线提交；首版不引入 Elasticsearch/OpenSearch。
- 当前任务契约：每项任务只保留一个 `current_handler_id`；同一 Workspace 的两位 ACTIVE 成员可读取全部未删除父任务和子任务；当前负责人可直接写入，非当前负责人的成员写入受保护字段时继续提交给对方审批；“我的任务”只按当前负责人筛选。
- 当前 Android 账户概览：从现有 Workspace snapshot 统计当前用户负责的全部未删除父任务和子任务，并显示任务、完成和延期汇总；匹配对象头像打开另一位 ACTIVE 成员的同口径概览。
- 当前迁移与缓存：Alembic `0005_remove_task_assignees` 校验非删除任务的 `current_handler_id` 必须是同一 Workspace 的 ACTIVE 成员，拒绝静默改写无效负责人；开发迁移会有意删除旧 `task_assignees` 参与人数据和所有已废弃的 `ASSIGNEE_UPDATE` 记录。Flutter 快照缓存命名空间为 `muyu.workspace.snapshot.v2.$workspaceId`，旧命名空间不会作为当前契约读取。
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
- 变更：完成 PostgreSQL 权威数据模型、短信验证码移动会话、双人工作区与设备签名审批、设备恢复/撤销、二维码 Web 会话、任务冲突与幂等、评论/延期/循环/重要日期、cursor 同步和通知型 WebSocket；客户端切换为 Android SMS + Web QR；删除旧密码、JWT、P2P 和旧任务运行时。
- 验证：隔离 PostgreSQL 后端 `37 passed, 1 skipped`；真实 Uvicorn API 云协议端到端 `1 passed`；脚本 smoke、旧运行时检查、Compose 拓扑检查和 shell 语法检查通过；Flutter analyze 与 `17 tests passed`；Android debug APK 和 Web release bundle 构建成功。
- 范围：本轮只交付 Android 与 Web，不生成 iOS 安装包；移动端新设备在已有工作区中先进入 `PENDING`，需另一位成员批准后才成为 ACTIVE。
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
