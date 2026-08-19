# Phase 4 Status Conflicts Design

## 1. 目标

在现有 Task Core 和 Phase 3 延期/阻塞闭环上增加同一任务状态的乐观并发控制。两台设备基于同一个旧状态版本提交不同状态时，服务端必须保留先成功的状态、记录后到的提议并返回可消费的 `409`，不能静默覆盖。

本阶段继续使用现有任务领域服务、状态历史和追加式活动记录，不引入 WebSocket、消息队列或全局任务锁。冲突记录不会成为任务状态，也不会阻止普通任务操作。

## 2. 范围与非目标

包含：

- 状态动作的 `expected_status_version` 校验；
- `task_status_conflicts` 和 `task_conflict_approvals` 持久化模型及迁移；
- 过期状态请求的 409 契约和冲突记录创建；
- 冲突列表、详情和双方确认接口；
- 双方确认相同目标状态后的原子合并；
- 新状态提交使旧冲突进入 `SUPERSEDED`；
- 冲突创建、替代、确认和解决的活动审计；
- Flutter 冲突专区、冲突详情和确认操作。

不包含：

- 普通标题、描述、截止时间或参与人字段的冲突；
- 任务级锁定、实时推送、评论、首页聚合、重要事件和统计；
- 第三方用户或多于两个固定用户的审批模型。

## 3. 核心决策

### 3.1 受并发控制的操作

以下操作属于状态写入，HTTP 请求必须携带 `expected_status_version`：

```text
start
complete
reopen
cancel
block
unblock
```

延期、转交、普通字段更新和个人排序不检查 `status_version`。所有状态写入仍递增任务的 `version` 和 `status_version`；延期等非状态写入只递增 `version`。

HTTP 层要求版本字段，领域服务保留 `None` 的兼容默认值，仅供已有内部调用和迁移测试使用；新客户端和公开 API 不得省略版本字段。

### 3.2 事务与锁

状态动作和冲突审批在事务开始时对任务行执行 `SELECT ... FOR UPDATE`，随后重新读取任务的 `status_version`。PostgreSQL 使用行锁保证并发请求只有一个成功；SQLite 测试环境使用同一事务边界验证行为，不能依赖 SQLite 的锁语义提供生产并发保证。

过期版本判断在锁内完成。过期请求不修改任务状态、`version` 或 `status_version`，只写入冲突记录和 `CONFLICT_DETECTED` 活动事件。

### 3.3 冲突快照

每个冲突保存请求所基于的完整状态快照，而不是只保存当前任务值：

- `base_status_version`：客户端提交的旧版本；
- `base_status`：该版本对应的状态；
- `current_status_version`：服务端发现冲突时的版本；
- `current_status`：服务端当时的状态；
- `proposed_status`：过期请求试图提交的目标状态；
- `proposed_payload`：原始状态动作的必要载荷；
- `proposed_by`：提交过期请求的固定用户。

`TaskStatusHistory` 新增非空 `status_version`。迁移会按每个任务的 `changed_at`、`id` 顺序，将既有历史从 1 开始回填；之后每次状态写入在插入历史时写入新版本。这样服务端可以可靠地从 `base_status_version` 还原 `base_status`，不信任客户端上报的状态文本。

过期请求仍须先根据 `base_status` 校验原始状态动作是否合法；非法动作不创建冲突记录。这样冲突只代表一个当时可执行、后来因并发而过期的真实提议。

同一任务、同一基准版本、同一提议用户、同一目标状态和相同动作载荷的已有 `OPEN` 冲突重复提交时复用原记录，不重复产生冲突事件。

### 3.4 冲突状态和替代

冲突状态为：

```text
OPEN -> RESOLVED
OPEN -> SUPERSEDED
```

任何任务状态成功写入后，服务端将该任务上所有基准版本早于新 `status_version` 的 `OPEN` 冲突标记为 `SUPERSEDED`，写入 `resolved_at`，并追加 `CONFLICT_SUPERSEDED` 事件。替代不回滚新状态，也不阻止后续状态操作。

### 3.5 双方确认与合并

“双方”固定指系统初始化的两名用户，而不是根据任务参与人动态缩小审批范围。每名用户在一个冲突上最多保留一条审批；重复提交会更新自己的 `approved_status` 和 `approved_at`，接口保持幂等。

冲突仍为 `OPEN` 时：

1. 用户提交一个合法目标状态；
2. 若两名用户的审批状态不同，冲突保持 `OPEN`；
3. 若两名用户审批相同，服务端锁定任务并再次确认冲突仍为 `OPEN` 且任务的 `status_version` 等于冲突创建时的 `current_status_version`；
4. 条件满足时，在同一事务内执行状态转换、写入状态历史、更新冲突为 `RESOLVED`、记录 `resolved_status` 和 `resolved_at`，并追加普通状态事件及 `CONFLICT_RESOLVED` 事件；
5. 如果目标状态已经等于当前状态，则不重复改变任务状态，但仍可将冲突标记为 `RESOLVED` 并记录解决事件；
6. 如果期间已有新状态写入，则将冲突标记为 `SUPERSEDED`，审批接口返回稳定的 `CONFLICT_SUPERSEDED` 业务错误。

审批目标必须是当前状态允许的状态转换目标；非法目标返回 422/稳定业务错误，不改变审批记录或冲突状态。若目标为 `WAITING`，审批目标必须等于冲突原始提议的 `proposed_status`，并重放 `proposed_payload` 中的 `blocked_reason`、`resume_handler_id` 和 `waiting_for_user_id`；不允许在审批时凭空构造新的阻塞载荷。

## 4. 数据模型

### 4.1 `task_status_history` 扩展

