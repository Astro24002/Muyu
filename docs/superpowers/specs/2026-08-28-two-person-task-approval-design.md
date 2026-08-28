# Muyu 双人任务审批设计

## 1. 目的与适用范围

本规格定义 Muyu 任务、子任务、评论和任务变更审批的权限模型。它补充并覆盖 `2026-08-26-lightweight-action-first-design.md` 中“本阶段不加入审批”的旧表述；项目仍保持轻量，不引入通用团队协作平台的组织模型。

本规格只适用于一个 Workspace 内的固定两人协作。系统不存在跨 Workspace 的任务访问，也不存在管理员、群组审批、角色层级或多人投票。

## 2. 不可变业务约束

1. 一个 Workspace 最多拥有两名 `ACTIVE` 成员。
2. 两名成员权限对等；“任务负责人”是任务字段，不是 Workspace 角色。
3. 所有审批均为一人发起、另一人审批，且每个请求只有一个审批人。
4. 审批人由服务端根据 Workspace 成员关系自动确定，客户端不能选择审批人。
5. 发起人和审批人必须是同一 Workspace 的两名不同成员。
6. 未验证设备只能读取；已验证 Android 设备或有效 Web 会话才能执行允许的写操作。
7. 所有写入、审批、拒绝、取消和冲突结果都必须进入同一事务中的操作记录、活动记录和 Workspace 同步游标。

## 3. 任务与子任务

任务和子任务使用同一个 `Task` 模型。子任务仅通过 `parent_task_id` 表示逻辑归属，不创建第二套子任务表或独立权限模型。

- `parent_task_id = NULL` 表示顶层任务；
- `parent_task_id != NULL` 表示子任务；
- 首版只允许一层子任务，禁止子任务再创建子任务；
- 顶层任务和子任务都分配全局唯一、不可变的人类可读任务编号，例如 `26080001`、`26080002`；
- 数据库主键仍使用 UUID，任务编号只用于展示、搜索和沟通；
- 编号由服务端原子生成，客户端不能自定义或重用。

`current_handler_id` 是唯一的“任务负责人”字段。首版不新增 `owner_user_id`。任务负责人必须是该 Workspace 的成员，并由服务端在每次变更时校验。

任务的进度只在 `IN_PROGRESS` 状态下显示，允许值为 `20`、`40`、`60`、`80`；`TODO` 隐含 0，`DONE` 隐含 100。四象限是可空任务标签 `Q1`、`Q2`、`Q3`、`Q4`，不创建独立的优先级实体。

## 4. 直接修改与审批修改

### 4.1 任务负责人直接修改

任务负责人可以直接修改任务允许字段，服务端在事务中检查：

- 当前会话属于任务所在 Workspace；
- 当前设备或 Web 会话具备写权限；
- 当前用户等于 `current_handler_id`；
- 客户端提交的 `base_field_versions` 与服务端当前字段版本一致。

允许直接修改的字段包括标题、描述、截止时间、计划时间、进度、状态、四象限、参与人和负责人转交。具体字段仍受任务状态转换规则约束。

### 4.2 另一位成员发起请求

另一位成员可以查看任务，但修改受负责人保护的字段时必须创建审批请求。请求创建后不改变任务当前状态，客户端应显示“待负责人审批”。

服务端将 `approver_id` 固定为任务当前负责人，并拒绝：

- 发起人自己审批；
- 指定第三位用户审批；
- 跨 Workspace 的审批人；
- 负责人已变更后仍使用旧负责人审批的请求。

如果请求包含多个字段，审批时必须对整组字段进行版本校验；任一目标字段已经发生不兼容变化，请求整体进入 `CONFLICTED`，不得部分应用。

## 5. 评论与评论删除

评论正文创建后不可编辑，评论采用软删除：

- 评论作者可以直接删除自己的评论；
- 任务负责人删除他人评论时，必须创建 `COMMENT_DELETE` 请求；
- 此类请求的 `approver_id` 固定为评论作者，而不是任务负责人；
- 评论作者批准后，服务端设置 `deleted_at`、`deleted_by` 和删除操作记录；
- 评论已经删除、任务已经删除或评论版本发生变化时，待处理请求进入 `CONFLICTED` 或 `CANCELLED`，不能重复删除；
- 历史审计保留，界面可显示“评论已删除”的墓碑状态。

评论作者删除自己的评论不需要审批，但仍然要经过同一套权限、幂等、版本和审计流程。

## 6. 统一审批请求模型

所有需要另一方确认的动作使用一张统一的 `task_approval_requests` 表：

