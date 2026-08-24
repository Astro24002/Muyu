# 云端协调双人协作架构设计

## 1. 状态、范围与替代关系

本规格定义本项目新的运行时架构：云端保存明文协作数据并协调在线写入，Android 与 Web 通过同一套 API 和同步协议协作。

本规格已经过产品决策确认，是后续实施计划和代码改造的唯一架构依据。它取代 2026-08-21 的 Local-first P2P 双人同步架构作为运行时设计；旧 P2P 文档保留为历史记录，不再约束新实现。

本阶段只实现 Android 客户端和 Web 客户端。协议和服务端模型不应依赖 Android 专有字段，以便未来增加 iOS，但 iOS 不属于本规格的构建、发布、测试或验收范围。

本规格同时取代下列旧运行时假设：

- 两台设备本地 Event Store 是任务事实源；
- P2P、局域网、热点、二维码传输或端到端加密事件流是同步路径；
- 两名固定用户、共享密码和启动时种子账号是认证模型；
- PostgreSQL 仅作为旧阶段历史实现；
- 双方必须共同签名才能解决每一个任务状态冲突；
- 客户端允许离线追加并在以后合并事实。

后续实施从新 Workspace 和新数据库模型开始。不迁移旧 Phase 0-3 数据，也不保留旧 P2P 或旧后端任务运行时作为兼容路径。代码删除和数据库初始化属于实施计划中的受控改造，不由本规格执行。

## 2. 产品目标与明确边界

目标是建立一个最多两人共同使用、在线优先的任务协作系统：

- 每个用户由手机号唯一标识；
- 每个用户首版只可属于一个活跃 Workspace；
- 每个 Workspace 最多有两名正式成员，权限完全对等；
- 用户可以拥有多个长期 Android 设备；
- Android 和 Web 能看到同一份任务、评论、延期和活动历史；
- 云端是明文任务事实源，并以事务和版本规则协调并发写入；
- 浏览器只能经用户自己的已批准 Android 设备扫码授权；
- 服务端不支持离线提交，网络不可用时缓存只能查看且必须标示为可能过期；
- 任务删除为软删除，任务和活动历史可审计、可恢复。

首版不包含：

- iOS 客户端、IPA、TestFlight 和 iOS 专项验收；
- P2P、Nearby、局域网发现、设备热点或本地事件同步；
- 端到端任务内容加密、云端密文中继、设备密钥封装和 Epoch 密钥；
- 离线写入队列、离线冲突合并或本地事实源；
- 永久物理删除任务、评论或活动历史；
- 多 Workspace 切换、第三位成员、组织、团队或 RBAC；
- Elasticsearch、OpenSearch、消息队列或 Redis 作为首版必需依赖；
- Web 端短信验证码直接登录；
- 旧数据库数据迁移、导入或兼容 API。

## 3. 选定架构

### 3.1 总体拓扑

    Android App                  Web App
        |                            |
        +------ HTTPS / WSS ---------+
                     |
              Reverse Proxy
                     |
        FastAPI Modular Monolith
          |       |       |
       REST API  WebSocket  Background-safe publisher
                     |
                PostgreSQL

PostgreSQL 是 Workspace、成员关系、设备授权、任务当前状态、操作历史、冲突记录、活动历史和同步游标的唯一事实源。所有任务内容可以以明文存储于 PostgreSQL。

FastAPI 采用模块化单体而不是微服务。任务写入、权限验证、幂等检查、字段冲突记录、活动记录和 Workspace 游标必须位于同一个数据库事务中，因此首版不引入跨服务协调。

Web 前端作为独立静态应用发布，Android 和 Web 复用同一后端 API、同一权限规则、同一 Workspace cursor 和同一冲突语义。当前 Android 交付物为 APK（调试、内测或侧载）和签名 AAB（商店发布）；Web 交付物为静态前端构建。二者必须进行互操作验收。未来 iOS 只能作为新的客户端接入相同协议，不能建立独立的数据模型或同步语义。

