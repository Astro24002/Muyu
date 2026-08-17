# Phase 3 Delay And Blocking Design

## 1. 目标

在 Phase 2 Task Core 的任务闭环上增加延期和阻塞事实记录。用户可以明确说明任务为什么延期、延期到何时、当前在等待什么，以及解除阻塞后由谁继续处理。所有变化继续通过现有任务领域服务在单个数据库事务中写入任务、历史和活动事件。

本阶段不实现状态冲突、评论、事件、循环任务、首页聚合或统计接口。

## 2. 范围

- `DelayRecord` 不可修改、不可删除，只允许追加；
- 延期原因枚举：`NO_TIME`、`TOO_LARGE`、`NOT_WILLING`、`FORGOT`、`WAITING_PARTNER`、`INTERRUPTED`、`OTHER`；
- `OTHER` 必须填写补充说明；
- 延期必须存在原截止时间，新截止时间必须晚于原截止时间且至少相差一分钟；
- 任务响应提供延期次数和累计延期分钟数，单独接口返回完整延期记录；
- `TODO` 或 `IN_PROGRESS` 任务可以进入 `WAITING`；
- 进入 `WAITING` 必须填写阻塞原因和解除后负责人，可选填写等待用户；
- 解除阻塞后自动进入 `IN_PROGRESS`，并切换到预先记录的负责人；
- `WAITING` 任务的当前负责人在解除前保持原值，恢复负责人单独保存在 `resume_handler_id`；
- `DONE`、`CANCELLED` 任务仍可按现有规则重开；从 `WAITING` 完成或取消时清空阻塞字段；
- 每次阻塞、解除阻塞和延期都递增任务版本并追加活动事件；阻塞/解除阻塞追加状态历史，解除阻塞时负责人变化再追加负责人历史。

## 3. 数据模型

### 3.1 `delay_records`

新增 Alembic `0003_delay_blocking` 迁移和 ORM 模型：

```text
id
task_id
user_id
original_due_at
new_due_at
delayed_at
delay_duration_minutes
reason
note
created_at
```

`task_id` 和 `user_id` 外键使用 `RESTRICT`，任务删除前必须保留审计记录；延期记录不提供更新和删除接口。`reason` 和 `delay_duration_minutes` 由领域服务再次校验，不能只依赖 HTTP/Pydantic 校验。

### 3.2 `tasks` 既有阻塞字段

Phase 2 已创建以下字段，本阶段启用它们，不新增重复表：

- `blocked_reason`：阻塞原因；
- `blocked_since`：进入 `WAITING` 的 UTC 时间；
- `resume_handler_id`：解除阻塞后继续处理的参与人；
- `waiting_for_user_id`：可选的固定用户。

`status` 继续使用字符串值 `TODO`、`IN_PROGRESS`、`WAITING`、`DONE`、`CANCELLED`。`current_handler_id` 在等待期间保留最近一次负责人，避免破坏 Phase 2 的非空约束。

## 4. 领域规则和事务

### 4.1 延期

`TaskService.delay` 接收任务 ID、操作用户、新截止时间、原因和备注：

1. 任务必须存在、未软删除且当前 `due_at` 不为空；
2. 新截止时间必须晚于当前截止时间至少一分钟；
3. 原因必须属于固定枚举；`OTHER` 时备注去除首尾空白后不能为空，其他原因备注可选；
4. 在同一事务内插入 `DelayRecord`、更新 `tasks.due_at`、递增 `version` 和 `updated_at`，追加 `TASK_DELAYED` 活动事件；
5. 原截止时间来自事务开始时读取的任务值，接口不允许直接覆盖延期历史。

累计延期分钟数为该任务全部 `DelayRecord.delay_duration_minutes` 之和。连续延期按每次操作时的当前截止时间计算，不与首次截止时间重复累计。

### 4.2 进入阻塞

`TaskService.block` 只允许 `TODO` 或 `IN_PROGRESS`：

