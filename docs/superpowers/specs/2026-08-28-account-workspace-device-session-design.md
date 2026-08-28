# 账号、双人 Workspace 与设备会话设计

## 1. 目标与边界

本设计解决四个相互关联的问题：

1. 用户第一次用短信验证码登录后，必须绑定另一位共同使用人，不能只创建一个没有伙伴的普通空间。
2. 一个 Workspace 最多绑定两个独立手机号账号，两个账号是成员关系，不合并为一个账号。
3. 每个账号的第一台 Android 设备自动验证；后续设备先只读，必须由另一位成员的已验证 Android 设备批准后才能写入。
4. Web 是短期授权会话，不注册为 Android 设备，不进入 Android 设备数量和设备撤销流程。

首版仍只实现 Android 客户端、TypeScript + Vite Web 和 FastAPI API。短信验证码仍是登录方式；手机号使用 E.164 存储，国内 11 位输入统一补全为 `+86`。服务端继续使用 PostgreSQL 作为事实源。

## 2. 核心对象关系

```text
User (手机号账号)
  └── AndroidDevice (0..N，持久设备)

Workspace (最多两个成员)
  ├── WorkspaceMembership(slot=1, user=A)
  └── WorkspaceMembership(slot=2, user=B)

WebLoginChallenge (一次性二维码挑战)
  └── WebSession (最长 18 小时的临时网页登录会话)
```

两个手机号分别对应两个 `User`。强绑定发生在 `WorkspaceMembership` 和邀请记录上，不通过修改手机号或合并用户实现。

Web 不创建 `AndroidDevice`。Web 登录成功只创建 `WebSession`，因此网页登录不会增加 Android 设备记录，也不会占用设备数量。

## 3. 状态模型

### 3.1 Workspace 状态

对外提供以下业务状态：

- `NEEDS_PARTNER`：账号还没有 Workspace，需要填写另一位用户手机号。
- `WAITING_FOR_PARTNER`：已创建 Workspace，slot 1 已加入，正在等待 slot 2 接受邀请。
- `READY`：两个成员均已加入。

Workspace 仍可使用现有持久化状态 `ACTIVE`/`ARCHIVED`。业务状态由成员数量和待处理邀请派生，不新增不必要的数据库枚举。

### 3.2 Android 设备状态

数据库内部保留生命周期状态：

- `PENDING`：未验证，只读。
- `ACTIVE`：已验证，可读写。
- `REVOKED`：已撤销，不能建立或刷新会话。

API 和 UI 对用户显示为两种主要状态：

- `UNVERIFIED`（对应 `PENDING`）
- `VERIFIED`（对应 `ACTIVE`）

`REVOKED` 仅用于安全控制和审计，可在历史记录中显示“已撤销”，不作为可用设备状态。

规则：

1. 每个用户的第一台设备自动为 `ACTIVE`，与该用户是否已经加入 Workspace 无关。
2. 同一用户的第二台及后续设备为 `PENDING`。
3. `PENDING` 设备可以登录、刷新会话、读取 Workspace 和任务，但所有写接口必须拒绝。
4. 只有另一位 Workspace 成员的 `ACTIVE` 设备可以批准该设备。
5. 当前登录设备不能删除或撤销自己；后端必须拒绝自我撤销请求。
6. 用户可以从“我的设备”撤销自己账号下的其他设备。撤销立即使该设备的移动会话失效。

### 3.3 Web 会话状态

Web 会话使用现有 `WebLoginChallenge` 和 `WebSession` 表：

- 挑战：短期、一次性、默认 5 分钟，成功交换后立即消费。
- 会话：`ACTIVE`、`EXPIRED`、`REVOKED`，最长 18 小时。
- 会话不进入 `AndroidDevice`，不参与 Android 设备审批。
- 任一 Workspace 成员的已验证 Android 设备可以撤销该 Workspace 的 Web 会话。
- Web 会话不能批准 Android 设备、创建 Web 会话或修改成员绑定。