### 3.2 服务端模块边界

    auth/          短信验证码、移动端会话、限流和注销
    users/         手机号用户与资料
    devices/       长期移动设备登记、审批、撤销和恢复
    workspaces/    双人成员关系、邀请、游标和授权边界
    web_sessions/  扫码挑战、Web 会话、撤销和 Cookie
    tasks/         当前状态、字段版本、生命周期和软删除
    operations/    追加式任务操作、幂等结果和增量变更
    conflicts/     同字段与生命周期冲突的记录和解决
    comments/      不可修改的评论
    activity/      追加式审计和展示历史
    realtime/      WebSocket 会话与提交后变更通知

模块只通过明确的应用服务和仓储边界通信。任务领域代码不直接操作 WebSocket；实时模块只在已经提交的事务之后发送通知，永远不决定任务事实。

### 3.3 放弃的方案

- 设备端服务或 P2P：隐私和基础设施成本较低，但设备在线、网络切换、后台执行和异地可达性会让同步体验不稳定；不适合本期在线协作目标。
- 云端密文中继：可保护服务端不见明文，但会显著增加 Web 编辑、设备恢复、密钥生命周期和冲突处理复杂度；产品已确认不需要任务内容端到端加密。
- 微服务和 ES：当前双人规模下增加部署、事务和运维复杂度，不提供相应收益。

## 4. 身份、成员与设备模型

### 4.1 用户与 Workspace

User 由不可重复的手机号标识。首版没有密码登录；手机号验证码是 Android 账户会话的唯一登录方式。用户资料不等同于 Workspace 权限，登录成功也不自动获得任何共同空间数据。

Workspace 最多有两个 ACTIVE 成员。首版一个用户只可拥有一个 ACTIVE Workspace，服务端通过约束防止成员关系串联到多个空间。两个成员在任务查看、创建、编辑、完成、删除、恢复、评论、延期、冲突解决和成员设备审批上权限对等。

首次建立共同空间的流程：

1. 用户 A 在自己的 Android 设备上通过短信验证码登录，并创建第一个 Workspace；该设备作为 A 的初始长期设备激活。
2. A 输入用户 B 的手机号创建邀请。B 可以尚未注册。
3. B 在 Android 上通过短信验证码注册或登录，设备进入 PENDING 状态。
4. 双方显示相同的一次性安全短码并人工确认；A 的活动 Android 设备批准 B 的申请。
5. 服务端在一个事务中激活 B 的成员关系和首台长期设备，记录审计事件，并使邀请失效。
6. B 绑定到 Workspace 后，可立即用自己的活动 Android 设备扫码登录 Web。

邀请码和安全短码都必须有过期时间、单次使用标志和审计记录。手机号邀请只定位候选成员，不应被视为自动授权。

### 4.2 长期移动设备

Device 是用户的长期移动客户端。首版平台为 ANDROID；数据库以枚举或字符串保留 platform 字段，但不为 iOS 增加客户端逻辑。长期设备有 PENDING、ACTIVE、REVOKED 三种状态。

Android 在首次登录后生成独立的设备授权签名密钥，私钥由 Android Keystore 保护，公钥与设备指纹登记到服务端。该密钥仅用于设备审批、扫码确认、撤销和恢复等高风险授权，不用于加密任务内容。

除创建 Workspace 的 A 首台设备和接受首次邀请的 B 首台设备外，任何新增或替换 Android 设备都必须由 Workspace 中另一位成员的 ACTIVE Android 设备批准。待批准设备可以完成账号登录，但不得读取、写入或订阅 Workspace 数据。审批时两台 Android 设备必须核对一次性安全短码；服务端验证审批设备、候选设备、Workspace 成员关系和请求未过期后，原子把候选设备置为 ACTIVE。

用户可以有多个 ACTIVE Android 设备。它们共享同一用户权限，但每个设备的身份、撤销状态、审计记录和会话均独立。撤销设备后，服务端立即拒绝该设备发起的移动端请求和审批操作，并记录撤销者及原因；不会删除该用户或 Workspace 数据。

### 4.3 设备全部丢失与手机号更换

