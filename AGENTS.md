# AGENTS.md

本文是后续 Codex Agent 接手 Muyu 时的工程入口。它记录当前有效的产品目标、运行时架构、不可变业务规则、工作区状态和下一步任务。若本文与代码或状态文档冲突，先停止扩展功能，完成差异审计并更新状态文档。

## 项目目标

Muyu 是 Android 优先、面向两个人的日常协作产品。正式用户使用真实手机号和真实 Workspace 身份；不是通过模拟身份切换来演示双方。

产品要同时支持：

- 共同管理事项、一级子任务和重要事项；
- 明确唯一负责人、当前应回应的人和下一步；
- 记录开始、阻塞、转交、延期、验收、退回、完成、取消和重开等协作事实；
- 通过另一位成员的验收完成任务闭环；
- 用“此刻”、四象限和日程从不同角度查看同一份任务数据；
- 提供共享记账、个人打卡、纪念日和纪念日准备事项；
- Android 与 Web 使用同一套 API、权限、事务和同步事实。

产品不使用积分、排名、惩罚、羞辱、焦虑式排序或绩效看板。页面优先回答：谁负责、现在轮到谁、下一步做什么、结果是否已被确认。

### 当前权威文档

按以下职责和优先级理解当前项目，不能用旧实现限制覆盖最新目标，也不能将目标当作已完成事实：

1. [Muyu-Codex-Design-and-Implementation.md](./Muyu-Codex-Design-and-Implementation.md)：用户指定的最新架构与产品设计基线（设计交付 v1.0，原型 v4）。已确认的产品行为优先；工程建议适配现有技术栈；未指定事项不冒充已确认。
2. [v1 契约与交付设计](./docs/superpowers/specs/2026-09-16-muyu-v1-contract-and-delivery-design.md)：基线到现有工程的状态、字段、导航、新领域与兼容适配；第 6 节的待细化项是施工前置条件。
3. [v1 分阶段实施计划](./docs/superpowers/plans/2026-09-16-muyu-v1.md) 与 [差异清单](./docs/architecture/2026-09-16-muyu-v1-gap-assessment.md)：批次依赖与验收编号；勾选必须对应真实证据。
4. [开发状态](./docs/05-development-status.md)：已实现、测试、部署和未完成项的事实依据，不覆盖最新产品目标。
5. [产品需求](./docs/01-product.md)、[开发路线](./docs/03-roadmap.md)、[设计决策](./docs/04-decisions.md)：最新基线的工程摘要和决策索引。
6. `docs/superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md` 及 2026-09-01 单负责人、2026-09-02 账户设备、2026-09-10 单人起步规格：现有运行时兼容依据；被后续规格明确替代的条款不重新启用。

`docs/02-technical-design.md`、旧 Phase 0-3 计划以及 Local-first P2P 规格主要用于理解历史资产。它们不能重新启用固定共享密码、旧 `WAITING` 状态、旧参与人模型或 P2P 作为当前实现依据。

实现进度和验收证据必须同步写入文档，不能只存在于聊天记录或 Git 提交中。

## 技术栈

### 后端

- Python 3.12；`backend/pyproject.toml` 要求 `>=3.12,<3.13`；
- FastAPI、Uvicorn；
- SQLAlchemy 2.0、Alembic、PostgreSQL 16、`psycopg`；
- Pydantic Settings；
- `cryptography`、`phonenumbers`；
- pytest、HTTPX；
- SMS OTP 认证、移动设备会话、Web QR 临时会话和 Workspace 成员关系；当前生产认证不是密码/JWT 登录。

### 客户端

- Flutter / Dart 3.13，Material 3，主要用于 Android；
- `flutter_secure_storage`、`http`、`crypto`、`mobile_scanner`、`shared_preferences`；
- Android 交付 APK/AAB；
- 独立 Web 客户端使用 React 19、TypeScript、Vite、Vitest、Playwright、`lucide-react` 和 `qrcode`；
- 首版只交付 Android 与 Web。iOS 只保留未来协议兼容空间，不进入当前构建、发布或验收；不开发 Linux 桌面客户端。

### 工程与部署

