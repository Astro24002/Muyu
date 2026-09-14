# Muyu「此刻」协作闭环生产实施计划

> 日期：2026-09-11
>
> 状态：本地跨端施工与自动化验收完成。后端 Home「此刻」投影、入口分页、任务详情 `next_step`、交接说明、验收内容、Android 详情闭环、Web canonical Home 消费，以及双人协作 E2E 已在本地落地并通过回归；线上部署、APK 构建和真实双设备验收仍按后续任务推进。
>
> 关联产品规格：[Muyu「此刻」协作链浏览器原型设计](../specs/2026-09-11-moment-collaboration-prototype-design.md)

## 1. 目标与边界

### 1.1 目标

把现有双人任务领域收敛为一条可持久化、可同步、可重放的「此刻」协作闭环：

```text
清单 → 此刻 → 任务详情 → 交接/推进 → 待验收 → 通过或退回 → 已完成/继续推进
```

本计划覆盖：

- Android `清单` Tab 默认进入「此刻」；
- 顶部的“需要我处理、等对方、本周到期”三个问题入口；
- “卡住的事情、我在推进、对方在推进”三个去重且稳定排序的主体分组；
- 任务详情的服务端事实型“下一步”投影；
- 交接请求在接受前不改变 `current_handler_id`，接受后才改变；
- 负责人提交验收后任务进入 `REVIEW` 并创建待处理验收请求；
- 另一位成员通过后进入 `DONE`，退回必须填写原因并回到 `IN_PROGRESS`；
- 任务状态与协作请求状态的独立生命周期；
- 交接说明、验收内容、拒绝/退回原因和请求结果进入活动记录；
- FastAPI、PostgreSQL、Android Flutter、snapshot/cursor sync 与现有 Web 消费者的契约对齐。

### 1.2 不在本轮范围

- 不增加第三位成员、参与人、多人负责人、项目或自定义工作流；
- 不新增持久化的 `next_step` 任务字段；“下一步”由当前任务事实、请求和查看者身份派生；
- 不改写现有用户未提交的 Web 原型文件，不把它们纳入本轮提交；
- 不扩展附件、聊天、评论编辑、子任务首页聚合规则；
- 不把 Web 原型模拟状态当作生产 API 或数据库实现。

### 1.3 施工约束

- Workspace 仍最多有两名 `ACTIVE` 成员；任务始终只有一个 `current_handler_id`。
- 任务状态继续使用 `TODO`、`IN_PROGRESS`、`BLOCKED`、`REVIEW`、`DONE`、`CANCELLED` 六值。
- 所有写入继续使用 `request_id` 幂等键、乐观版本和事务内 cursor。
- WebSocket 只发送失效提示，客户端仍通过 snapshot/changes REST 获取事实。
- Android 离线只读最后一个有效快照，不做离线写入。

## 2. 现状审计与缺口

### 2.1 已存在并应复用的能力

| 领域 | 当前实现 | 结论 |
| --- | --- | --- |
| 单负责人 | `Task.current_handler_id`、`TaskHandlerHistory`、`TaskService._require_handler` | 保留；不引入新 owner 字段。 |
| 六状态 | `TaskStatus`、`TRANSITIONS`、`status_version`、`TaskStatusHistory` | 基本满足；补齐本计划的入口和验收内容校验。 |
| Review 元数据 | `reviewer_user_id`、`review_submitted_at`、`reviewed_at`、`review_rejection_reason` | 保留；进入 `REVIEW` 时由服务端派生另一位 active 成员。 |
| 请求模型 | `TaskApprovalRequest`、`requester_id`、`approver_id`、`request_type`、`proposed_changes`、`status`、`rejection_reason` | 复用 JSONB 承载交接说明和验收内容；不把请求状态塞进任务状态。 |
| 验收事务 | `TaskApprovalService.submit_review` 已将 `IN_PROGRESS → REVIEW` 与待处理 `STATUS_UPDATE` 请求放在同一事务 | 扩展内容参数和事件 payload，保留原子性与幂等。 |
| 审批路由 | `/api/v1/workspaces/{workspace_id}/approval-requests` 及 approve/reject/cancel | 保持路径，补充上下文校验和 Android 调用。 |
| cursor sync | `WorkspaceChangeLog` 已支持 `task`、`approval_request`、`comment` 等资源；snapshot 已返回审批请求 | 不新增一种“首页资源”；任务/请求变化后重新加载 home 投影。 |
| Android 同步 | `WorkspaceSyncController` 已合并任务、请求和 cursor，并有 home 刷新逻辑 | 扩展模型、last-known-good home、请求动作和页面路由。 |
| 任务详情动作 | 现有 Flutter 已有六状态动作、Review 退回原因对话框、负责人选择 | 重排为“下一步”主行动，保留服务端权限结果。 |

### 2.2 必须补齐的缺口