当两名成员都失去所有 ACTIVE Android 设备时，任何一人都不能单独恢复共同空间。两人必须各自完成短信验证码身份验证，在新 Android 设备上发起恢复，并通过新的安全短码相互确认。服务端随后在同一事务中激活两台新设备、撤销旧设备和全部 WebSession，并写入恢复审计。由于任务内容保存在云端明文，新设备恢复成功后可以直接拉取当前 Workspace 数据。

手机号仍可使用时，更换手机号要求验证旧号码和新号码，并由另一位成员的 ACTIVE Android 设备批准。旧号码不可用时，手机号变更不走单人自助路径，而走上述双人恢复语义：另一名成员必须参与，服务端把新号码验证和成员确认写入同一恢复审计链。首版不提供管理员绕过或客服单人重置。

## 5. 短信认证与移动端会话

短信验证码提供者必须通过可替换接口实现：开发和自动化测试使用受控模拟提供者，生产环境通过部署配置接入正式短信服务商。

验证码规则固定为：

- 六位数字；
- 五分钟有效；
- 成功校验后立即单次作废；
- 按手机号和 IP 分别限制发送与校验频率；
- 日志、追踪、错误消息和审计正文不得记录完整验证码；
- 发送成功响应不得泄露手机号是否已经注册；
- 同一验证码或挑战的并发验证只有一个可以成功。

Android 通过验证码获得短期访问令牌和可撤销刷新会话。刷新会话在数据库中只保存不可逆摘要，并绑定 User、Device、过期时间和撤销状态。移动端凭据保存在系统安全存储中。注销、设备撤销、恢复和风险处置都会使相关会话失效。

Web 不提供短信验证码直接登录。短信登录只能用于 Android 的用户认证和新设备的 PENDING 建立；浏览器进入任何 Workspace 前必须完成扫码授权。

## 6. Web 扫码授权

### 6.1 会话规则

WebSession 是临时浏览器会话，不是长期 Device，不能审批新设备、邀请成员、批准恢复或替代移动设备。它继承当前用户已经拥有的 Workspace 权限。

Web 会话最长 18 小时，不允许静默续期。用户退出、会话到期、服务端撤销，或批准该会话的 Android 设备被撤销后，浏览器必须重新扫码。浏览器不保存 Android 私钥，也不获取任务解密密钥；任务内容由普通受保护的 HTTPS 会话从服务端读取。

只有当前用户自己名下的 ACTIVE Android 设备可以查看和撤销该用户的 WebSession。另一位 Workspace 成员不能撤销对方的 WebSession。当前用户可撤销一个会话或全部自己的 Web 会话；撤销会立即使 Cookie 无效并断开对应 WebSocket。

### 6.2 扫码流程

    Browser creates one-time challenge and browser-held proof
        -> Server returns QR payload, origin and safety short code
        -> User scans with own ACTIVE Android device
        -> Android shows origin and short code; user explicitly approves
        -> Server verifies challenge, device state and same User ownership
        -> Browser exchanges its proof for an HttpOnly Web session cookie
        -> Browser connects with the session and loads Workspace data

扫码挑战有效期为 120 秒、单次使用且只能由创建它的浏览器证明完成。二维码必须包含受签名或不可猜测的挑战引用、扫描随机数、预期站点来源和安全短码，不包含用户会话、移动端私钥或任务内容。

服务端批准时必须验证：挑战未过期且未使用；扫描 Android 设备为 ACTIVE；设备所属用户与将要创建 WebSession 的用户相同；该用户已有 ACTIVE Workspace 成员关系；浏览器来源匹配已登记来源。原浏览器只有证明它持有创建挑战时生成的随机证明值后，才能兑换 Cookie，避免仅扫描二维码的一方劫持浏览器会话。

Web Cookie 必须为 HttpOnly、Secure、SameSite，并采用 CSRF 防护。WebSocket 握手重新校验会话有效性；会话撤销或到期时服务端主动关闭连接。Web 前端采用严格 CSP、受控构建和发布流程，因为前端脚本能访问浏览器中呈现的任务明文。

