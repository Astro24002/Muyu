# 双人协作行动管理系统技术设计（历史基线）

> **现行运行时架构**以 [云端协调双人协作架构设计](./superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md) 为唯一依据：PostgreSQL 是明文协作事实源，Android 与 Web 经 FastAPI 的 REST/WSS 协作。本文件记录 Phase 0-3 的历史 FastAPI/PostgreSQL、固定用户和共享密码设计，仅用于理解遗留实现；它不定义新系统的认证、数据、同步、冲突或发布路径。

## 1. 总体架构

第一版采用单体架构：

```text
Android App / Web Browser
          |
        HTTPS
          |
      Caddy / Nginx
          |
     FastAPI API
          |
      PostgreSQL
```

部署环境为个人 ECS 和 Docker Compose。实时同步暂不强制使用 WebSocket，客户端通过请求刷新或短轮询获取变化。

## 2. 客户端和后端

推荐 Flutter，同时支持 Android 和 Web，尽可能复用数据模型、API Client、状态管理、表单校验和业务逻辑。

Android 是主要终端，Web 用于长时间查看、任务整理、事件管理和数据分析。

后端使用 Python 3.12 和 FastAPI，目录边界如下：

```text
backend/app/main.py
backend/app/core/
backend/app/auth/
backend/app/user/
backend/app/task/
backend/app/event/
backend/app/recurring/
backend/app/comment/
backend/app/activity/
backend/app/analytics/
backend/alembic/
```

第一版使用 REST API，服务端负责校验状态转换、延期事务、循环任务幂等生成和冲突检测。Python 后端使用 FastAPI、SQLAlchemy 2.0、psycopg、Alembic、Pydantic Settings、bcrypt 和 PyJWT；测试使用 pytest 和 HTTPX。

## 3. 数据模型

### users

```text
id
phone             unique, immutable
password_hash
nickname
avatar_key        immutable
role
created_at
updated_at
```

系统启动时在空数据库中初始化两名用户。默认密码通过部署 Secret 注入，数据库只保存哈希。

### sessions

```text
id
user_id
refresh_token_hash
expires_at
revoked_at
created_at
```

Access Token 短期有效，Refresh Token 可撤销且只保存哈希。

### tasks

```text
id
parent_task_id       nullable
title
description
status
current_handler_id   nullable
blocked_reason       nullable
blocked_since        nullable
resume_handler_id    nullable
waiting_for_user_id  nullable
planned_start_at     nullable
due_at               nullable
estimated_minutes    nullable
completed_at         nullable
created_by
recurring_task_id    nullable
version
status_version
deleted_at           nullable
created_at
updated_at
```

状态：

```text
TODO
IN_PROGRESS
WAITING
DONE
CANCELLED
```

### task_assignees

```text
task_id
user_id
```

一个任务可关联一名或两名用户。

### task_user_positions

```text
user_id
task_id
position
updated_at
```

唯一约束：`unique(user_id, task_id)`。该字段是用户展示顺序，不是业务优先级。

### task_status_history

```text
id
task_id
from_status
to_status
changed_by
changed_at
```

### task_handler_history

```text
id
task_id
from_user_id
to_user_id
changed_by
changed_at
```

### delay_records

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

延期记录只允许新增，不允许修改或删除。

### events

```text
id
title
description
event_type
all_day
event_date         nullable
event_at           nullable
recurrence_rule    nullable
created_by
deleted_at         nullable
created_at
updated_at
```

事件类型：

```text
IMPORTANT_DATE
ANNIVERSARY
APPOINTMENT
TRIP
OTHER
```

日期事件使用 `event_date`，具体时刻事件使用 `event_at`。服务端保存绝对值，客户端按 `Asia/Shanghai` 展示倒计时。

### recurring_tasks

```text
id
title
description
recurrence_rule
next_occurrence_at
active
created_at
updated_at
```

第一版支持每日、每周、每月，时区固定为 `Asia/Shanghai`。

### task_instances

```text
id
recurring_task_id
task_id
due_at
```

唯一约束：`unique(recurring_task_id, due_at)`。错过多个周期时只生成当前实例，不补历史实例。每月 31 日在目标月份不存在时使用当月最后一天。

### comments

```text
id
task_id
user_id
content
created_at
```

MVP 评论只支持新增和查看，不支持编辑和删除。

### activity_events

统一追加式活动记录：

```text
id
actor_user_id
target_type
target_id
action
before_json
after_json
payload_json
aggregate_version
request_id
created_at
```

所有任务、子任务、负责人、状态、延期、评论、事件和冲突变化都必须写入。活动记录不可修改或删除。

事件类型示例：

```text
TASK_CREATED
TASK_UPDATED
TASK_ASSIGNEES_CHANGED
TASK_HANDLER_CHANGED
TASK_STATUS_CHANGED
TASK_BLOCKED
TASK_UNBLOCKED
TASK_DELAYED
TASK_COMPLETED
TASK_CANCELLED
TASK_REOPENED
SUBTASK_CREATED
SUBTASK_UPDATED
COMMENT_CREATED
CONFLICT_DETECTED
CONFLICT_RESOLVED
```