1. [backend/app/home/routes.py](../../../backend/app/home/routes.py) 目前只返回当前用户的 `current_tasks`、`blocked_tasks`、`review_tasks` 和一个 `pending_approval_count`；它不会展示对方的进行中任务，也没有交接/验收两个方向的计数和本周到期视角。
2. 当前 home 的 `blocked_tasks` 只筛 `current_handler_id == actor.user_id`，与“双方 BLOCKED 合并到卡住的事情”不符；三个主体也没有明确的服务端去重契约。
3. 现有 `_bounded_tasks` 只按逾期、无日期、日期和更新时间排序；“即将到期”窗口、分组优先级、稳定 tie-breaker 和跨负责人投影尚未冻结。
4. `HANDLER_TRANSFER` 已存在，待处理时任务 owner 不会立即改变，审批后才执行变更；但现有请求没有强制、结构化的交接说明，活动记录只暴露通用审批 operation 摘要。
5. `submit_review` 已创建 `REVIEW` 和验收请求，但没有验收内容；`proposed_changes` 中只有 `target_status` 与 `review_submission`。
6. [backend/app/tasks/routes.py](../../../backend/app/tasks/routes.py) 的 `/tasks/{task_id}/activity` 目前只返回 operation/comment/delay 摘要，不返回 `ActivityEvent.payload`，因此无法向用户证明交接说明、验收内容和退回原因。
7. 请求 `REJECTED` 目前同时覆盖普通拒绝和 Review 退回；这可以保留，但客户端必须根据请求类型和上下文显示“拒绝”或“退回”，不能把它当作任务状态。
8. Android `TaskListView` 仍把 home 投影渲染为旧的“当前阻塞”，`CloudWorkspaceScreen` 虽然默认选中清单，但清单内容仍是常规列表，不是「此刻」固定三组。
9. Android `home.dart`、Web `api/types.ts` 和 Web today view model 仍绑定旧 home 字段；API 应采用增量兼容方式，避免覆盖当前用户未提交的 Web 文件。
10. cursor snapshot/changes 已同步任务和请求，但 home 是派生读模型；每次拉取 cursor 后应重新取 home，home 请求失败时保留上一份有效投影而不是清空页面。

### 2.3 工作树保护

审计时发现以下用户未提交内容：`docs/README.md`、`docs/superpowers/specs/2026-09-11-moment-collaboration-prototype-design.md`、`web/src/**`、`web/test/**`、`web/public/**`。本计划创建时不修改、不删除、不格式化这些文件，也不提交它们。后续施工必须先读取这些改动，再按 Web 契约任务合并。

## 3. 冻结的领域契约

### 3.1 任务状态

| 当前状态 | 允许目标 | 触发者 | 关键事实 |
| --- | --- | --- | --- |
| `TODO` | `IN_PROGRESS`、`BLOCKED`、`CANCELLED` | 当前负责人 | `BLOCKED` 必须有阻塞原因和恢复负责人。 |
| `IN_PROGRESS` | `BLOCKED`、`REVIEW`、`CANCELLED` | 当前负责人 | 进入 `REVIEW` 同时派生 reviewer 并创建验收请求。 |
| `BLOCKED` | `IN_PROGRESS`、`CANCELLED` | 当前负责人或其受审批保护的请求 | 恢复时使用保存的 `resume_handler_id` 或显式有效成员。 |
| `REVIEW` | `DONE`、`IN_PROGRESS`、`CANCELLED` | 仅 `reviewer_user_id` | `IN_PROGRESS` 必须有非空退回原因；负责人不变。 |
| `DONE` | `TODO`、`IN_PROGRESS`、`CANCELLED` | 依现有任务权限 | 重新打开清除完成时间，但不删除历史验收事件。 |
| `CANCELLED` | `TODO`、`IN_PROGRESS` | 依现有任务权限 | 不进入此刻主体。 |

用户可见中文固定为：待进行、进行中、阻塞中、待验收、已完成、已取消。`REVIEW` 不是“等对方”这种请求状态的别名。

### 3.2 协作请求状态

`TaskApprovalRequest.status` 保持 `PENDING`、`APPROVED`、`REJECTED`、`CONFLICTED`、`CANCELLED`。它与 `Task.status` 独立：

- `PENDING` 交接不会改变任务负责人或状态；
- `APPROVED` 交接才应用 `current_handler_id`，验收通过才应用 `REVIEW → DONE`；
- `REJECTED` 的 Review 请求表示“退回”，任务回到 `IN_PROGRESS`；普通字段/交接请求则表示“拒绝”，任务不变；
- `CANCELLED` 表示发起人撤回或因目标事实失效而取消；
- `CONFLICTED` 表示版本/目标已变化，不能重开旧请求；重新发起必须使用新 `request_id` 和新请求行。

客户端显示文案由 `request_type`、`proposed_changes.review_submission` 和结果上下文派生，绝不能用 request status 覆盖 task status。

## 4. API 与数据契约

### 4.1 任务快照保持共享、viewer 无关

现有任务快照继续包含：

```json
{
  "status": "REVIEW",
  "current_handler_id": "handler-uuid",
  "reviewer_user_id": "reviewer-uuid",
  "review_submitted_at": "2026-09-11T10:00:00Z",
  "reviewed_at": null,
  "review_rejection_reason": null,
  "status_version": 4,
  "lifecycle_version": 5
}
```

它不包含按查看者变化的 `next_step` 文案；按查看者派生的下一步只出现在任务详情响应或 Android 本地投影中。

### 4.2 `TaskApprovalRequest.proposed_changes` 扩展

继续使用现有 JSONB，不新建参与人表或请求上下文表。服务层必须拒绝未知键、空白内容和错误的请求类型组合。

交接请求：

```json
{
  "request_type": "HANDLER_TRANSFER",
  "proposed_changes": {
    "current_handler_id": "next-handler-uuid",
    "transfer_note": "酒店后续需要持续沟通，请继续跟进合同"
  },
  "base_field_versions": {"current_handler_id": 3}
}
```

- `transfer_note` trim 后长度为 1-2000；新 Android 入口必填。
- 待处理期间任务的 `current_handler_id`、`status`、版本和首页分组不变。
- 接受后使用当前 owner 权限在同一事务写入 owner、handler history、task operation 和审批事件。
- 拒绝、撤回或冲突不写入 proposed handler，但完整请求仍留在 snapshot、changes 和 activity 中。