- Docker Compose、GitHub Actions、Caddy；
- Python 基础镜像使用 `m.daocloud.io/docker.io` 镜像源；
- PostgreSQL、API、Web/Caddy 和备份服务按 Compose 拓扑部署；数据库只在内部网络暴露；
- API 由环境变量配置，Android 通过 `API_BASE_URL`/构建参数配置，Web 通过构建环境配置；
- 所有密码、OTP pepper、SMS provider key、数据库凭据、签名材料和生产 Token 只由部署 Secret 注入；不写入仓库、文档、测试输出或日志。

## 架构原则

### 云端协调模块化单体

PostgreSQL 是共享协作事实源。FastAPI 保持模块化单体，不拆微服务：

```text
backend/app/
├── auth/       # SMS OTP、移动会话和认证依赖
├── workspaces/ # Workspace、成员、分类、bootstrap
├── devices/    # Android 设备状态与管理
├── web_login/  # Web QR 登录和临时会话
├── tasks/      # 任务、状态、审批、评论、延期、冲突
├── home/       # 此刻 Home 投影和入口分页
├── sync/       # snapshot、cursor changes 和缓存边界
├── realtime/   # 事务提交后的 WebSocket 失效通知
├── recovery/   # 设备/会话恢复能力
├── audit/      # 追加式审计事实
├── db/         # ORM、数据库会话、UTC 类型和迁移
├── httpapi/    # 鉴权依赖、统一错误契约
└── core/       # 配置、日志和基础设施
```

未来新增 `ledger`、`checkins`、`anniversaries` 时，沿用相同的 Workspace、仓储、领域服务、事务和同步边界，不另造本地事实源。

### 分层职责

- 路由只负责 HTTP 输入输出、鉴权依赖和领域错误映射；
- Pydantic schema 负责请求/响应契约和边界校验；
- 领域服务负责状态迁移、权限、版本、幂等和事务边界；
- 仓储负责查询和持久化细节；ORM 模型不承担 HTTP 逻辑；
- Android/Web Repository 负责 REST/JSON、snapshot、changes 和错误解析；
- Controller/应用状态负责同步、页面状态、重试和错误保留；
- Screen/React 页面负责交互和展示，不直接改写 owner、status 或服务器事实。

### 事实、事务和审计

每个业务写命令必须在同一个数据库事务中完成：

- 校验当前 Workspace 成员、权限和期望版本；
- 更新业务实体和版本；
- 写状态/负责人/审批/评论/延期等历史或不可变记录；
- 写 `TaskOperation`、`ActivityEvent` 或对应领域事件；
- 分配并写入单调递增的 Workspace cursor；
- 写入幂等结果后提交。

不能出现任务或账目已写入但活动、审批、cursor 或幂等记录缺失的情况。活动记录是追加式事实，客户端不能编辑或删除历史。

### 统一任务源和同步

- 清单/此刻、四象限、日程、全部事情和详情都从同一任务集合派生；不得复制三套任务数据或为每个视图建立独立仓库；
- snapshot 建立完整权威视图，`changes?after_cursor=` 按 cursor 顺序追赶；cursor 过期、缺口或重复时回拉 snapshot；
- WebSocket 只发送“有更新”的 cursor 提示，不承载业务正文；REST snapshot/changes 才是正确性路径；
- Android 可读取最后一个有效快照，但当前协议不允许离线提交；Web 不能用 `localStorage` 冒充双方同步或真实身份；
- 写请求必须带幂等 request/idempotency key，涉及已有实体的写请求必须带期望版本；超时只能用原 key 查询或重试；
- 拉取失败保留 last-known-good 数据并标记 stale，不能清空任务、表单或草稿。

### 测试驱动

功能和缺陷修复遵循：

1. 先写能够表达契约的失败测试；
2. 运行测试，确认失败原因是预期缺口；
3. 实现最小生产代码；
4. 运行专项测试；
5. 运行后端、Flutter、Web 和相关迁移/构建回归；
6. 更新实施计划和 `docs/05-development-status.md`；
7. 再提交与任务对应的变更。

文档同步或纯审计可以不新增生产测试，但仍要运行适合的静态检查并如实记录未执行的验证。

## 不允许改变的设计决策

### 身份、Workspace 和认证