过期和撤销的 Web 会话保留有限审计窗口（默认 30 天），之后由清理任务删除。挑战记录在过期或消费后进入同一清理流程。数据库为 `status + expires_at` 建立索引，避免历史记录无限增长。

## 4. 首次登录与双人绑定流程

### 4.1 用户 A 首次登录

1. A 完成短信验证码验证。
2. 后端创建或加载 `User A`。
3. 若 A 没有设备，创建 `AndroidDevice(A, ACTIVE)`。
4. A 没有 Workspace 时，客户端请求 bootstrap 状态并显示绑定表单。
5. A 输入 B 的手机号。服务端规范化手机号，拒绝与 A 相同的号码。
6. 服务端事务内创建 Workspace、A 的 slot 1 `ACTIVE` 成员和 B 的待接受邀请。
7. 返回 `WAITING_FOR_PARTNER`。A 可以读写任务，但 UI 明确显示等待 B 加入。

### 4.2 用户 B 首次登录

1. B 完成短信验证码验证。
2. 后端创建 `User B` 和 B 的第一台 `ACTIVE` Android 设备。
3. bootstrap 接口按 B 的手机号发现待接受邀请，返回 `INVITED` 状态和邀请摘要。
4. B 确认加入后，服务端事务内创建 slot 2 `ACTIVE` 成员并将邀请置为 `ACCEPTED`。
5. B 进入 `READY` Workspace，不触发设备审批。

如果 B 已经有第二台或后续设备，则该设备仍为 `PENDING`，加入成员和设备验证分别处理：成员加入可完成，当前设备只读，之后由 A 的已验证设备批准。

### 4.3 绑定约束

- 一个用户只能属于一个未归档 Workspace。
- 一个 Workspace 最多两个成员，槽位只能是 1 和 2。
- 一个 Workspace 同时只能有一个有效的 slot 2 邀请。
- 邀请手机号必须等于登录用户规范化后的手机号。
- 已属于其他 Workspace 的手机号不能被绑定，除非先完成明确的退出/恢复流程；首版不提供静默换绑。

## 5. API 合同

### 5.1 Bootstrap

```http
GET /api/v1/workspaces/bootstrap
Authorization: Bearer <mobile-token>
```

响应示例：

```json
{
  "state": "NEEDS_PARTNER",
  "workspace": null,
  "invite": null,
  "device": {
    "status": "VERIFIED",
    "can_write": true
  }
}
```

```json
{
  "state": "WAITING_FOR_PARTNER",
  "workspace": {
    "id": "...",
    "name": null,
    "member_count": 1
  },
  "invite": {
    "id": "...",
    "phone_masked": "+86******0169",
    "status": "PENDING",
    "expires_at": "..."
  },
  "device": {
    "status": "VERIFIED",
    "can_write": true
  }
}
```

```json
{
  "state": "READY",
  "workspace": {"id": "...", "name": null, "member_count": 2},
  "invite": null,
  "device": {"status": "UNVERIFIED", "can_write": false}
}
```

该接口必须使用允许 `PENDING` 设备读取的移动主体依赖，而不是只允许 `ACTIVE` 设备的写主体依赖。只有认证失效、数据库故障或真正的服务错误才返回 `failure`，不能把 `NEEDS_PARTNER` 或 `UNVERIFIED` 转成“无法加载共享空间”。

### 5.2 绑定共同使用人

```http
POST /api/v1/workspaces/bind-partner
Content-Type: application/json
Authorization: Bearer <mobile-token>

{"phone": "15028180169"}
```

要求 `request_id` 幂等。成功返回 `WAITING_FOR_PARTNER` 的 bootstrap 数据；重复请求返回同一个有效邀请。自绑定、已满、已有 Workspace、手机号已绑定其他 Workspace 分别返回稳定错误码。

### 5.3 邀请接受

```http
POST /api/v1/workspace-invites/{invite_id}/accept
Content-Type: application/json
Authorization: Bearer <mobile-token>

{"device_id": "<current-device-id>"}
```