## 7. 任务事实模型与数据库设计

### 7.1 当前状态加追加式历史

服务端采用当前状态表和追加式操作历史的混合模型：

    tasks                 当前可查询任务状态
    task_operations       每一次领域操作的不可修改记录
    task_conflicts        同字段或生命周期冲突及其解决结果
    task_comments         只新增的评论
    delay_records         只新增的延期记录
    activity_events       面向时间线和审计的追加记录
    workspace_change_log  单调 cursor 的增量同步记录

每个写操作必须在一个 PostgreSQL 事务中完成以下动作：权限和状态校验、幂等检查、更新 tasks、增加相关字段版本、追加 task_operations、追加活动记录、必要时写入 conflict 或 delay record、分配 workspace_cursor、写入 workspace_change_log。事务提交成功后才可以返回写入成功或发送实时通知。

任务、评论、延期原因、活动历史和冲突快照允许以明文保存在数据库。历史和操作记录禁止普通 UPDATE 或 DELETE；应用数据库角色只能通过受限应用路径修改当前状态表。软删除不会物理删除任务或历史。

### 7.2 核心关系

至少应建立以下实体和约束：

    users
      id, phone unique, profile fields, timestamps

    sms_verification_challenges
      phone, code digest, expires_at, consumed_at, rate metadata

    mobile_sessions
      user_id, device_id, refresh digest, expires_at, revoked_at

    devices
      id, user_id, platform, public_key, fingerprint, status, timestamps

    workspaces
      id, next_cursor, timestamps

    workspace_members
      workspace_id, member_slot (must be 1 or 2), user_id, state, timestamps
      unique(workspace_id, member_slot)
      unique(workspace_id, user_id)
      partial unique index for user_id where state is ACTIVE

    workspace_invites
      workspace_id, invited_phone, state, expires_at, audit fields

    device_authorization_requests
      workspace_id, candidate_device_id, approver_device_id,
      safety_code_digest, expires_at, approved_at, revoked_at

    web_login_challenges
      browser_proof_digest, scan_nonce_digest, origin, expires_at, consumed_at

    web_sessions
      user_id, approved_by_device_id, browser session digest, expires_at, revoked_at, audit fields

    tasks
      workspace_id, parent_task_id nullable, current business fields,
      version, field_versions JSONB,
      lifecycle_version, deleted_at, created_at, updated_at

    task_comments
      workspace_id, task_id, author_user_id, body, created_at

    delay_records
      workspace_id, task_id, actor_user_id, original_due_at, new_due_at,
      reason, note nullable, created_at

    activity_events
      workspace_id, task_id nullable, actor_user_id, actor_device_id nullable,
      web_session_id nullable, event type, payload snapshot, created_at

    task_operations
      workspace_id, task_id, actor_user_id, actor_device_id nullable,
      web_session_id nullable, request_id, operation type, before/after,
      base versions, resulting versions, cursor, created_at
      unique(workspace_id, actor_user_id, request_id)

    task_conflicts
      workspace_id, task_id, field or lifecycle target, base/current/proposed,
      request_id, state, resolved_by, resolution, created_at, resolved_at

    workspace_change_log
      workspace_id, cursor, resource type, resource id, operation id, created_at
      unique(workspace_id, cursor)

重要日期、循环任务及其生成的任务实例也属于同一 Workspace 的 PostgreSQL 事实数据。它们的创建、更新、生成、取消与删除必须沿用 tasks 的单事务、追加式历史和 workspace_cursor 规则，而不能引入第二个事实源。

member_slot 必须由数据库检查约束限制为 1 或 2，且 workspace_id 与 member_slot 的唯一性直接保证每个 Workspace 最多有两名成员。仅 ACTIVE 成员的 user_id 部分唯一索引直接保证首版每个用户最多一个活跃 Workspace。数据库细节可以在实施计划中按现有任务字段补全，但不得改变上述事务边界、唯一约束、事实源和追加式历史原则。

### 7.3 删除、评论和活动