- Workspace 最多两名 `ACTIVE` 成员；它是当前两人关系边界，不得扩展成通用 Team、Organization、多人协作、RBAC 或多级审批系统；
- 使用真实手机号、真实成员关系和服务端鉴权；不保留模拟身份切换作为生产路径；
- 手机短信 OTP 成功后建立/恢复 Android 设备和移动会话；Web 只能通过已授权 Android 设备的 QR 流程获得临时会话；
- 未激活或被撤销的设备不能写入；当前设备不能撤销自己，其他设备撤销必须二次确认；
- `display_name` 可修改；手机号、用户 ID、头像身份和设备公钥等不可由普通业务接口修改；头像继续使用默认 `CircleAvatar`，除非另有正式设计；
- 当前运行时没有默认共享密码。历史测试或旧 `.env` 示例中的密码字符串不是生产登录契约，不要在新代码、文档、日志或回答中传播凭据。

### 任务和负责人

- 每个任务只有一个 `current_handler_id`；不新增 `participants`、共同负责人或第二个 owner 字段；
- 当前负责人和“下一棒/审批人”是不同概念。交接申请在批准前不能改变负责人；只有目标成员批准后才原子变更负责人并写负责人历史；
- 同一 Workspace 的 ACTIVE 成员按当前读取契约可读取全部未删除任务和子任务；非负责人修改受保护字段必须走既有审批流程；
- 子任务仍使用 Task 模型，最多一级；父任务和子任务状态独立；
- `labels` 目前是兼容字段，但新任务只能有一个已批准分类；不恢复多标签写入，也不重新生成系统“默认”分类；
- 创建任务省略截止时间时，按当前服务端契约生成默认截止时间；修改已有截止时间必须遵守延期/版本规则，不能通过普通 PATCH 偷改业务事实；
- 任务完成没有单人例外：没有另一名有效审批人时不能伪造验收或直接进入完成。

### 当前任务状态和审批

当前 API、数据库和同步契约使用以下六个内部状态：

```text
TODO
IN_PROGRESS
BLOCKED
REVIEW
DONE
CANCELLED
```

当前允许迁移：

```text
TODO        -> IN_PROGRESS / BLOCKED / CANCELLED
IN_PROGRESS -> BLOCKED / REVIEW / CANCELLED
BLOCKED     -> IN_PROGRESS / CANCELLED
REVIEW      -> DONE / IN_PROGRESS / CANCELLED
DONE        -> TODO / IN_PROGRESS / CANCELLED
CANCELLED   -> TODO / IN_PROGRESS
```

- `REVIEW` 是任务状态；`TaskApprovalRequest` 的 `PENDING/APPROVED/REJECTED/CONFLICTED/CANCELLED` 是独立请求状态，不能互相替代；
- 负责人提交验收时，服务端在同一事务内进入 `REVIEW` 并创建唯一待处理验收请求；另一位 ACTIVE 成员批准后才进入 `DONE`；退回必须有原因并回到 `IN_PROGRESS`，负责人不变；
- `HANDLER_TRANSFER` 待处理时 owner、任务分组和任务状态不变；审批后才应用 proposed handler；
- `BLOCKED` 必须保留非空阻塞原因和有效恢复负责人；解除后进入 `IN_PROGRESS`，保留阻塞时长和活动事实；阻塞任务不能绕过状态机直接交接或验收；
- `CANCELLED`、重开和旧兼容路径属于当前运行时契约。v1 产品文档里的五种概念状态不能直接替换现有六状态，必须先写独立迁移和兼容计划；旧 `WAITING` 只能作为历史兼容映射到 `BLOCKED`，不能重新作为新状态使用；
- v1 用户填写的明确下一步已通过可空 `next_step_text` 持久化并接入 snapshot/changes、查询及 Android/Web 创建/编辑；现有 viewer-aware `next_step` 仍是行动投影。交接用 `proposed_next_step`，接受时与负责人原子应用，拒绝保留原文；客户端契约 header 强制和交接拟议值尚未实现。
- 新建给 TA 必须先由创建者负责并原子创建交接请求；新 v1 创建映射 IN_PROGRESS，旧 TODO 创建需兼容。解除阻塞不改负责人；恢复负责人旧路径须审计，不能绕过交接。
- 目标标题/下一步/操作说明/补充说明长度为 70/90/500/1000 Unicode code point；当前更长旧字段不截断。无截止日期、时区、旧写入窗口与新领域同步按契约第 6 节补齐设计后施工。