```text
TaskApprovalRequest
├── id                  UUID 主键
├── workspace_id        所属 Workspace
├── task_id             目标任务
├── comment_id          可空，评论动作使用
├── requester_id        发起人
├── approver_id         唯一审批人
├── request_type        请求类型
├── proposed_changes    规范化的建议变更 JSON
├── base_field_versions 发起时的字段版本 JSON
├── status              请求状态
├── request_id          客户端幂等键
├── created_at
├── reviewed_at
├── reviewed_by
├── rejection_reason
└── resolved_cursor     完成后的 Workspace cursor
```

请求类型固定为：

```text
TASK_UPDATE
QUADRANT_UPDATE
STATUS_UPDATE
TASK_DELETE
TASK_RESTORE
COMMENT_DELETE
ASSIGNEE_UPDATE
HANDLER_TRANSFER
```

请求状态固定为：

```text
PENDING
APPROVED
REJECTED
CONFLICTED
CANCELLED
```

同一个 `request_id` 在同一 Workspace 内重复提交必须返回原始结果，不得创建第二个请求或重复写入同步游标。

## 7. 请求生命周期

```text
发起人提交
    ↓
PENDING
    ├── 审批人批准 → APPROVED → 应用变更
    ├── 审批人拒绝 → REJECTED
    ├── 发起人撤回 → CANCELLED
    ├── 目标版本不一致 → CONFLICTED
    └── 任务/评论终止或负责人变化 → CANCELLED
```

规则如下：

1. 只有 `PENDING` 请求可以被审批、拒绝或撤回。
2. 发起人可以撤回自己尚未处理的请求。
3. 审批人只能处理发给自己的请求。
4. 审批前服务端必须锁定目标任务或评论并重新检查成员、设备、负责人、生命周期和字段版本。
5. 审批成功与目标变更、操作记录、活动记录和 cursor 更新必须在同一事务提交。
6. 审批请求不能绕过现有状态转换，例如不能通过请求直接把 `CANCELLED` 任务改回任意状态。
7. 负责人转交、任务删除或恢复后，受旧负责人语义影响的待处理请求自动取消，并记录原因。

## 8. API 与客户端视图

服务端提供统一的请求接口，资源路径始终嵌套在 Workspace 下，并由当前会话推导审批权限：

```text
POST  /api/v1/workspaces/{workspace_id}/approval-requests
GET   /api/v1/workspaces/{workspace_id}/approval-requests?box=incoming|outgoing
POST  /api/v1/approval-requests/{request_id}/approve
POST  /api/v1/approval-requests/{request_id}/reject
POST  /api/v1/approval-requests/{request_id}/cancel
```

客户端只需要两个入口：

- “待我审批”：列出 `approver_id = current_user` 且状态为 `PENDING` 的请求；
- “我发起的请求”：列出 `requester_id = current_user` 的请求及其最终状态。

审批详情必须显示任务/评论摘要、发起人、请求类型、建议变更、创建时间、版本冲突提示和批准/拒绝操作。客户端不能显示或编辑审批人选择器。

## 9. 同步、审计与幂等

以下动作全部产生可同步的操作事件：

- 创建、批准、拒绝、撤回和自动取消审批请求；
- 直接任务修改和评论自删除；
- 审批应用的任务/评论变更；
- `CONFLICTED` 结果。

WebSocket 只发送 Workspace 有新 cursor 的通知；Android 和 Web 随后通过快照或增量 changes API 获取完整结果。任何客户端都不能仅凭本地 UI 把待审批变更当作已生效事实。

审计记录至少包含 actor user/device、Workspace、目标任务或评论、request_id、动作、时间和非敏感原因。审批请求正文可以记录建议变更，但不得记录验证码、设备私钥或会话令牌。

## 10. 验收标准

- 第三个成员无法加入 Workspace，且不存在管理员绕过路径；
- A 发起的任务变更只能由 B 审批，B 发起的任务变更只能由 A 审批；
- 自己审批自己的请求、跨 Workspace 审批和未验证设备写入均被拒绝；
- 任务负责人可直接修改，另一位成员修改会生成 `PENDING` 请求且任务保持原值；
- 审批通过只应用一次，重复请求或重复审批保持幂等；
- 版本过期时请求进入 `CONFLICTED`，不会覆盖新数据；
- 评论作者可直接软删除自己的评论，负责人删除他人评论必须经过作者批准；
- 待处理、已完成、已拒绝、已冲突和已取消请求在 Android/Web 两端一致可见；
- 所有结果都有操作记录、活动记录和连续 Workspace cursor；
- 不新增 Project、Team、RBAC、群组审批、投票或离线事实源。