验收提交请求：

```json
{
  "request_type": "STATUS_UPDATE",
  "proposed_changes": {
    "target_status": "DONE",
    "review_submission": true,
    "review_content": "已确认酒店合同、套餐和取消条款"
  },
  "base_field_versions": {"status_version": 4}
}
```

- `review_content` trim 后长度为 1-5000；负责人提交验收时必填。
- 请求创建与 `IN_PROGRESS → REVIEW` 必须同事务完成；失败时二者都回滚。
- reviewer 通过时只更新任务状态和 review 元数据，不把负责人改成 reviewer。
- reviewer 退回时 `POST .../reject` 的 `reason` 必填 1-2000；同一原因写入请求 `rejection_reason`、任务 `review_rejection_reason` 和事件 payload。

历史请求若没有这些新键，读取时显示“历史内容未记录”，不能伪造内容。

### 4.3 Home API

`GET /api/v1/home` 增加以下 canonical 字段；旧的 `current_tasks`、`blocked_tasks`、`review_tasks`、`pending_approval_count` 在 Android/Web 均完成迁移并经过一个发布周期前保留为 deprecated compatibility fields，不再作为 Android「此刻」数据源。

```json
{
  "viewer_user_id": "me-uuid",
  "as_of": "2026-09-11T10:00:00Z",
  "week": {
    "timezone": "UTC",
    "start": "2026-09-07T00:00:00Z",
    "end": "2026-09-14T00:00:00Z"
  },
  "entry_counts": {
    "needs_me": 2,
    "waiting_on_other": 1,
    "due_this_week": 4
  },
  "moment": {
    "blocked": {"items": [], "has_more": false},
    "mine": {"items": [], "has_more": false},
    "other": {"items": [], "has_more": false}
  },
  "entries": {
    "needs_me": {"items": [], "has_more": false},
    "waiting_on_other": {"items": [], "has_more": false},
    "due_this_week": {"items": [], "has_more": false}
  }
}
```

`moment.blocked/mine/other` 的 task item 使用现有 Task snapshot；两个请求入口的 item 使用：

```json
{
  "approval_request": {"id": "...", "status": "PENDING", "request_type": "HANDLER_TRANSFER"},
  "task": {"id": "...", "title": "确认酒店", "status": "IN_PROGRESS", "current_handler_id": "..."}
}
```

契约规则：

- `needs_me` 只统计 `approver_id == viewer_user_id && status == PENDING`；
- `waiting_on_other` 只统计 `requester_id == viewer_user_id && status == PENDING`；
- `due_this_week` 统计 `due_at >= week.start && due_at < week.end`、未删除、状态为 `TODO/IN_PROGRESS/BLOCKED/REVIEW` 的任务，双方负责人都包含；
- 三个 count 是不同统计对象，不能相加当任务总数；
- `week` 使用服务端 UTC 的自然周，并把边界返回给客户端；后续引入 Workspace timezone 时只替换周界计算，不修改字段语义；
- `moment` 只保留 `BLOCKED`、`TODO`、`IN_PROGRESS`；`REVIEW`、`DONE`、`CANCELLED` 不进入三组主体；
- `BLOCKED` 优先归入 `blocked`，不会因为 `waiting_for_user_id` 或文字“等待对方”重复进入 `waiting_on_other`；
- `TODO/IN_PROGRESS` 按 `current_handler_id == viewer_user_id` 归入 `mine`，否则归入 `other`；
- 每个 task 在 `moment` 最多出现一次；服务端先归组再排序，客户端不再二次跨组排序。

为支持“查看全部入口”的大数据量，增加：

```text
GET /api/v1/home/entries/{entry}?limit=50&after_cursor={cursor}
```

其中 `{entry}` 为 `needs_me`、`waiting_on_other`、`due_this_week`；返回 `entry_counts` 中同一 count、`items`、`has_more`、`next_cursor`。第一页仍可直接使用 `/home` 的预取 items；分页数据不能改变 count 口径。

### 4.4 交接、验收与审批路由

保留现有路径并增加语义校验：

| 路径 | 请求 | 成功结果 |
| --- | --- | --- |
| `POST /api/v1/tasks/{task_id}/transition` | `target_status=REVIEW`、`review_content`、`base_status_version` | `202`，返回已进入 `REVIEW` 的 task、PENDING 验收请求和 cursor。 |
| `POST /api/v1/tasks/{task_id}/handler-transfer` | `target_handler_id`、`transfer_note`、`base_field_version` | `202`，返回 PENDING `HANDLER_TRANSFER`；任务仍为原 owner。 |
| 现有 `PATCH /api/v1/tasks/{task_id}` | `changes.current_handler_id` | 保留兼容；内部转发到交接校验，生产客户端必须携带 transfer note 或迁移到专用路由。 |
| `POST /api/v1/workspaces/{workspace_id}/approval-requests/{id}/approve` | `request_id` | 仅 derived approver；交接应用 owner 变更，Review 应用 `DONE`。 |
| `POST /api/v1/workspaces/{workspace_id}/approval-requests/{id}/reject` | `request_id`、Review 时必填 `reason` | 普通请求拒绝不改任务；Review 请求退回 `IN_PROGRESS`，owner 保持不变。 |
| `POST /api/v1/workspaces/{workspace_id}/approval-requests/{id}/cancel` | `request_id` | 仅 requester；任务事实保持不变。 |

所有 mutation 维持 `request_id` 重放语义：相同 request/body 返回同一结果；相同 request_id 搭配不同内容返回 `approval_request_reused`。旧客户端调用 transition 的 Review 决策继续兼容，但 Android 新代码直接调用审批 action，避免把“通过”误当普通状态变更。