### task_status_conflicts

冲突只针对任务状态，不把任务本身标记为 `CONFLICT`：

```text
id
task_id
base_status
current_status
proposed_status
proposed_by
resolved_status
status              OPEN / RESOLVED / SUPERSEDED
created_at
resolved_at
```

### task_conflict_approvals

```text
conflict_id
user_id
approved_status
approved_at
```

双方确认同一最终状态后才合并。后续新的状态提交可以使旧冲突变为 `SUPERSEDED`，不锁住任务。

## 4. 核心业务规则

### 状态转换

```text
TODO -> IN_PROGRESS / WAITING / DONE / CANCELLED
IN_PROGRESS -> TODO / WAITING / DONE / CANCELLED
WAITING -> TODO / IN_PROGRESS / DONE / CANCELLED
DONE -> TODO / IN_PROGRESS
CANCELLED -> TODO
```

进入 `WAITING` 必须填写阻塞原因和解除阻塞后处理人。解除阻塞时自动恢复为 `IN_PROGRESS` 并设置该处理人。

### 延期

延期操作必须在同一事务内完成：

```text
DelayRecord
  + 更新 tasks.due_at
  + 更新 tasks.version
  + ActivityEvent
```

禁止直接覆盖截止时间历史。

### 完成和重开

完成时设置 `completed_at`。重新打开时清空当前 `completed_at`，但历史事件和状态记录保留。

### 并发控制

- 所有任务修改递增 `version`；
- 只有状态修改校验 `status_version`；
- 状态版本不一致返回 HTTP 409 并创建冲突记录；
- 普通字段采用字段级更新，尽量自动合并；
- 排序使用用户私有记录，不产生冲突。

## 5. API

### Auth 和用户

```text
POST  /api/auth/login
POST  /api/auth/refresh
POST  /api/auth/logout
GET   /api/me
PATCH /api/me
GET   /api/users
```

### 首页和任务

```text
GET    /api/home
GET    /api/tasks
POST   /api/tasks
GET    /api/tasks/:id
PATCH  /api/tasks/:id
DELETE /api/tasks/:id
POST   /api/tasks/:id/start
POST   /api/tasks/:id/transfer
POST   /api/tasks/:id/block
POST   /api/tasks/:id/unblock
POST   /api/tasks/:id/delay
POST   /api/tasks/:id/complete
POST   /api/tasks/:id/reopen
POST   /api/tasks/:id/cancel
GET    /api/tasks/:id/events
GET    /api/tasks/:id/comments
POST   /api/tasks/:id/comments
GET    /api/me/tasks/order
PUT    /api/me/tasks/order
```

### 事件和循环任务

```text
GET    /api/events
POST   /api/events
GET    /api/events/:id
PATCH  /api/events/:id
DELETE /api/events/:id

GET    /api/recurring-tasks
POST   /api/recurring-tasks
GET    /api/recurring-tasks/:id
PATCH  /api/recurring-tasks/:id
POST   /api/recurring-tasks/:id/pause
POST   /api/recurring-tasks/:id/resume
```

### 冲突和统计

```text
GET  /api/conflicts
GET  /api/conflicts/:id
POST /api/conflicts/:id/approve

GET /api/analytics/delay
GET /api/analytics/tasks
```

第一版统计实时计算，不保存汇总缓存。

## 6. API 约定

所有时间使用 ISO 8601。状态动作提交 `expected_status_version`。

版本过期时返回：

```http
409 Conflict
```

```json
{
  "code": "STATUS_CONFLICT",
  "conflict_id": "conflict-123",
  "current_status": "WAITING",
  "proposed_status": "DONE"
}
```

常见错误：

```text
400 BAD_REQUEST
401 UNAUTHORIZED
404 NOT_FOUND
409 CONFLICT
422 VALIDATION_ERROR
429 RATE_LIMITED
```

## 7. 时间规范

- 业务时区：`Asia/Shanghai`；
- 数据库存储绝对时间时使用 UTC；
- 日期型纪念日使用 date-only；
- API 时间使用 ISO 8601；
- 客户端展示统一转换为北京时间；
- 不保存剩余天数。

## 8. 安全与部署

- 只有 Caddy/Nginx 暴露公网；
- API 和 PostgreSQL 使用 Docker 内网；
- PostgreSQL 不暴露公网端口；
- 全站 HTTPS；
- 登录限流；
- Access Token 短期有效；
- Refresh Token 可撤销且只保存哈希；
- 默认密码通过 Secret 注入；
- 数据库独立 Volume；
- 每日备份并保留多个版本。

## 9. 后续扩展

预留但不进入 MVP：

- WebSocket；
- Android Push；
- AI 任务拆解；
- 自动任务排序；
- 智能任务推荐；
- 更复杂的拖延分析；
- 任意 RRULE 编辑。