### v1 产品信息架构（目标，尚未全部实现）

目标底部 Tab 固定为：`事项 / 记账 / 打卡 / 我的`。

- `事项` 内部包含清单“此刻”、四象限和日程；三者是同一任务源的视图，不是三个底部 Tab；
- 视图切换放在标题菜单中，不恢复独立常驻切换栏、顶部品牌宣传横幅或头像账号栏；
- “此刻”按 `卡住的事情 / 我在推进 / TA 在推进` 三段互斥展示未完成任务；任务在一个此刻页面中只能出现一次；
- 三个入口指标分别统计“需要我处理、等对方、本周到期”；前两项只统计等待接棒/验收的下一棒，不含普通进行中或分类/字段审批。现有 Home canonical 口径已收敛，旧广义审批字段继续兼容；本周按统一业务时区周一至周日，当前服务端使用 UTC，时区方案尚需细化；
- 开放集合为未删除的 TODO/IN_PROGRESS/BLOCKED/REVIEW；DONE/CANCELLED 从未完成投影移出但保留历史。全部事情从此刻和我的进入，搜索名称/分类/负责人/下一步，支持未完成、全部、阻塞、验收、接棒、完成筛选和来源恢复；
- 标题菜单选项是清单/四象限/日程，标题是此刻/四象限/日程；点当前项不重置，支持返回/外部点击/键盘与焦点恢复，会话内保留各自滚动、筛选和日期状态。四象限重要/紧急为用户属性，适配现有 quadrant，不按到期自动改变；
- Android/Web 壳层已切换为 v1 `事项 / 记账 / 打卡 / 我的`，事项视图放在标题菜单；Android 记账/打卡使用已上线的生活领域 REST API，Web 对生活领域仍显示未开放。真实设备视觉验收和完整来源筛选尚未完成，不能把目标基线写成整体完成。

### v1 辅助领域边界

记账、打卡和纪念日是独立领域，不能复用任务表、浏览器本地存储或假数据替代：

- 记账金额用整数分保存，默认人民币；支出/收入、付款/收款人和记录人分开；月度汇总不因明细筛选而改变；不做 AA 清算、欠款结算、多币种或银行接入；
- 打卡 Tab 保留日常打卡/纪念日，默认我的，可查看 TA 的/全部，不改名为“重复”。习惯由一个本人负责，频率只支持每日/每周/每月；同一习惯同一周期唯一一条有效打卡；只有本人能打卡、撤销、编辑、暂停、恢复或删除，对方只能查看；未到开始日期或暂停不可打卡，撤销只影响本期。确认删除习惯需说明关联打卡记录一起删除，业务删除与不可变审计分开；
- 纪念日按公历计算，保留原始日期和准备天数；2 月 29 日非闰年取 2 月 28 日，未来原始日期不得提前发生；双方可查看编辑。手动生成准备事项以 `anniversary:{id}:{occurrenceDate}` 去重，生成者负责、初始 IN_PROGRESS、截止本次日期；删除/修改纪念日不删除或改写既有任务，不实现自动周期生成或 Push；
- 以上模块已有 [本地施工规格](./docs/superpowers/specs/2026-09-17-life-domains-contract.md)、计划、`0016_life_domains` 迁移、后端/API 专项测试和 Android REST 页面；线上 API 和数据库已于 2026-09-17 升级，Web 生活领域页面、增量客户端整合与双人设备验收仍未完成。

### 时间、视觉和产品边界

- PostgreSQL 时间戳统一使用 UTC；日历日期与时间点分开，周期和“本周”按已确认 Workspace/业务时区计算；客户端按本地时区展示；
- 任务顺序是展示偏好，不是积分、优先级或排名；阻塞时长、截止时间和活动记录只描述事实，不用于责备；
- 不引入 Redis、消息队列、Elasticsearch/OpenSearch、离线写队列、Push 作为首版正确性前提；WebSocket 只能做通知；
- Android 是首要验收端。使用 Material 3 和共享主题令牌，页面紧凑、可扫描、文字状态清楚、图标不能成为唯一含义；不使用营销式大 Hero、嵌套卡片或横向溢出；
- 需检查 320/360/393/412 宽度、键盘、安全区、系统返回、大字体、读屏和减少动态效果；不能只依赖颜色表达状态。