### 4.5 任务详情“下一步”

增加 viewer-aware 的详情投影，不把它写入 Task 表：

```text
GET /api/v1/tasks/{task_id}
```

响应在现有 task snapshot 外增添：

```json
{
  "next_step": {
    "kind": "WAITING_FOR_TRANSFER_ACCEPTANCE",
    "label": "等待溪岸接受交接",
    "request_id": "approval-uuid",
    "can_act": true,
    "actions": ["CANCEL_TRANSFER"]
  }
}
```

`kind` 至少包括：`CONTINUE_TASK`、`WAITING_FOR_TRANSFER_ACCEPTANCE`、`ACCEPT_OR_REJECT_TRANSFER`、`WAITING_FOR_REVIEW`、`ACCEPT_OR_RETURN_REVIEW`、`RESUBMIT_REVIEW`、`SHOW_BLOCKED_FACT`、`NO_ACTION`。按钮只是能力提示，真正权限仍由 mutation API 校验。Android 网络失败时可用同一纯函数从 snapshot + approvals 派生，并标记为可能过期。

同一任务存在多个待处理请求时，投影按协作闭环优先判定：先匹配 `HANDLER_TRANSFER`，再匹配带 `review_submission=true` 且目标为 `DONE` 的验收请求；普通字段审批不能遮挡交接或验收的“下一步”。

### 4.6 活动记录与协作证据

现有 `ActivityEvent` 继续 append-only；扩展 `/tasks/{task_id}/activity` 返回事件 payload，而不是只返回 operation 类型：

```json
{
  "kind": "activity",
  "id": "event-uuid",
  "event_type": "HANDLER_TRANSFER_APPROVED",
  "actor_user_id": "user-uuid",
  "request_id": "request-uuid",
  "created_at": "2026-09-11T10:00:00Z",
  "payload": {
    "from_user_id": "old-owner",
    "to_user_id": "new-owner",
    "transfer_note": "继续跟进合同",
    "task_before": {"current_handler_id": "old-owner"},
    "task_after": {"current_handler_id": "new-owner"}
  }
}
```

最少需要保留：

- `HANDLER_TRANSFER_REQUESTED/APPROVED/REJECTED/CANCELLED`：request id、from/to、交接说明、前后 owner；
- `TASK_REVIEW_SUBMITTED`：负责人、reviewer、验收内容、提交时 task snapshot；
- `TASK_REVIEW_ACCEPTED`：验收人、验收内容引用、验收时间、前后状态；
- `TASK_REVIEW_RETURNED`：验收人、退回原因、负责人、前后状态；
- 普通状态/阻塞/评论/延期事件继续保留既有 payload。

`ActivityEvent.payload` 与 `TaskApprovalRequest.proposed_changes/rejection_reason` 在同一事务写入；activity API 只允许同 Workspace 成员读取，不能从日志中省略或重新推导已结束请求的内容。

## 5. 权限矩阵

| 动作 | 当前负责人 | 另一位 ACTIVE 成员 | `reviewer_user_id` | PENDING/未验证设备 |
| --- | --- | --- | --- | --- |
| 读取任务、此刻、全部任务、活动 | 允许 | 允许 | 同一成员身份，允许 | PENDING 设备只读；未认证拒绝 |
| 直接编辑普通任务字段 | 直接写入 | 创建针对当前负责人的审批请求，任务不变 | 按其是否为当前负责人处理 | 写入 `403 device_not_verified` |
| 发起交接 | 创建 `HANDLER_TRANSFER`，必须填说明；任务 owner 不变 | 不作为 Android 主入口；保留现有逆向受保护请求时仍须由当前 owner 审批 | 同上 | 禁止 |
| 接受/拒绝交接 | 若是目标 approver 才可接受/拒绝 | 若是目标 approver 才可接受/拒绝 | 仅当其是 derived approver | 禁止 |
| 提交验收 | 仅当前负责人，原子进入 `REVIEW` 并请求另一成员 | 不能代提 | 如果不是当前负责人不能代提 | 禁止 |
| 通过验收 | 不能处理自己的验收请求 | 仅 derived reviewer 通过，进入 `DONE` | 同左 | 禁止 |
| 退回验收 | 不能处理自己的验收请求 | 仅 derived reviewer 退回，原因必填，进入 `IN_PROGRESS` | 同左 | 禁止 |
| 撤回自己发起的请求 | 允许 | 允许 | 依 requester 身份 | 禁止 |
| 查看/处理请求列表 | 只能看到涉及自己的请求 | 只能看到涉及自己的请求 | 同一身份 | PENDING 设备可读但不可写 |

所有审批动作都重新锁定 Workspace active membership、request row 和 task row，再验证 approver/requester、status 和版本，不能依赖客户端传来的角色或 `can_act`。

## 6. 状态机与关键时序

### 6.1 交接

```text
负责人 Bokang · IN_PROGRESS
        │ POST handler-transfer(note)
        ▼
任务仍由 Bokang 负责 · IN_PROGRESS
        │ PENDING HANDLER_TRANSFER
        ├── 溪岸 approve ──► current_handler_id = 溪岸，IN_PROGRESS
        ├── 溪岸 reject ───► Bokang 负责，IN_PROGRESS
        └── Bokang cancel ─► Bokang 负责，IN_PROGRESS
```

approve 的任务变更、handler history、请求状态、活动事件和 cursor 必须一个事务完成。接受前两个用户看到同一 owner 和同一任务行；接受后 home 重新归组。

### 6.2 验收