1. 阻塞原因去除首尾空白后长度为 1-2000；
2. `resume_handler_id` 必须是任务参与人；
3. `waiting_for_user_id` 如果提供，必须是固定用户；
4. 设置 `status=WAITING`、`blocked_reason`、`blocked_since`、`resume_handler_id` 和 `waiting_for_user_id`；
5. 追加状态历史和 `TASK_BLOCKED` 活动事件，并递增 `version`、`status_version`。

### 4.3 解除阻塞

`TaskService.unblock` 只允许 `WAITING`：

1. 读取并保留 `resume_handler_id`，其值必须仍是参与人；
2. 设置 `status=IN_PROGRESS`、`current_handler_id=resume_handler_id`，清空全部阻塞字段；
3. 如负责人发生变化，追加 `TaskHandlerHistory`；
4. 追加状态历史和 `TASK_UNBLOCKED` 活动事件，并递增版本；
5. 整个操作与活动事件在同一事务中提交。

从 `WAITING` 直接完成或取消时，沿用 Phase 2 状态动作，但必须同时清空阻塞字段，避免留下与当前状态矛盾的等待信息。

## 5. HTTP API

所有接口需要 Access Token，沿用现有统一错误格式和 `X-Request-ID`：

```text
POST /api/tasks/{task_id}/delay
GET  /api/tasks/{task_id}/delays
POST /api/tasks/{task_id}/block
POST /api/tasks/{task_id}/unblock
```

延期请求：

```json
{
  "new_due_at": "2026-08-20T12:00:00Z",
  "reason": "NO_TIME",
  "note": "可选说明"
}
```

阻塞请求：

```json
{
  "blocked_reason": "等待对方确认时间",
  "resume_handler_id": "uuid",
  "waiting_for_user_id": "uuid"
}
```

任务响应新增：

```text
blocked_reason
blocked_since
resume_handler_id
waiting_for_user_id
delay_count
total_delay_minutes
```

延期记录响应包含全部记录字段。业务错误使用稳定代码：`TASK_NOT_FOUND`、`INVALID_DELAY_REASON`、`DELAY_NOTE_REQUIRED`、`DUE_AT_REQUIRED`、`INVALID_DELAY_TIME`、`INVALID_BLOCK_REASON`、`INVALID_RESUME_HANDLER`、`INVALID_WAITING_USER`、`INVALID_TASK_TRANSITION`。

## 6. Flutter 交互

- 任务列表对 `WAITING` 显示明确状态标签，并保留刷新后的阻塞字段；
- 详情页对 `TODO/IN_PROGRESS` 提供“阻塞”和“延期”；
- 阻塞表单包含原因、解除后负责人和可选等待用户；
- `WAITING` 详情显示阻塞原因、等待用户和恢复负责人，并提供“解除阻塞”；
- 延期表单包含新截止时间、固定原因菜单和条件显示的补充说明；
- 详情页显示延期次数、累计延期分钟和不可编辑的延期记录；
- API 错误保留在当前页面，不清空已输入内容；
- 不新增首页或冲突专区，避免提前进入 Phase 4/7。

## 7. 测试和验收

- SQLite 和 PostgreSQL 迁移检查 `delay_records`、索引、外键和不可变记录路径；
- 领域测试覆盖三次延期、累计时间、原因/时间校验、阻塞必填、恢复负责人、等待用户、解除阻塞负责人历史、从等待完成/取消和活动事件顺序；
- HTTP 测试覆盖认证、请求校验、稳定业务错误、延期查询、阻塞/解除阻塞及双方读取一致；
- Flutter 模型、仓储、控制器和详情表单测试覆盖 `WAITING`、延期记录和错误保留；
- `make test`、Web/Android 构建、PostgreSQL smoke 和 API 重启持久性全部通过后，更新 `docs/05-development-status.md` 并提交。

## 8. 兼容和迁移

`0003_delay_blocking` 只新增 `delay_records` 表；Phase 2 已存在的任务阻塞字段直接启用，不修改 users、sessions 或既有任务数据。既有任务 API 字段保持兼容，仅在响应中追加可空阻塞字段和非负延期统计字段。