## 编码规范

### 通用

- 开始任何工作先运行 `git status --short --branch`，再读取与目标文件相关的 `git diff`；保留用户已有未提交改动；
- 不使用 `git reset --hard`、`git checkout --` 或其他回退用户修改的命令；不自动推送远端；用户已允许直接在 `main` 上修改；
- 只修改当前需求涉及的模块，不做无关重构；默认 ASCII，现有中文 UI/文档可继续使用中文；注释只解释非显然逻辑；
- 不提交生成缓存、临时脚本、明文凭据、OTP、Token、数据库 URL、私钥或测试输出；不要把 Secret 写入 Markdown；
- REST 写命令使用稳定业务错误码、幂等 key、期望版本和结构化响应；服务端权限不能只依赖按钮是否显示；
- 每个迁移必须有明确 `revision`/`down_revision`，同时验证空数据库升级、回滚和现有数据边界；生产迁移前必须检查线上 head 和备份。

### Python/FastAPI

- 使用 Python 3.12 类型标注；路由使用 Pydantic 请求/响应模型；
- 查询和持久化集中在仓储/领域服务；不要在路由中散落 SQL 或业务状态转换；
- 所有任务、审批、评论、延期、Workspace 和未来账目/打卡写入遵守单事务、审计和 cursor 规则；
- 时间字段使用项目 UTC 类型/明确的 UTC 时间点；不要依赖宿主机本地时区；
- 认证、权限、状态迁移、版本冲突和幂等必须有服务端测试，不能只写客户端测试。

### Flutter/Android

- 使用不可变模型；JSON 解析集中在模型和 Repository；Controller 负责同步、加载、错误和 last-known-good 数据；Screen 只负责交互/展示；
- API 失败时保留表单输入、对话框和当前快照；不能先乐观修改 owner/status 再静默回滚；
- 使用 Material 3、`MuyuThemeExtension`/现有主题令牌和熟悉的 Material 图标；不在页面散落旧颜色、任意圆角或阴影；
- 任务动作必须由服务端返回的可执行事实驱动；不能让客户端绕过审批或状态规则；
- 检查手机窄屏、横向溢出、键盘、返回键、安全区、长标题、大字体、无障碍语义和减少动态效果。

### Web

- 使用 React/TypeScript/Vite 现有目录和 API 类型；保留未提交的 Web 原型/实现文件，先读 diff 再合并；
- Web 优先消费 canonical Home、snapshot 和 cursor 契约；不能继续把已废弃字段当唯一数据源；
- QR 登录使用真实 Android 授权会话；不能增加浏览器密码登录、模拟身份或 localStorage 伪造生产同步；
- 共享业务规则必须由服务端保证，Web 只做展示和输入校验；宽屏布局也要覆盖窄视口与键盘/无障碍场景。

### 文档、计划和提交

每个实施任务完成后：

- 更新对应 `docs/superpowers/plans/` 的复选框；
- 更新 `docs/05-development-status.md`，写明真实命令、结果、环境、未完成项和限制；
- 更新相关规格或运行手册，尤其是迁移、部署、备份和用户操作边界；
- 提交信息与实施任务对应；未执行的真机、线上、发布或视觉验收不能写成已通过。

### 常用验证命令

在拥有所需 Docker/PostgreSQL、Flutter 和 Node 环境时按风险执行：

```sh
make backend-test
make client-test
make web-test
make web-build
make verify
git diff --check
```

`make verify` 还会执行迁移、部署拓扑、旧运行时和客户端边界检查；环境不可用时要记录具体阻塞，不要用更弱的命令冒充全量验收。Android 调试包使用 `make client-build API_BASE_URL=...`，正式 APK/AAB 必须走受保护的 release 流程。

## 当前开发进度

文档基线同步日期：2026-09-17；本地生活领域验证见下，真实设备/线上证据仍沿用此前记录，未重新验收。

### 已完成并应复用