```text
负责人 · IN_PROGRESS
        │ submit review_content
        ▼
负责人仍是 owner · REVIEW · reviewer_user_id = 另一 ACTIVE 成员
        │ PENDING STATUS_UPDATE(review_submission=true)
        ├── reviewer approve ─► DONE，owner 不变
        └── reviewer reject(reason) ─► IN_PROGRESS，owner 不变
```

再次提交验收必须创建新请求；上一条 APPROVED/REJECTED 请求与验收内容不得覆盖或删除。`review_rejection_reason` 是当前任务最近一次退回事实，历史原因以 ActivityEvent 和已解决请求为准。

### 6.3 请求与任务状态分离示例

| 任务状态 | 请求状态 | 用户语义 |
| --- | --- | --- |
| `IN_PROGRESS` | `PENDING` + `HANDLER_TRANSFER` | 等对方接受交接，负责人仍是发起前 owner。 |
| `REVIEW` | `PENDING` + `review_submission` | 等另一成员验收，负责人仍是提交者。 |
| `IN_PROGRESS` | `REJECTED` + `review_submission` | 该次验收已退回，任务由原负责人继续处理。 |
| `DONE` | `APPROVED` + `review_submission` | 该次验收通过，任务结束但 owner 不变。 |

## 7. 任务分解

每个任务施工时先加契约测试，再实施最小改动；当前已完成 Task 0 至 Task 9 的本地首轮施工（Task 9 包含 Web canonical Home 消费和旧字段兼容），并完成 Task 10 的本地自动化 E2E；Task 10 的线上/真机发布验收仍按本计划推进。

### Task 0：建立跨端契约测试基线

**后端：**

- 新增 `backend/tests/tasks/test_moment_contract.py`：请求上下文键、长度、状态/请求分离、owner 不变和新请求重提。
- 扩展 `backend/tests/httpapi/test_home_routes.py`：三入口 count、双方任务、去重、排序、自然周边界和 has-more。
- 扩展 `backend/tests/httpapi/test_task_approval_routes.py`：交接 note、验收 content、接受/拒绝/退回、幂等和权限矩阵。
- 扩展 `backend/tests/tasks/test_review_workflow.py` 与 `test_task_approvals.py`：ActivityEvent payload 与历史请求。

**Android：**

- 扩展 `client/test/models/home_test.dart`、`client/test/models/task_approval_request_test.dart`。
- 新增 `client/test/models/moment_next_step_test.dart`。
- 扩展 `client/test/sync/workspace_sync_controller_test.dart`、`client/test/sync/task_approval_sync_test.dart`。
- 扩展 `client/test/screens/cloud_workspace_screen_test.dart`、`task_detail_screen_test.dart`、`task_review_actions_test.dart`。

**契约动作：**

- 先运行 focused suites，记录旧 home/旧 payload 失败点；
- 所有测试 fixture 明确 viewer、owner、reviewer、requester、approver，禁止用单用户 fixture 掩盖权限。

### Task 1：补齐 PostgreSQL 查询索引与迁移门禁

**文件：**

- 新增 `backend/alembic/versions/<next>_moment_home_indexes.py`；
- 修改 `backend/app/db/models.py` 的 `Task.__table_args__`（若使用 ORM 索引声明）；
- 新增/扩展 `backend/tests/db/test_moment_home_schema.py`。

**实现：**

- 为 Workspace、软删除、状态、负责人、截止时间的 home 查询增加组合索引；
- 评估现有 `task_approval_requests` 的 workspace/status/approver、workspace/status/requester、task/status 索引是否覆盖 count 与 pending review 查询；不足时用同一 migration 补充；
- 不新增表、不迁移已有任务内容；JSONB 扩展依赖现有 `proposed_changes` 和 ActivityEvent.payload；
- migration 必须可重复执行、可回滚索引，并在 staging 用 `EXPLAIN` 验证全 Workspace 查询不退化成高成本全表排序。

### Task 2：实现交接说明、验收内容和活动事实

**文件：**

- 修改 `backend/app/tasks/approval_schemas.py`、`approvals.py`、`routes.py`、`schemas.py`；
- 修改 `backend/app/tasks/service.py`、`operations.py`；
- 修改 `backend/app/db/models.py` 仅在需要补索引/约束时；
- 扩展 `backend/tests/tasks/test_task_approvals.py`、`test_review_workflow.py`、`backend/tests/httpapi/test_task_approval_routes.py`。

**实现：**

- 在 `_validate_request_shape`/`_validate_status_proposal` 中严格校验 `transfer_note`、`review_content`，统一 trim 和长度错误码；
- `submit_review` 接收 content，在同一事务完成 transition、request、ActivityEvent；
- approval apply 前保留 task before snapshot，apply 后写 task after snapshot；
- 为交接请求结果、验收提交/通过/退回写明确事件类型，payload 保留文本、操作者、request id、时间和前后状态/owner；
- 普通 reject 与 Review return 共用 request status `REJECTED`，但事件类型和 UI projection 明确区分；
- 保留 `TaskApprovalRequest` 原有字段和 sync JSON 兼容性；不重开旧 request。

### Task 3：重做 home 服务端投影

**文件：**

- 修改 `backend/app/home/schemas.py`、`backend/app/home/routes.py`；
- 视需要新增 `backend/app/home/service.py`，把分类、排序和入口查询从 FastAPI route 移到可单测服务；
- 扩展 `backend/tests/httpapi/test_home_routes.py`，新增 `backend/tests/home/test_moment_projection.py`。

**实现：**