删除任务设置 deleted_at 并追加 TaskDeleted 操作和活动记录；默认查询过滤已删除任务。恢复是单独的有版本生命周期操作，任一成员可执行。被删除任务拒绝普通字段编辑、状态修改、评论和延期，必须先恢复。

评论只支持新增和查看。延期必须同时追加 DelayRecord、更新 due_at 以及活动记录。所有任务和协作动作都有活动记录，记录操作者 User、来源 Device 或 WebSession、请求 ID、时间、目标和必要的前后状态；活动历史不能被用户编辑或删除。

## 8. 在线写入、版本与冲突

### 8.1 正式提交语义

客户端操作按以下方式提交：

    User edit
      -> Client reads current task cache and field versions
      -> Client sends request_id, base_field_versions and changed fields
      -> Server validates identity, membership, session/device and task state
      -> One PostgreSQL transaction writes authoritative state and operation log
      -> Server returns ACK, task snapshot and workspace_cursor
      -> Client replaces or reconciles its cache
      -> Server broadcasts workspace.changed after commit

只有服务端 ACK 返回后，操作才算正式提交。网络不可用、权限失效、超时或服务器错误时，客户端不得把修改视为成功，也不得放入本地离线提交队列。若服务端已提交但响应在网络中丢失，客户端必须用相同 request_id 查询或重试；服务端返回第一次处理的结果而不是重复写入。

### 8.2 字段级乐观并发

tasks 同时维护整体 version 和每个可编辑业务字段的 field_versions。客户端提交时只携带自己修改字段的基线版本：

- 所有目标字段的基线仍等于服务端版本时，服务端应用操作；
- 两个并发操作修改不同字段时，两者都可通过检查并自动合并；
- 任一目标字段的版本已改变时，服务端不静默覆盖，创建或返回 task_conflict 并返回 HTTP 409；
- 冲突中保存基线值、当前值、提议值、相关版本、操作者与请求 ID；
- 任一 Workspace 成员可以选择保留当前值，或将提议值作为基于最新版本的新操作提交；解决动作也追加到操作和活动历史。

整体 version 用于缓存和展示失效，不应单独导致不同字段写入冲突。服务端数据库事务必须对目标任务行加锁或采用等价的原子条件更新，避免两个请求同时读取同一个旧字段版本后都写入成功。

### 8.3 生命周期冲突

状态变更、完成、重新打开、删除和恢复使用独立 lifecycle_version。任何生命周期操作都必须携带 expected_lifecycle_version；该版本过期时，服务端记录 lifecycle conflict 并返回 HTTP 409。生命周期冲突不能被后到请求自动覆盖。

普通字段操作不会绕过已删除状态。冲突解决后的写入使用当时最新生命周期版本，因此重复、过期或已经处理的解决请求保持幂等或明确拒绝。新架构不要求两位成员共同签名同一冲突解决结果；任一有权限成员的显式解决操作即可完成。

## 9. 同步读取与实时通知

### 9.1 cursor 增量协议

每个 Workspace 有单调递增且不可回退的 workspace_cursor。任何影响客户端可见状态的已提交事务都获得新的 cursor，并写入 workspace_change_log。客户端本地保存 last_cursor 和可丢弃缓存。

增量读取以 after_cursor 为输入，按 cursor 升序返回变化资源、权威当前快照和新的 cursor。客户端必须幂等处理重复项，并忽略比本地 last_cursor 更旧的响应。若 cursor 不再可用于增量读取，服务端返回明确的 resync_required，客户端获取完整 Workspace 快照后替换缓存并保存新 cursor。

缓存不是事实源。客户端可以在断网时查看缓存，但 UI 必须显示可能过期；不得允许本地写入被标为已提交。

### 9.2 通知、轮询与手动刷新

WebSocket 只发送 workspace.changed 通知，其中包含 Workspace 标识和最新 cursor，不包含任务标题、评论、延期原因或其他业务正文。收到通知的客户端主动使用 REST 增量接口拉取。用户自己的写入成功响应直接含权威任务状态和 cursor，无需等待下一轮通知。