新增：

```text
status_version  integer not null
```

唯一性由 `(task_id, status_version)` 保证。历史记录仍不可修改或删除。

### 4.2 `task_status_conflicts`

```text
id                        UUID primary key
task_id                   UUID not null, RESTRICT
base_status_version       integer not null
base_status               string not null
current_status_version    integer not null
current_status            string not null
proposed_status           string not null
proposed_payload          JSON not null
proposed_by               UUID not null, RESTRICT
resolved_status           string nullable
status                    OPEN / RESOLVED / SUPERSEDED
created_at                UTC timestamp not null
resolved_at               UTC timestamp nullable
```

索引：`task_id`、`status`，以及用于去重的 `(task_id, base_status_version, proposed_by, proposed_status, status)` 查询索引。任务采用软删除时保留冲突记录和审计数据；当前代码没有物理删除任务的应用路径，外键使用 `RESTRICT` 作为未来物理删除的保护。

### 4.3 `task_conflict_approvals`

```text
conflict_id       UUID not null, RESTRICT
user_id           UUID not null, RESTRICT
approved_status   string not null
approved_at       UTC timestamp not null
```

主键为 `(conflict_id, user_id)`。每个冲突最多两条审批记录，用户必须是两名固定用户之一。

## 5. HTTP 契约

### 5.1 状态动作

统一请求体：

```json
{
  "expected_status_version": 3
}
```

`block` 在此基础上增加既有字段：

```json
{
  "expected_status_version": 3,
  "blocked_reason": "等待对方确认时间",
  "resume_handler_id": "uuid",
  "waiting_for_user_id": "uuid"
}
```

版本过期时返回：

```http
409 Conflict
```

```json
{
  "code": "STATUS_CONFLICT",
  "message": "task status version is stale",
  "details": {
    "conflict_id": "uuid",
    "base_status_version": 2,
    "base_status": "TODO",
    "current_status_version": 3,
    "current_status": "IN_PROGRESS",
    "proposed_status": "DONE",
    "proposed_payload": {},
    "proposed_by": "uuid"
  }
}
```

### 5.2 冲突专区

```text
GET  /api/conflicts
GET  /api/conflicts/{conflict_id}
POST /api/conflicts/{conflict_id}/approve
```

审批请求：

```json
{
  "approved_status": "DONE"
}
```

列表默认返回当前用户可见的 `OPEN` 冲突，按 `created_at` 倒序；详情返回任务摘要、冲突快照、当前状态、状态和两条审批记录。审批成功返回完整冲突响应；若第二个相同审批触发合并，响应中的 `status` 为 `RESOLVED`，并包含合并后的任务摘要。

稳定错误码：

```text
STATUS_CONFLICT
CONFLICT_NOT_FOUND
CONFLICT_SUPERSEDED
INVALID_CONFLICT_APPROVAL
CONFLICT_ALREADY_RESOLVED
```

## 6. Flutter 交互

- `TaskItem.statusVersion` 作为每次状态动作的 expected version；动作成功后用服务端返回任务替换本地任务；
- Repository 增加冲突模型、列表、详情和审批方法；409 映射为携带冲突详情的 typed failure，而不是丢失为普通字符串；
- 主 shell 增加“冲突”专区入口，显示 OPEN 数量和冲突列表；
- 冲突详情显示基准状态、当前状态、提议状态、提交人和双方审批，提供固定状态菜单和确认按钮；
- 状态动作发生 409 时，任务详情保留当前任务和表单状态，显示冲突提示并可进入冲突专区；
- 解决或替代后刷新任务与冲突列表；不使用 WebSocket，依靠进入页面和手动刷新读取最新状态；
- 移动端保持单列布局，不增加首页或时间线内容。

## 7. 测试与验收

后端：

- 迁移测试覆盖历史版本回填、唯一约束、外键、索引和 SQLite/PostgreSQL；
- 领域测试覆盖同版本首个成功、过期请求建冲突、重复冲突幂等、双方不同意、双方同意合并、非法审批、期间新状态导致 `SUPERSEDED`；
- HTTP 测试覆盖六类状态动作的 expected version、409 details、冲突列表/详情/审批、认证和双方读取一致；
- 活动事件顺序覆盖 `CONFLICT_DETECTED`、`CONFLICT_SUPERSEDED`、`CONFLICT_RESOLVED` 以及合并状态事件。

Flutter：

- 模型和 Repository 测试覆盖冲突 JSON、请求体、409 typed failure 和审批响应；
- Controller/widget 测试覆盖冲突入口、审批状态、错误保留和解决后刷新；
- `flutter analyze`、全量测试、Web/Android 构建通过。

集成：

- 新增双用户 smoke：同一 `status_version` 并发提交两个状态，验证一个成功、一个 409；双方对同一目标审批后验证任务合并、冲突关闭和事件顺序；再提交新状态验证旧冲突 `SUPERSEDED`；
- 干净 PostgreSQL Compose 卷、API 重启和迁移版本持久性验收通过后更新开发状态文档。

## 8. 兼容、迁移和回滚

- `0004_status_conflicts` 只扩展状态历史并新增两张冲突表，不修改既有任务状态值；
- 迁移先以可空形式添加 `task_status_history.status_version`，逐任务按历史顺序回填，再设置非空和唯一约束，兼容 SQLite 与 PostgreSQL；
- 旧客户端若继续调用状态接口会收到 422，不会绕过并发控制；发布客户端与 API 必须作为同一版本一起升级；
- 降级时保留迁移数据，不提供删除冲突审计记录的回滚路径；应用可暂时停止冲突写入，但不能将旧状态静默覆盖。