- 一次查询 workspace 未删除任务，按优先级 `BLOCKED → TODO/IN_PROGRESS` 完成唯一归组；
- blocked 无论 owner 是谁都进入 `moment.blocked`；普通任务按 viewer/other 进入 mine/other；REVIEW 只进入请求入口/全部任务；
- 分组内排序：逾期、48 小时内即将到期、较远截止、无截止；同截止按 `updated_at DESC, id ASC`，blocked 同条件按 `blocked_since ASC`；
- 三个 count 分别用 pending request 或任务 status/due 查询，不从 section item 数量推导；
- 预取有限 items 并返回 has-more；entry 分页使用固定 count 快照口径和 cursor；
- 保留旧 response 字段作为 deprecated projection，注明最终移除门槛是 Web/Android 都切换并经过一个发布周期。

### Task 4：实现 viewer-aware 下一步与 activity API

**文件：**

- 修改 `backend/app/tasks/routes.py`；
- 新增 `backend/app/tasks/next_step.py` 与对应 schemas（如不需要独立文件，放入 `schemas.py`）；
- 扩展 `backend/tests/httpapi/test_task_contract_regressions.py`、新增 `test_task_activity_routes.py`。

**实现：**

- `GET /tasks/{id}` 增加 `next_step`，按请求状态、task status、owner/reviewer 和当前 viewer 派生；
- `GET /tasks/{id}/activity` 返回 ActivityEvent payload，按事件时间稳定排序，并保留 comment/delay 历史；
- 不允许客户端通过传入 viewer id 获取另一视角的 `can_act`；viewer 必须来自认证 Actor；
- 详情响应保持旧 task 字段，旧 Flutter/Web parser 忽略新增字段。

### Task 5：对齐 snapshot、cursor changes 和 home 刷新

**文件：**

- 检查/修改 `backend/app/sync/service.py`、`backend/app/sync/routes.py`、`backend/app/tasks/approvals.py`、`backend/app/tasks/service.py`；
- 扩展 `backend/tests/sync/test_task_approval_sync.py`、`backend/tests/e2e/test_cloud_protocol.py`、`backend/tests/e2e/test_two_person_task_approval.py`。

**实现：**

- snapshot 继续返回全部未过期/可见 approval request，保留 transfer/review JSONB 内容；
- approval request、task 和 activity 事件在同一 mutation transaction 分配 cursor；
- changes 的 approval resource 不能丢弃已解决请求的 `proposed_changes`、`rejection_reason`；
- cursor 失效仍返回 410，客户端完整 snapshot 后再重载 home；
- changes 必须从 `after_cursor + 1` 连续返回；历史已被清理或中间游标缺失时统一返回 410，不能把不完整增量当作成功；
- WebSocket hint 必须在 commit 后发送；
- 测试重复拉取、空 changes、cursor gap、请求先变更后任务变更和两个设备并发。

### Task 6：扩展 Flutter 数据模型与 repository/controller

**文件：**

- 修改 `client/lib/models/home.dart`；
- 修改 `client/lib/models/task_approval_request.dart`；
- 新增 `client/lib/models/moment_next_step.dart`（或并入 home model）；
- 修改 `client/lib/sync/workspace_sync_repository.dart`、`workspace_sync_controller.dart`；
- 检查 `client/lib/task/cloud_task_repository.dart` 的兼容接口；
- 修改 `client/lib/models/workspace_snapshot.dart` / `workspace_change.dart` 仅在解析新字段或 last-known-good 需要时。

**实现：**

- `HomeResponse` 增加 `viewerUserId`、`asOf`、`week`、`entryCounts`、`moment`、`entries`，旧字段保留读取；
- 新增严格的 `MomentSection`、`HomeEntryCount`、`HomeApprovalItem` parser，拒绝 foreign workspace、负 count、无效 status 和未知 entry；
- `TaskApprovalRequest` 提供 `transferNote`、`reviewContent`、`isReviewSubmission`、上下文状态标签，但原始 JSON 仍 round-trip；
- repository 增加 handler-transfer/review-content 参数和 activity/next-step 请求；所有请求带 request id；
- controller 在 cursor pull 后重新加载 home；home 失败时保留上一份 home，并设置 `isStale/errorMessage`，不能将 home 设为 null；
- transition/approval 返回的 task、request、cursor 先合并再拉取，避免短暂丢失 pending 请求。

### Task 7：实现 Android「此刻」首页与入口

**文件：**

- 修改 `client/lib/screens/cloud_workspace_screen.dart`；
- 修改 `client/lib/screens/task_list_view.dart`；
- 修改 `client/lib/tasks/task_status.dart`；
- 视需要新增 `client/lib/screens/moment_entry_screen.dart` 或在 task list 中实现入口页；
- 更新 `client/test/screens/cloud_workspace_screen_test.dart`、`task_list_view` 相关测试，并新增 `client/test/screens/moment_entry_screen_test.dart`。

**实现：**

- `_selectedDestination` 初始值继续为 0，但 destination 0 的根内容改为 moment projection；
- 顶部按固定顺序显示“需要我处理、等对方、本周到期”，使用 count + 入口按钮，不把它们渲染成互斥任务状态卡；
- 主体严格按“卡住的事情、我在推进、对方在推进”渲染，任务只按服务器 section 出现一次；
- 任务行最多两层主要信息，blocked 额外显示真实 `blocked_reason`，右侧使用明确逾期/日期文字；
- “查看全部事情”打开现有全量任务列表，包含所有未删除任务和六状态；
- 入口详情页使用 home 预取数据，has-more 时调用 entry 分页 API；需要我处理/等对方显示 approval context，不把 request status 当 task status；
- 清单刷新、下拉刷新、cursor hint 和从详情返回都重新投影，不保留过期分组。

