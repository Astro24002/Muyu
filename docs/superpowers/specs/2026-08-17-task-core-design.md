# Phase 2 Task Core Design

## 目标

在现有双用户认证基础上实现可实际使用的任务闭环：创建任务、分配参与人和当前负责人、开始、转交、完成、取消、重开，并支持一层子任务、个人排序和完整活动审计。Android 与 Web 使用同一组 Flutter 页面和 REST API。

## 范围

本阶段包含路线图 Phase 2：

- 任务创建、列表、详情、编辑和软删除；
- 一名或两名参与人；
- 唯一当前负责人及负责人转交；
- `TODO`、`IN_PROGRESS`、`DONE`、`CANCELLED` 状态动作；
- 一层子任务，父子状态互相独立；
- 计划开始时间、截止时间和预计分钟数；
- 每名用户独立的任务展示顺序；
- 任务状态历史、负责人历史和追加式活动记录；
- Flutter 任务列表、创建/编辑、详情和状态操作。

本阶段不包含 `WAITING` 操作、延期、状态冲突、评论、循环任务和统计。这些能力分别按 Phase 3-8 实施。数据库保留 `WAITING` 枚举值和后续所需字段，但本阶段 API 不允许进入该状态。

## 数据模型

新增以下表：

- `tasks`：技术设计中定义的完整任务字段。`status` 使用字符串枚举；`version` 和 `status_version` 从 1 开始；删除写入 `deleted_at`。
- `task_assignees`：`task_id + user_id` 联合主键；参与人数量由服务层限制为 1-2。
- `task_user_positions`：`user_id + task_id` 联合主键，`position` 为非负整数。
- `task_status_history`：每次状态变化追加一行。
- `task_handler_history`：每次负责人变化追加一行。
- `activity_events`：通用追加式审计表，JSON 字段保存前后快照和动作载荷。

子任务继续使用 `tasks.parent_task_id`。创建子任务时父任务必须存在且本身没有父任务；API 拒绝第二层嵌套。软删除父任务不会隐式删除子任务，存在未删除子任务时拒绝删除父任务，避免形成不可见孤儿。

## 领域规则

- 标题去除首尾空白后长度为 1-200；描述最多 5000 字符。
- 参与人必须是系统固定用户，数量为 1-2 且不可重复。
- 当前负责人必须是参与人之一。
- 创建任务时状态固定为 `TODO`，创建人取当前登录用户。
- 创建后为两名参与人追加个人排序记录，默认排在各自现有任务末尾。
- 普通字段更新和排序更新递增 `version`；状态动作同时递增 `version` 和 `status_version`。
- `start`：`TODO -> IN_PROGRESS`。
- `complete`：`TODO/IN_PROGRESS -> DONE` 并设置 `completed_at`。
- `cancel`：`TODO/IN_PROGRESS -> CANCELLED`。
- `reopen`：`DONE/CANCELLED -> TODO` 并清空 `completed_at`。
- `transfer` 不改变状态，新负责人必须在参与人中。
- PATCH 不允许直接修改状态、负责人、创建人、版本和审计字段。
- 每个写操作在同一数据库事务内写入业务表、历史表和 `activity_events`。

本阶段返回 `status_version`，但不要求客户端提交预期版本；Phase 4 将在不改变响应模型的前提下增加冲突记录和 `expected_status_version` 校验。

## HTTP API

所有接口需要 Access Token：

```text
GET    /api/tasks
POST   /api/tasks
GET    /api/tasks/{task_id}
PATCH  /api/tasks/{task_id}
DELETE /api/tasks/{task_id}
POST   /api/tasks/{task_id}/start
POST   /api/tasks/{task_id}/transfer
POST   /api/tasks/{task_id}/complete
POST   /api/tasks/{task_id}/reopen
POST   /api/tasks/{task_id}/cancel
GET    /api/tasks/{task_id}/events
GET    /api/me/tasks/order
PUT    /api/me/tasks/order
```

`GET /api/tasks` 默认返回未删除的顶层任务，按当前用户个人排序在前、未排序任务按创建时间倒序。可用 `parent_task_id` 查询某个父任务的子任务。详情响应包含同一任务字段及 `assignee_ids`，客户端单独查询子任务列表。

业务错误使用现有统一错误契约：不存在或已删除返回 `404 TASK_NOT_FOUND`；非法状态转换、无效参与人、第二层子任务和存在子任务时删除返回 `409` 或 `422` 的稳定业务代码。

## Flutter 客户端

登录后主壳层使用底部导航：任务、账户。任务页是默认页。

- 任务列表按服务端顺序展示，提供状态筛选和刷新；空状态直接提供创建入口。
- 创建/编辑表单包含标题、描述、参与人、当前负责人、计划开始、截止时间、预计分钟数和可选父任务。
- 详情页展示负责人、参与人、时间字段、状态动作和子任务列表。
- 状态动作只显示当前状态允许的命令；转交使用成员选择菜单。
- 错误保留在当前页面，以现有 API 错误消息显示，不清空用户输入。
- 本阶段排序 API 完成并测试，拖拽排序 UI 放到后续首页/列表体验优化，不阻塞 Task Core 闭环。

## 测试与验收

- Alembic 在 SQLite 和 PostgreSQL 创建全部任务表、外键与唯一约束。
- 仓储/服务测试覆盖创建、子任务层级、参与人校验、状态转换、转交、软删除、排序及审计事务。
- HTTP 契约测试以真实认证请求覆盖完整闭环及稳定错误响应。
- Flutter 测试覆盖 JSON 模型、仓储请求、列表空态、创建成功和详情状态动作。
- 完整验收运行 `make test`，再在干净 PostgreSQL Compose 数据卷执行任务 smoke：两个用户登录、创建共同任务、开始、转交、创建子任务、完成、双方读取一致。

## 兼容与迁移

新增迁移只创建新表，不修改现有 `users` 和 `sessions` 数据。现有认证 API 和客户端登录流程保持兼容。API CORS 方法增加 `PUT` 和 `DELETE`。

---

## 历史决策说明（2026-09-01）

本文保留当时的设计正文；其中关于任务参与人、`task_assignees`、`assignee_ids` 及参与人约束的决定已被[移除任务参与人模型设计](./2026-09-01-remove-task-participants-design.md)取代。当前实现只保留 `current_handler_id` 作为唯一负责人，本文不再作为当前实现依据。