当当前用户的设备数量为 1 且设备为首台设备时，直接激活成员；当设备为 `PENDING` 时，只激活成员关系并建立设备审批请求，设备仍保持只读。

### 5.4 设备权限与管理

`GET /api/v1/devices` 只返回 Android 设备，不返回 WebSession。每项至少包含：`id`、`status`（`UNVERIFIED`/`VERIFIED`/可选 `REVOKED`）、`is_current`、`created_at`、`enrolled_at`。

新增撤销接口：

```http
POST /api/v1/devices/{device_id}/revoke
Authorization: Bearer <mobile-token>
```

当前设备、已撤销设备和其他账号设备必须返回稳定的 403/409 错误。撤销事务内更新设备状态并撤销该设备所有未过期 MobileSession。

### 5.5 Web 会话撤销

新增只面向已验证 Android 设备的接口：

```http
GET  /api/v1/web-sessions
POST /api/v1/web-sessions/revoke-all
POST /api/v1/web-sessions/{session_id}/revoke
```

接口只返回当前 Workspace 的有效会话摘要，不返回 Cookie 或 digest。撤销 WebSession 不改变 AndroidDevice 状态。

## 6. 权限矩阵

| 能力 | ACTIVE Android | PENDING Android | ACTIVE WebSession |
|---|---:|---:|---:|
| 查看 Workspace/任务 | 是 | 是 | 是 |
| 创建/修改任务 | 是 | 否 | 是 |
| 评论/延期/冲突处理 | 是 | 否 | 是 |
| 批准 Android 设备 | 是 | 否 | 否 |
| 撤销其他 Android 设备 | 是（仅本账号设备） | 否 | 否 |
| 撤销 Web 会话 | 是 | 否 | 否 |
| 删除/撤销本机 | 否 | 否 | 不适用 |

所有写路由必须在服务层再次校验设备能力，不能只依赖客户端按钮禁用。读取路由使用允许 `PENDING` 的主体依赖。移动刷新接口必须允许 `PENDING` 设备刷新，但仍拒绝 `REVOKED` 设备。

## 7. 客户端行为

### Android

Workspace gate 不再只有 `needsWorkspace` 和 `failure`，改为：

- `needsPartner`：手机号输入和绑定按钮；
- `waitingForPartner`：展示邀请状态和重新加载；
- `invited`：展示邀请确认按钮；
- `ready`：进入任务界面；
- `readOnlyDevice`：进入任务界面但禁用所有写操作并显示原因；
- `failure`：仅用于真实网络/服务错误。

“我的”页面分为“我的 Android 设备”和“网页登录会话”两个区域。当前设备的撤销按钮永远不显示；服务端仍必须拒绝绕过 UI 的自我撤销请求。

### Web

Web 继续只使用二维码登录和 HttpOnly Cookie。Web 页面不显示 Android 设备状态，不调用设备注册接口。网页登录会话页面只展示当前有效会话、创建时间、过期时间和撤销按钮，不展示 Cookie、签名或内部 digest。

## 8. 安全、清理与审计

- 手机号进入数据库前统一使用 E.164；日志和 UI 对邀请手机号只显示掩码。
- QR challenge、browser proof、短信验证码、移动 token、Web Cookie 不写日志。
- WebSession 使用随机 Cookie digest；服务端只存 digest。
- 定时任务每天清理过期/撤销超过 30 天的 WebSession 和已消费/过期 challenge。
- 清理任务必须可重复执行，不能影响 ACTIVE 会话。
- 撤销 Android 设备时同时撤销 MobileSession 和该设备发起的待处理授权请求。
- 所有绑定、邀请接受、设备验证、设备撤销、WebSession 撤销写入现有审计事件体系。

## 9. 非目标

首版不实现 iOS 设备、不提供账号密码登录、不允许 Web 直接短信登录、不提供自动换绑第二位成员、不把 Web 记录伪装成 Android 设备、不引入离线写入或新的加密数据层。