### Task 8：实现任务详情“下一步”、交接与验收动作

**文件：**

- 修改 `client/lib/screens/task_detail_screen.dart`；
- 修改 `client/lib/screens/task_approval_screen.dart`；
- 修改 `client/lib/models/task.dart`（仅在需要展示 next-step/activity context 时）；
- 扩展 `client/test/screens/task_detail_screen_test.dart`、`task_review_actions_test.dart`、`task_approval_screen_test.dart`。

**实现：**

- 详情顺序固定为标题/事实、当前情况、下一步、协作内容、活动、动作；
- 当前 owner 在 IN_PROGRESS 看到继续处理、发起交接、提交验收；
- pending transfer 发起人看到等待对方接受和撤回，目标成员看到接受/拒绝；双方都看到当前 owner 仍未改变；
- 验收提交要求非空 `review_content`，成功后显示等待 reviewer 验收；
- 只有 reviewer 显示通过/退回，退回对话框阻止空白原因；请求发起人不能看见决策按钮；
- 退回后原负责人看到修改后重新提交、历史原因和新的提交入口，旧请求仍可在活动/请求记录查看；
- 活动记录渲染 transfer note、review content、return reason，并显示操作者和时间；
- 服务端拒绝时 UI 显示稳定错误，不做本地伪造状态转换。

### Task 9：迁移 Web API 消费者并保护现有脏文件

**文件（本轮已施工，保留既有视觉原型并精确合并）：**

- `web/src/api/types.ts`、`web/src/api/client.ts`；
- `web/src/sync/workspace-sync.ts`；
- `web/src/tasks/task-view-model.ts`、`web/src/ui/workspace-view.ts`、`web/src/ui/task-detail-view.ts`、`web/src/ui/approval-view.ts`；
- 对应 `web/test/**`。

**实现：**

- 先在当前用户 Web 改动上做三方审阅，保留其页面/样式/测试改动；
- 先支持新 `moment/entries` 字段，再移除旧 home projection；
- Web 与 Android 采用相同 status/request/next-step/ActivityEvent 语义；
- 本轮已在保留既有视觉原型的前提下完成 Web canonical Home 消费迁移；线上静态文件部署仍需单独授权。

### Task 10：端到端验收与发布门禁

**文件：**

- 扩展 `backend/tests/e2e/test_two_person_task_approval.py`、`backend/tests/e2e/test_cloud_protocol.py`；
- 扩展 `client/integration_test/mobile_cloud_flow_test.dart`；
- 必要时新增 `scripts/smoke-moment-collaboration.sh`，只使用测试账号和环境注入 secret。

**实现：**

- 用两个 ACTIVE 成员、两个 Android 设备和同一任务完整跑通六屏故事；
- 在请求 pending、approve、reject、review submit、review accept/return、cursor pull 后分别核对两台设备；
- 验证旧客户端仍能读取 additive home/task/request 字段；
- 验证所有数据库 migration、API、Flutter tests 及现有 Web tests 后才进入部署。

本地自动化验收已完成：`backend/tests/e2e/test_two_person_task_approval.py` 串联双人创建、交接审批、负责人变更、验收提交、退回、重新提交、通过完成，并在关键节点核对双方 snapshot、连续 cursor/changes、`next_step` 和 Home 三个计数；Home 入口分页已覆盖稳定 keyset cursor、taskless 请求、foreign/deleted 过滤和 count 一致性。真实 Android 双设备、staging/线上部署、APK 发布仍未执行。

## 8. 测试与验收矩阵

### 8.1 后端单元/领域

- home：双方 `BLOCKED`、owner 分组、唯一归组、逾期/48 小时/未来/无日期排序、tie-breaker、自然周半开区间；
- request：交接 pending owner 不变，approve 一次性变更，reject/cancel 不变，旧 request 不重开；
- review：owner 只能提交、状态进入 REVIEW、reviewer 派生准确，approve DONE、return 要求原因且 owner 不变；
- content：空白/超长 transfer note、review content、return reason 稳定返回 422；
- permission：非 approver、非 requester、非 reviewer、跨 workspace、第三 active member 和未验证设备全部拒绝；
- activity：每个关键结果至少有一个 append-only event，payload 含说明/内容/原因、actor、request id、before/after；
- concurrency：task lock + request lock 下双 approve、双 transfer、旧版本和重复 request id 只能得到一个事实结果。

### 8.2 HTTP/API

- `GET /home` 的 count 不随 section 截断改变；
- `GET /home/entries/*` 分页与 count 一致、foreign task/request 不泄露；
- `GET /tasks/{id}` 的 `next_step` 随 viewer 变化但 task snapshot 不变；
- activity API 返回已解决请求的历史内容；
- approval action 返回 task/request/cursor 并可直接被 Flutter 合并；
- 所有错误符合现有 `{code,message,details}` envelope，保留 `X-Request-ID`。

### 8.3 cursor/snapshot sync

- full snapshot 包含新增 request JSON 内容；
- transfer approval、review submit、review decision 各自为连续 cursor 资源变化；
- changes 结果严格从 after cursor 开始，不能跳 cursor；
- cursor 过期触发完整 snapshot；
- 任务、请求、评论和分类已有解析测试继续通过；
- home 派生失败不会清空上一次可用 UI。

### 8.4 Flutter Android

- 冷启动登录后 `清单` 默认显示「此刻」，不是旧全量列表；
- 三个顶部入口文字、count、点击详情和空态稳定；
- 三个主体顺序和 task 唯一性稳定；
- 任务行在窄屏下不溢出，blocked reason、逾期文字不遮挡；
- 双用户视角的 next step 与按钮互斥正确；
- transfer/review action 带 request id，失败后不伪造成功；
- `flutter analyze`、全量 `flutter test`、Android debug build 通过。