前台 Android 和打开的 Web 页面采用以下同步策略：

- WebSocket 正常连接时，收到通知立即拉取；
- 每 30 秒执行一次增量同步作为通知漏失和连接异常的兜底；
- Android 回到前台、Web 页面恢复焦点、WebSocket 建连或重连时立即同步；
- 用户可手动刷新，立即触发增量同步并显示同步中、最后成功时间、失败原因和重试入口；
- 后台不承诺秒级同步，后续可通过平台推送和系统调度改善，但不改变以 cursor 拉取为准的正确性模型。

数据库提交后才发布通知。通知漏发、重复、乱序或 WebSocket 断开都不能导致数据丢失，因为 REST 增量、30 秒轮询、前台补齐和手动刷新会恢复一致状态。

## 10. API 与服务契约

API 的具体 URL 可以在实施计划中确定，但必须覆盖以下契约：

- 发送和验证短信验证码；
- 移动端刷新、注销和会话撤销；
- 创建、接受、过期和取消 Workspace 邀请；
- 登记 PENDING Android 设备、查询待审批设备、核对短码、批准和撤销设备；
- 创建、扫描、批准、兑换和撤销 Web 扫码会话；
- 读取 Workspace 快照与 after_cursor 增量；
- 任务、评论、延期、软删除、恢复和冲突解决读写；
- WebSocket 的鉴权、订阅和 workspace.changed 通知；
- 使用 request_id 查询或重放未知写入结果。

每个受保护请求都必须同时验证 User 身份、Workspace 成员关系、来源 Device 或 WebSession 的状态，以及目标资源归属。新设备 PENDING、已撤销设备、过期 WebSession、已使用扫码挑战和非成员用户必须获得明确的拒绝结果，不得通过资源存在性泄露对方数据。

## 11. 安全、隐私与运维

任务数据不使用端到端加密，服务端可以读取明文。因此安全边界是 TLS、访问控制、数据库权限、审计、备份保护和前端发布安全，而不是设备持有密钥。

- 所有客户端传输强制 HTTPS 和 WSS；
- PostgreSQL 不暴露公网端口，只允许后端服务网络访问；
- 数据库备份和时间点恢复副本必须加密、限制运维访问并记录恢复审计；
- 生产环境 Secrets 通过部署系统注入，不写入源代码、镜像或文档；
- API、短信、扫码、设备审批和写入接口实施速率限制、过期、单次使用和异常审计；
- 日志、指标和错误上报不得包含任务正文、评论正文、延期原因、验证码、访问令牌、Cookie 或完整会话标识；
- Web 使用 HttpOnly Secure SameSite Cookie、CSRF 防护、严格 CSP 和受控静态资源发布；
- Android 设备授权私钥由 Keystore 保护，撤销后服务端拒绝该设备的授权操作；
- 任务读写、设备审批、恢复、手机号变更、WebSession 撤销、删除/恢复和冲突解决全部写入审计记录。

首版不额外实现复杂的手机号劫持风控。双人设备审批和双人恢复仍是敏感操作的主要约束；这不是对号码本身安全性的保证。

## 12. 搜索与分析边界

PostgreSQL 是首版唯一数据库和唯一事实源。任务、评论和活动搜索需要时使用 PostgreSQL 全文检索与索引，例如 tsvector 加 GIN，以及适当的 pg_trgm 模糊匹配。双人 Workspace 的数据规模不需要 Elasticsearch 或 OpenSearch。

未来只有在跨大量文本、复杂相关性排序或大规模聚合分析已经证明 PostgreSQL 不足时，才可以增加 SearchProjection。该投影必须遵循：

    PostgreSQL transaction
      -> durable outbox
      -> asynchronous indexer
      -> Elasticsearch or OpenSearch read projection

客户端永远只写 PostgreSQL；搜索索引可被完整重建，其故障不得阻塞任务写入、权限判断或同步 cursor。

## 13. 部署、可用性与扩展