- 云端协调架构 Tasks 1-15、Android/Web 客户端边界 Tasks 1-8、Workspace bootstrap、成员/设备/会话、SMS OTP、Web QR 登录和恢复路径；
- PostgreSQL/Alembic 本地和线上迁移 head 均为 `0016_life_domains`；生产升级前备份和隔离恢复/回滚演练证据见开发状态。任务参与人模型移除、单负责人约束、六状态、审批、评论、延期/阻塞、冲突、活动和 cursor/snapshot/changes；
- 单分类契约和 `0013_remove_default_classification` 已完成本地代码、迁移、客户端和测试收口；线上已从先前的 `0014_moment_home_indexes` 升至 `0016_life_domains`；
- `GET /api/v1/home` canonical 元数据、互斥 `moment.blocked/mine/other`、`entry_counts`、入口 keyset 分页，以及按 viewer 派生的任务详情“下一步”；
- 交接说明、验收内容、退回原因、活动 payload、审批与任务状态分离、snapshot/cursor 连续性、Web canonical Home 消费和双人协作自动化 E2E；
- Android 当前的清单/此刻、四象限、日程、任务详情、审批、账户、设备、扫码和主题令牌化视觉系统；Web 当前的任务工作台和 canonical Home 兼容消费；
- `v0.2.0` APK 发布记录，以及按 commit 命名的本地调试 APK 构建流程。

### 最近记录的验证证据

以下是本地最近的验证证据，完整限制见 `docs/05-development-status.md`：

- Flutter：2026-09-17 全量 `227 passed`，Dart format、`flutter analyze` 和 `git diff --check` 通过；
- Web：此前本地 Vitest `274 passed`、typecheck 和 Vite build；本次生活领域未修改 Web，不代表新领域 Web 验收；
- 后端：暂停习惯编辑修复后 PostgreSQL 全量 `285 passed, 3 skipped, 2 warnings`；生活领域专项 `5 passed`；
- Android：本地 debug APK `client/build/app/outputs/flutter-apk/Muyu-26a51c9.apk` 已重新构建并验证归档和 API origin；最新 checksum 见状态文档。2026-09-17 线上 API/Web 与数据库已更新到 `0016_life_domains`，新领域路由未授权请求返回 401；真实账户、Android 真机、双人端到端与正式签名发布仍未验收；
- 真实 Android 设备安装、截图对比和双设备人工验收仍没有授权设备证据，不能标记为完成；线上 API/Web 没有因最近 Android 视觉重构而改动。

### v1 接手差异

2026-09-16 已收到 `Muyu-Codex-Design-and-Implementation.md` 并完成差异审计。当前工程已具备认证、Workspace、任务审批、事务、同步和 Android/Web 基础，但以下 v1 目标仍未完成：

- 四入口与事项标题内切换已在 Android/Web 本地实现，待 Android 真机和 Web 窄屏验收；
- “全部事情”的完整搜索、状态筛选、历史归档和来源页面恢复；
- 明确下一步的交接拟议值、客户端契约 header 强制和创建给 TA 原子交接；`next_step_text` 字段及 Android/Web 新建/编辑已部分完成；
- 本地记账、打卡、纪念日的后端/API 和 Android 页面已局部施工；仍缺 Web 页面、完整并发/时区/恢复测试及上线验收；
- v1 全部模块的 Android/Web/API/PostgreSQL 双人验收、迁移、备份、重启持久性和发布门禁。

### 当前工作树注意事项

本次更新前工作区已经有用户未提交内容，包括 `docs/05-development-status.md`、`Muyu-Codex-Design-and-Implementation.md`、`docs/architecture/2026-09-16-muyu-v1-gap-assessment.md` 、v1 契约规格、v1 实施计划和若干 `docs/design-reviews/` HTML。后续 Agent 必须先读这些 diff，和它们一起工作，不能删除、重置、格式化覆盖或擅自提交无关文件。

## 后续任务

按以下顺序推进；每一阶段都先写/更新规格和实施计划，再施工。

### 0. 收口当前 Android 交付证据

- 在有授权的真实 Android 设备上安装当前 commit-named APK，检查登录、Workspace、刷新、返回、键盘、安全区、窄屏、大字体和任务操作；
- 以 393×851 为参考完成 320/360/393/412 宽度的视觉检查（390×844 旧截图可补充），记录截图或明确记录设备不可用；
- 若发现问题，先写失败 widget/集成测试，再修复并重新运行 Flutter 全量门禁；
- 不把没有真实设备的情况写成物理机通过。