### 8.5 Web 兼容

- 旧 home fixture 可读取新 additive response；
- 新 moment/queue 字段有 TypeScript typecheck、unit/UI tests；
- 当前未提交 Web 样式和原型测试在合并后不被覆盖；
- `npm test -- --run`、`npm run typecheck`、`npm run build` 通过。

## 9. 生产验收脚本与场景

以 Bokang 为初始负责人、溪岸为另一位 ACTIVE 成员、任务“确认婚礼酒店”为固定验收数据：

1. 两台 Android 登录后都在清单进入「此刻」；Bokang 任务在“我在推进”，溪岸看到“对方在推进”，三个 count 为 0。
2. Bokang 发起带说明的交接。两台设备都仍看到 `current_handler_id = Bokang`、`IN_PROGRESS`；Bokang 的“等对方”与溪岸的“需要我处理”各加 1。
3. 溪岸接受交接。请求变为 `APPROVED`，owner 一次性变为溪岸、任务仍 `IN_PROGRESS`；home 两边重新归组，活动保留说明和 from/to。
4. 溪岸填写验收内容提交。任务进入 `REVIEW`、负责人仍为溪岸、`reviewer_user_id = Bokang`；任务离开三组主体，两个请求方向分别增加 1。
5. Bokang 通过。请求 `APPROVED`，任务 `DONE`、负责人仍为溪岸；任务不在此刻主体但仍在全部事情和活动中，验收内容可见。
6. 另一次验收由 Bokang 退回。空原因不能提交；有原因时请求 `REJECTED`、任务回到 `IN_PROGRESS`、负责人仍是溪岸；溪岸看到“修改后重新提交”，活动保留原因。
7. 插入一条双方 `BLOCKED` 任务和一条没有 pending request 的“等待对方”阻塞任务，确认它们只在“卡住的事情”，不增加“等对方”。
8. 将 due_at 置于 UTC 当前自然周边界内，确认本周到期入口包括 TODO/IN_PROGRESS/BLOCKED/REVIEW，不包括 DONE/CANCELLED/删除任务。
9. 在一个已登录但未验证的 Android 设备上重复写操作，确认只能读取和刷新，不能创建/接受/退回/撤回。
10. 让 cursor 过期并断网，确认 Android 显示最后有效快照和 stale 状态，恢复网络后完整 snapshot 且 home/count/活动一致。

## 10. 部署与回滚注意事项

### 10.1 发布顺序

1. 先在 staging 运行索引 migration、`alembic upgrade head` 和 `EXPLAIN` 检查；
2. 部署后端 additive 版本：先接受旧 home 字段、旧 transition 调用，同时产生新事件 payload；
3. 部署 Android 版本，确认新 home/approval/activity contract 在真实双用户 Workspace 通过；
4. 完成 Web consumer 迁移后观察一个发布周期，再删除旧 home compatibility fields；
5. 所有数据库、cursor、Android、Web 检查通过后才切生产流量。

### 10.2 数据与时区

- 本轮不做历史任务数据重写；已有审批缺少 transfer/review content 时显示“历史内容未记录”；
- 生产环境必须明确使用 UTC 计算“本周到期”，API 返回 week 边界；若将来切 Workspace timezone，必须单独 migration/spec，不在客户端猜测；
- 交接说明、验收内容和退回原因可能含业务文本，禁止写入请求日志、WebSocket payload 或错误 details；数据库备份和访问控制按现有策略执行。

### 10.3 事务、并发和缓存

- 审批创建/决策必须在锁定 active membership、request、task 后执行；
- ActivityEvent、TaskApprovalRequest、Task、TaskOperation、WorkspaceChangeLog 必须同事务提交；
- WebSocket hint 只在 commit 后发送；
- Android cache 只保存 snapshot，不把 home 作为独立事实；home 刷新失败保留 last-known-good 并标 stale；
- PostgreSQL 索引 migration 可独立回滚；不得为回滚删除任务、请求或活动历史。

### 10.4 回滚门槛

- 新后端可在不升级 Android 的情况下继续处理旧 transition Review 请求；
- 新 Android 在旧后端上若缺少 canonical home 字段，应明确显示 compatibility/error，不把空数组当作“没有任务”；
- 在确认所有客户端已切换前，不删除旧 home 字段或旧 activity event type；
- 回滚应用版本不回滚已提交的交接/验收事实；旧客户端必须仍能读取六状态、owner、reviewer 和已解决请求。

## 11. 完成定义

只有同时满足以下条件才可把本计划标记为完成：

- Android 默认进入「清单 → 此刻」，三入口和三主体契约在双用户设备上通过；
- pending transfer 不改变 owner，approve 后 owner 只变更一次；
- review submit 原子进入 REVIEW，reviewer approve/return 权限正确，return 原因必填且 owner 不变；
- Task status 与 approval request status 可分别在 API、数据库、snapshot、changes、Android UI 中观察；
- 交接说明、验收内容、退回原因在 TaskApprovalRequest 和 ActivityEvent/任务活动 API 中可重放；
- home 去重、排序、count、自然周边界和分页测试通过；
- backend 全量 pytest、Flutter 全量 test/analyze、Web test/typecheck/build 和 Android 构建通过；
- staging migration/rollback/cursor expiry/双设备 smoke 通过；
- 现有用户未提交的 Web 文件未被本次计划文档创建动作覆盖或提交。