首版部署一个 FastAPI 模块化单体、一个 PostgreSQL 实例、一个反向代理和一个静态 Web 前端。FastAPI 除长连接外保持无状态，未来可横向扩展。RealtimePublisher 是可替换边界：单实例可直接发送通知；多实例部署时可以接入 Redis 或等价广播设施。Redis 不进入首版运行时要求。

后端或数据库不可用时，客户端可查看过期缓存，但所有写入必须失败或使用相同 request_id 安全重试。PostgreSQL 自动备份和时间点恢复用于服务故障恢复；恢复流程不得跳过应用审计或误把备份恢复当作客户端离线同步。

## 14. 测试与验收

### 14.1 后端与数据库

- 短信挑战覆盖过期、单次使用、手机号/IP 限流、模拟提供者和不泄露注册状态；
- Workspace 约束覆盖最多两名成员、每用户一个活跃 Workspace、邀请未注册手机号和邀请过期；
- 设备测试覆盖 PENDING 拒绝、他方 Android 审批、撤销、多个 ACTIVE 设备和短码过期；
- 双人恢复测试覆盖两人共同确认、旧设备与 WebSession 失效、单人无法恢复；
- Web 扫码测试覆盖挑战过期、浏览器证明错误、错误用户设备批准、18 小时到期、本人撤销和另一位成员拒绝撤销；
- 任务事务测试覆盖 request_id 幂等、不同字段自动合并、同字段 409 冲突、生命周期冲突、软删除/恢复和审计追加；
- cursor 测试覆盖增量排序、重复项、快照回退、通知漏发和 resync_required；
- PostgreSQL 集成测试验证锁和事务边界，而不仅是 SQLite 行为。

### 14.2 Android 与 Web 集成

- Android A 创建 Workspace、邀请尚未注册的 B、B 短信注册并经短码加入；
- A 与 B 都可在自己的 Android 上扫码登录 Web；
- Android 写入后 Web 收到通知并拉取，Web 写入后 Android 在通知、30 秒兜底、回前台和手动刷新路径下收敛；
- Web 会话在 18 小时到期、退出和本人 Android 撤销后均无法继续 API 或 WebSocket 访问；
- 两端并发编辑不同字段自动合并，同字段显示可操作冲突；
- 缓存可读但断网时不能提交；响应丢失时同一 request_id 不会重复操作；
- Android APK/AAB 构建和 Web 静态构建都通过，Android 与 Web 针对同一服务端运行端到端验收。

### 14.3 迁移与删除验收

- 新部署以空 PostgreSQL 初始化新架构，不导入旧用户、旧任务、旧延期或旧活动；
- 旧 P2P 运行时、旧本地加密 Event Store 和旧固定密码后端代码在实施完成后不再被生产入口、CI 或发布产物引用；
- 不保留双事实源、同步桥接或旧 API 兼容层；
- 删除旧代码前先以版本控制确认精确目标，避免删除无关工程资产。

## 15. 不变量

后续实现必须始终满足：

1. PostgreSQL 是任务及协作状态的唯一事实源；
2. 一个 Workspace 永远不超过两名 ACTIVE 用户成员；
3. 一个用户首版永远不超过一个 ACTIVE Workspace；
4. PENDING 或 REVOKED 设备不能读取、写入或订阅 Workspace；
5. 新增长期 Android 设备必须有另一位成员的 ACTIVE Android 设备批准；
6. WebSession 只能由同一用户自己的 ACTIVE Android 设备扫码批准或撤销，且不超过 18 小时；
7. 服务端 ACK 前客户端修改不算已提交，且不存在离线提交队列；
8. 不同字段并发可以合并，同一字段和生命周期并发永不静默覆盖；
9. 每个成功写入、冲突、审批、撤销、恢复和删除/恢复都有可追溯审计记录；
10. WebSocket 只是通知通道，cursor REST 读取才是同步正确性的依据；
11. ES/OpenSearch 不是首版依赖，也永远不能成为事实源；
12. Android APK/AAB 和 Web 发布物必须连接同一 API、权限和同步协议；iOS 不进入当前发布范围。