### 1. 细化现有 v1 实施计划的兼容前置项

- 以 `Muyu-Codex-Design-and-Implementation.md` 和 gap assessment 为产品基线，确认每个目标与现有 API/数据的兼容边界；
- v1 规格和实施计划已建立；按契约第 6 节细化日期/时区、新建即交接、长度/旧客户端兼容、新领域同步与旧操作边界，不能把文档方案当作已实现 API；
- 将当前六状态与 v1 概念状态分开记录，未经迁移计划不要删除 `CANCELLED`、重开或历史兼容路径；
- 把实施拆成可独立回归的计划，不把记账/打卡/纪念日当作纯 UI 任务。

### 2. 完成事项导航和阅读体验

- 四 Tab 目标壳层已在 Android/Web 本地实现，待真实设备与窄屏人工验收；
- 将清单、四象限、日程改为事项标题内的三个视图，保留各自滚动、筛选、月份和选中日期状态；
- 补齐此刻三指标、三段互斥分组、全部事情搜索/筛选/归档入口和任务详情来源恢复；
- 继续复用同一任务源、权限、审批和 cursor，不复制任务或把客户端缓存当事实源；
- 为 Android、Web、API 和无障碍行为增加契约测试，并在迁移期间保留必要的旧字段兼容。

### 3. 收口任务协作 v1 契约

- 补齐明确下一步的交接拟议值、客户端契约 header 和创建给 TA 原子流程；保持已实现的创建/编辑/API/同步字段契约，确保交接拟下一步、当前下一步和历史事实不混淆；
- 保持单一 `current_handler_id`、交接审批、验收审批、阻塞原因、退回原因、活动记录和幂等/版本规则；
- 验证单人起步、第二名成员加入、共享分类审批和“无审批人不能完成”的边界；
- 用双用户 PostgreSQL E2E 覆盖创建、交接、拒绝、验收退回、再次提交、通过、阻塞恢复、刷新和 cursor 重放。

### 4. 实现共享记账

- 新增独立 schema、Alembic 迁移、Repository、领域服务、REST API、Android/Web 页面和权限测试；
- 金额用整数分保存，支持月份、收支筛选、分类汇总、付款/收款人和二次确认删除；
- 保证增改删、月度汇总、并发、幂等、审计和重启后持久性，不与任务完成/验收混用。

### 5. 实现打卡与纪念日

- 打卡实现每日/每周/每月周期、周期唯一约束、本人操作权限、撤销本期、暂停/恢复和历史保留；
- 纪念日实现公历下一次日期、闰年边界、准备天数、查看范围和稳定 source key；
- 生成的准备事项进入同一任务协作闭环，双方并发生成最多一条；删除纪念日不能删除已生成任务；
- 为跨日、跨周、跨月、夏令时/时区和 2 月 29 日注入可控时钟测试。

### 6. 完成跨端、部署和发布门禁

- 在干净 PostgreSQL 上验证所有迁移、回滚/恢复策略、索引、数据不变量和现有数据升级；
- 运行后端全量测试、Flutter format/analyze/test、Web typecheck/test/build、客户端边界和旧运行时检查；
- 验证 API 重启后任务、审批、活动、账目、打卡和纪念日无丢失、无重复，cursor 可继续；
- 生成 Android debug APK 和受保护流程的正式 APK/AAB，检查 API origin、签名、归档和 checksum；
- 完成 Android 真机、Web 窄视口、无障碍、弱网/超时/重复提交和双用户 smoke；
- 更新 `docs/05-development-status.md`、相关计划、运行手册和发布清单；未执行的项目必须明确写为 pending。

### 完成标准

在声称 v1 或某个阶段完成前，必须有新鲜证据证明：

- 产品行为、API、数据库、Android、Web 和同步契约一致；
- 后端、Flutter、Web、迁移、构建和双人 E2E 通过；
- 真实设备/线上/发布类验收均有对应证据，不能用单元测试替代；
- 事务、活动、审批、幂等、cursor 和数据恢复边界无缺口；
- 文档、计划、工作区状态和产物记录已同步，且没有遗留测试半成品、临时文件或明文凭据。
