# Muyu 轻量行动协作实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 FastAPI/PostgreSQL 云端事实源上补齐轻量任务协作闭环，并让 Android 与独立 Web 以同一快照提供“我的任务、列表、状态看板、阻塞/延期和冲突处理”。

**Architecture:** 保留现有 Workspace、Task、TaskAssignee、TaskStatusHistory、TaskComment、DelayRecord、TaskConflict、TaskOperation、cursor 和 WebSocket 模型，不新增 Project/Team/层级看板。所有写入继续由 FastAPI 在一个 PostgreSQL 事务中完成；客户端只保存可过期的快照，WebSocket 仅触发 snapshot/changes 刷新。任务状态在公共 API 中使用 `TODO`、`IN_PROGRESS`、`WAITING`、`DONE`、`CANCELLED`；数据库当前已有的 `COMPLETED` 值通过服务层做兼容映射，不建立第二套状态字段。

**Tech Stack:** Python 3.12、FastAPI、SQLAlchemy 2、PostgreSQL、Alembic、Flutter Android、TypeScript、Vite、Vitest、Dart `flutter_test`。

**Spec:** [docs/superpowers/specs/2026-08-26-lightweight-action-first-design.md](/home/muyu/Muyu/docs/superpowers/specs/2026-08-26-lightweight-action-first-design.md)

## Global Constraints

- 一个 Workspace 最多两名 ACTIVE 成员；本计划不新增 `Project`、`Team`、`Portfolio`、`Version`、`Sprint` 或 `Cycle` 数据层级。
- 固定公共状态为 `TODO`、`IN_PROGRESS`、`WAITING`、`DONE`、`CANCELLED`，看板列只投影 `Task.status`，不保存独立 board 状态。
- Task 只允许一层 Subtask；创建子任务时父任务必须是顶层任务，第二层请求返回稳定 422 错误。
- 所有写入沿用 `request_id` 幂等、字段/状态版本和 409 冲突协议；冲突不能静默覆盖服务端值。
- 延期记录、评论、状态历史和操作记录只追加，不提供物理删除或更新接口；删除仍是软删除。
- 网络失败时客户端只能展示可能过期的数据，不创建离线写入队列，也不把本地缓存当作事实源。
- 本阶段不实现任务依赖图、附件/对象存储、可配置工作流、Scrum/燃尽/资源报表、自动化、OKR、知识库或插件。
- Web 继续使用同源 `/api` 与 `credentials: include`；Flutter 继续只构建 Android；不新增必需外部服务或客户端依赖。
- 每个任务遵循 TDD：先写一个证明目标行为的失败测试，再做最小实现，运行专项测试、格式/类型检查后提交一个小 commit。

---

## 文件地图

实现者先按下面的边界定位代码，避免把领域规则塞进页面：

- `backend/app/db/enums.py`：公共状态与兼容映射的枚举定义。
- `backend/app/tasks/schemas.py`：任务创建、字段更新、状态/阻塞/延期/评论请求模型。
- `backend/app/tasks/service.py`：任务创建、子任务/参与人校验、字段更新、状态转换和版本冲突。
- `backend/app/tasks/delays.py`、`backend/app/tasks/comments.py`：追加式延期和评论领域操作。
- `backend/app/tasks/routes.py`：认证后的 REST 路由和稳定错误码。
- `backend/app/sync/service.py`：统一快照与增量资源投影。
- `backend/tests/tasks/test_lightweight_contract.py`、`backend/tests/httpapi/test_lightweight_routes.py`：领域和 HTTP 契约测试。
- `web/src/api/types.ts`、`web/src/api/client.ts`：snake_case API 边界和请求方法。
- `web/src/tasks/task-view-model.ts`：纯函数筛选、看板分组和提醒统计。
- `web/src/sync/workspace-sync.ts`：快照、cursor、写入和冲突状态的唯一协调者。
- `web/src/ui/workspace-view.ts`、`web/src/ui/task-detail-view.ts`：列表/看板/我的任务和任务操作 DOM。
- `web/test/task-view-model.test.ts`、`web/test/workspace-view.test.ts`：无网络的投影和交互测试。
- `client/lib/models/task.dart`、`client/lib/models/task_view.dart`：Dart 模型与纯视图投影。
- `client/lib/task/cloud_task_repository.dart`、`client/lib/sync/workspace_sync_controller.dart`：Android 写入与同步接口。
- `client/lib/screens/cloud_workspace_screen.dart`、`client/lib/screens/task_detail_screen.dart`：Android 轻量任务工作区。
- `client/test/models/task_view_test.dart`、`client/test/screens/cloud_workspace_screen_test.dart`：模型和 Widget 测试。
- `backend/tests/e2e/test_lightweight_workspace.py`、`scripts/smoke-lightweight-workspace.sh`：双用户跨客户端验收。
- `docs/05-development-status.md`、`docs/README.md`：范围、命令和实际证据记录。

---

### Task 1: 完成服务端轻量任务领域契约

**Files:**
- Modify: `backend/app/db/enums.py`
- Modify: `backend/app/tasks/schemas.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/app/sync/service.py`
- Create: `backend/tests/tasks/test_lightweight_contract.py`
- Create: `backend/tests/httpapi/test_lightweight_routes.py`

**Interfaces:**
- `TaskService.create(workspace_id, actor_user_id, request_id, title, description="", due_at=None, parent_task_id=None, assignee_ids=None, planned_start_at=None, estimated_minutes=None) -> Task`。标题去首尾空白；父任务必须是顶层；参与人只能是当前 Workspace 的 1-2 个 ACTIVE 成员；未传参与人时把创建人作为唯一参与人和当前处理人。
- `TaskService.patch(..., changes, base_field_versions) -> Task` 允许 `title`、`description`、`planned_start_at`、`due_at`、`estimated_minutes`、`current_handler_id`、`assignee_ids`；状态、版本、创建人和审计字段仍拒绝直接修改。负责人必须在参与人中，参与人替换在同一事务中更新 `task_assignees`。
- `TaskService.transition(workspace_id, actor_user_id, task_id, request_id, target_status, base_status_version, blocked_reason=None, resume_handler_id=None, waiting_for_user_id=None) -> Task`。接受公共 `DONE`，并将旧存储值 `COMPLETED` 规范化为 `DONE`；只执行固定转换，过期版本写入 `TaskConflict(target="status")` 并抛出 `field_conflict`。
- `TaskService.block(...)` 和 `TaskService.unblock(...)` 复用 `transition` 的事务边界：进入 `WAITING` 必填原因与恢复负责人；解除后进入 `IN_PROGRESS`、切换恢复负责人并清空阻塞字段。
- `TaskService.snapshot(task) -> dict` 必须返回 `assignee_ids`、`delay_count`、`total_delay_minutes` 和公共状态 `DONE`，不得返回空数组或固定零值。
- REST 新增/统一以下路径：
  - `POST /api/v1/tasks` 接受 `parent_task_id`、`assignee_ids`、`planned_start_at`、`estimated_minutes`。
  - `PATCH /api/v1/tasks/{task_id}` 使用现有字段版本体。
  - `POST /api/v1/tasks/{task_id}/transition` 体为 `{request_id,target_status,base_status_version,blocked_reason?,resume_handler_id?,waiting_for_user_id?}`。
  - `POST /api/v1/tasks/{task_id}/comments`、`GET /api/v1/tasks/{task_id}/comments`。
  - `POST /api/v1/tasks/{task_id}/delays`、`GET /api/v1/tasks/{task_id}/delays`。
  - `GET /api/v1/tasks/{task_id}/activity` 返回按时间升序的操作、评论和延期摘要。
  - 现有 `/api/v1/tasks/{task_id}/lifecycle` 保留为兼容别名，将 `complete/reopen/delete` 翻译到同一 `transition`/软删除实现；新客户端只使用 `transition`。

- [ ] **Step 1: 写领域失败测试**

在 `backend/tests/tasks/test_lightweight_contract.py` 写出以下断言，先不改生产代码：

```python
def test_create_one_level_subtask_and_assignees(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        parent = TaskService(session).create(workspace.id, user_a.id, uuid4(), "父任务")
        child = TaskService(session).create(
            workspace.id, user_a.id, uuid4(), "子任务", parent_task_id=parent.id,
            assignee_ids=[user_a.id, user_b.id],
        )
        assert child.parent_task_id == parent.id
        assert _assignees(session, child.id) == {user_a.id, user_b.id}
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).create(workspace.id, user_a.id, uuid4(), "二层", parent_task_id=child.id)
        assert error.value.code == "nested_task_not_allowed"

def test_transition_waiting_done_and_stale_status_creates_conflict(db_engine):
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "行动")
        TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "IN_PROGRESS", 1)
        waiting = TaskService(session).transition(
            workspace.id, user.id, task.id, uuid4(), "WAITING", 2,
            blocked_reason="等待确认", resume_handler_id=user.id,
        )
        assert waiting.status.value == "WAITING"
        done = TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "DONE", 3)
        assert TaskService(session).snapshot(done)["status"] == "DONE"
        with pytest.raises(TaskConflictError) as error:
            TaskService(session).transition(workspace.id, user.id, task.id, uuid4(), "TODO", 3)
        assert error.value.code == "field_conflict"
```

运行：`cd backend && python -m pytest tests/tasks/test_lightweight_contract.py -q`。预期失败原因为方法/字段尚未实现。

- [ ] **Step 2: 实现状态、参与人和子任务的最小领域逻辑**

在 `enums.py` 增加 `PUBLIC_TASK_STATUS` 映射（`TaskStatus.COMPLETED -> "DONE"`），在 `schemas.py` 增加严格的 `TransitionRequest` 并限制 `target_status` 字符串集合。扩展 `TaskService.create/patch`，使用 `select(WorkspaceMembership)` 校验成员，使用 `TaskAssignee` 行更新参与人；不要创建新表。将转换规则集中为：

```python
TRANSITIONS = {
    "TODO": {"IN_PROGRESS", "WAITING", "DONE", "CANCELLED"},
    "IN_PROGRESS": {"WAITING", "DONE", "CANCELLED"},
    "WAITING": {"IN_PROGRESS", "DONE", "CANCELLED"},
    "DONE": {"TODO"},
    "CANCELLED": {"TODO"},
}
```

`transition` 在 `with_for_update()` 后比较 `status_version`；成功时更新 `completed_at`/阻塞字段、追加 `TaskStatusHistory`、递增 `version` 和 `status_version`，并为旧 `COMPLETED` 返回 `DONE`。非法转换返回 `invalid_request`，第二层父任务返回 `nested_task_not_allowed`，版本过期创建 `TaskConflict(target="status")`（冲突值先转换成字符串）后返回 409。

- [ ] **Step 3: 修正快照派生字段并接入路由**

在 `snapshot` 中查询 `TaskAssignee`，以 `select(DelayRecord)` 聚合当前任务的记录数和分钟数；`SyncService.snapshot` 继续以这一个函数生成所有任务，避免 Web/Android 各自重算事实。将创建、transition、comment、delay 路由都通过 `_queue_hint` 发布同一 cursor，并把稳定错误映射为 `422 invalid_request`、`404 not_found`、`409 field_conflict/lifecycle_conflict`。

- [ ] **Step 4: 补 HTTP 契约失败测试并运行**

在 `backend/tests/httpapi/test_lightweight_routes.py` 使用现有认证 fixture，断言：创建请求可带 `parent_task_id`/`assignee_ids`；transition 成功响应是 `status == "DONE"` 且带 `status_version`；第二层子任务返回 422；过期 `base_status_version` 返回 409 且响应 `details.conflicts[0].field == "status"`；未认证仍返回 401。

运行：

```bash
cd backend
python -m pytest tests/tasks/test_lightweight_contract.py tests/httpapi/test_lightweight_routes.py -q
python -m compileall -q app alembic
```

- [ ] **Step 5: 提交领域垂直切片**

```bash
git add backend/app/db/enums.py backend/app/tasks backend/app/sync/service.py backend/tests/tasks/test_lightweight_contract.py backend/tests/httpapi/test_lightweight_routes.py
git commit -m "feat: complete lightweight task domain contract"
```

---

### Task 2: 补齐延期、评论、活动和快照一致性

**Files:**
- Modify: `backend/app/tasks/delays.py`
- Modify: `backend/app/tasks/comments.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/app/sync/service.py`
- Create: `backend/tests/tasks/test_lightweight_timeline.py`
- Modify: `backend/tests/e2e/test_cloud_protocol.py`

**Interfaces:**
- `add_delay(...)` 保证新截止时间晚于当前截止时间至少一分钟，`OTHER` 必须有非空备注；记录不可更新/删除，并在同一事务更新任务 `due_at`、版本和 cursor。
- `list_delays(...) -> list[DelayRecord]` 返回完整记录字段：`id/task_id/actor_user_id/original_due_at/new_due_at/delayed_at/delay_duration_minutes/reason/note/created_at`。
- `list_activity(session, workspace_id, task_id) -> list[dict]` 合并 `TaskOperation`、`TaskComment`、`DelayRecord`，按 `created_at,id` 升序；只读取当前 Workspace 的任务。
- `SyncService.snapshot(workspace_id)` 仍是客户端唯一事实快照，任务中的 `delay_count`、`total_delay_minutes` 与 `GET /delays` 的记录总和一致。

- [ ] **Step 1: 写时间线和不可变记录测试**

在 `backend/tests/tasks/test_lightweight_timeline.py` 覆盖三次连续延期累计分钟、`OTHER` 缺备注、过早新截止时间、评论幂等、活动排序和软删除后拒绝评论/延期。示例：

```python
def test_three_delays_are_append_only_and_match_snapshot(db_engine):
    with Session(db_engine) as session:
        user, workspace = _workspace(session)
        task = TaskService(session).create(workspace.id, user.id, uuid4(), "追踪")
        task.due_at = datetime(2026, 8, 27, tzinfo=timezone.utc)
        session.commit()
        for minute in (60, 120, 180):
            add_delay(session, workspace.id, user.id, task.id,
                      task.due_at + timedelta(minutes=minute), "NO_TIME", request_id=uuid4())
            session.commit()
        refreshed = session.get(Task, task.id)
        snapshot = TaskService(session).snapshot(refreshed)
        assert snapshot["delay_count"] == 3
        assert snapshot["total_delay_minutes"] == 360
```

运行：`cd backend && python -m pytest tests/tasks/test_lightweight_timeline.py -q`，预期先失败。

- [ ] **Step 2: 修复延期聚合和完整记录响应**

让 `TaskService.snapshot` 使用同一 UTC `now` 和 `DelayRecord` 查询；路由响应不丢失 `delayed_at`、`actor_user_id`、`delay_duration_minutes`。对重复 `request_id` 返回原记录，不重复增加任务版本或 cursor。

- [ ] **Step 3: 增加活动读取路由**

实现 `list_activity`，将操作类型规范成 `{"kind":"operation"|"comment"|"delay", ...}`，禁止返回请求体中的 token、cookie 或 proof。新增 `GET /api/v1/tasks/{task_id}/activity`，任务不属于 actor Workspace 时统一 404。

- [ ] **Step 4: 扩展真实双用户协议测试**

在 `backend/tests/e2e/test_cloud_protocol.py` 的现有登录流程后追加：用户 A 创建父任务和子任务、用户 B 读取；A 延期并阻塞、B 读取同一 `delay_count/blocked_reason`；A 添加评论、B 读取活动；A 通过 transition 完成后双方 snapshot 的 cursor 和状态一致。测试只使用临时数据库和现有 fake SMS，不调用生产短信。

- [ ] **Step 5: 运行专项测试并提交**

```bash
cd backend
python -m pytest tests/tasks tests/e2e/test_cloud_protocol.py -q
python -m compileall -q app alembic
git add backend/app/tasks backend/app/sync/service.py backend/tests/tasks backend/tests/e2e/test_cloud_protocol.py
git commit -m "feat: expose lightweight task timeline"
```

---

### Task 3: 统一 Web/Android API 模型、投影和同步写入

**Files:**
- Modify: `web/src/api/types.ts`
- Modify: `web/src/api/client.ts`
- Create: `web/src/tasks/task-view-model.ts`
- Modify: `web/src/sync/workspace-sync.ts`
- Create: `web/test/task-view-model.test.ts`
- Create: `web/test/workspace-actions.test.ts`
- Modify: `client/lib/models/task.dart`
- Create: `client/lib/models/task_view.dart`
- Modify: `client/lib/task/cloud_task_repository.dart`
- Modify: `client/lib/sync/workspace_sync_repository.dart`
- Modify: `client/lib/sync/workspace_sync_controller.dart`
- Create: `client/test/models/task_view_test.dart`
- Modify: `client/test/task/cloud_task_repository_test.dart`

**Interfaces:**
- Web `TaskStatus = 'TODO' | 'IN_PROGRESS' | 'WAITING' | 'DONE' | 'CANCELLED'`；`TaskItem` 增加 `status_version`、阻塞和延期字段，保持 snake_case。
- Web `ApiClient` 新增：
  - `transitionTask(id, input: {requestId, targetStatus, baseStatusVersion, blockedReason?, resumeHandlerId?, waitingForUserId?})`；
  - `getTaskComments(id)`、`addTaskComment(id, {requestId, body})`；
  - `getTaskDelays(id)`、`addTaskDelay(id, {requestId, newDueAt, reason, note?})`；
  - `getTaskActivity(id)`。
- Web 纯函数：`filterMyTasks(tasks, userId)`, `groupTasksByStatus(tasks)`, `deriveTaskSummary(tasks, now) -> {mine, blocked, dueSoon, overdue, openConflicts}`。`dueSoon` 定义为未来 24 小时内且未完成/取消；函数不修改输入。
- `WorkspaceSyncController` 新增 `transitionTask`, `addComment`, `addDelay`，成功响应按服务端 task/cursor 合并；409 状态冲突进入现有 `conflicts`，网络失败设置 `stale`，不写入离线队列。
- Dart `TaskView` 暴露同名筛选/分组/summary 静态方法；`CloudTaskRepository` 提供 `transition`, `addComment`, `addDelay`，每个请求沿用固定 request id 和字段版本。

- [ ] **Step 1: 写投影和 API 请求失败测试**

在 `web/test/task-view-model.test.ts` 断言五状态分组、只把 `assignee_ids` 或 `current_handler_id` 命中的任务归入我的任务、截止/阻塞统计不把 DONE 算入 overdue。在 `web/test/workspace-actions.test.ts` 断言 transition body 使用 `target_status/base_status_version`，409 不改变快照。先运行：

```bash
cd web
npm test -- --run test/task-view-model.test.ts test/workspace-actions.test.ts
```

预期失败，因为方法和投影不存在。

- [ ] **Step 2: 实现 TypeScript 类型、API 方法和纯投影**

复用 `ApiClient.request` 的 JSON/credentials/error 处理，不在新方法中直接调用 `fetch`。`groupTasksByStatus` 始终返回固定顺序 `['TODO','IN_PROGRESS','WAITING','DONE','CANCELLED']` 的对象，即使某列为空也保留空数组。

- [ ] **Step 3: 扩展 Web 同步控制器**

每个写方法先从当前快照读取 `status_version`/`field_versions`，生成一个 request UUID；成功后用服务器返回的完整任务替换本地任务，并以返回 cursor 继续 pull。不要在错误分支乐观插入任务或修改状态。

- [ ] **Step 4: 写并实现 Dart 模型与仓储测试**

在 `client/test/models/task_view_test.dart` 覆盖 `DONE` 解析、我的任务筛选和 dueSoon/overdue；在现有仓储测试中断言 transition、comment、delay 的路径、snake_case body、`x-request-id`。运行：

```bash
cd client
dart format --output=none --set-exit-if-changed .
flutter test test/models/task_view_test.dart test/task/cloud_task_repository_test.dart
```

- [ ] **Step 5: 提交共享客户端契约**

```bash
git add web/src/api web/src/tasks web/src/sync web/test client/lib/models client/lib/task client/lib/sync client/test/models client/test/task
git commit -m "feat: add lightweight task client actions"
```

---

### Task 4: Web 行动优先界面（列表、我的任务、简单看板）

**Files:**
- Modify: `web/src/ui/workspace-view.ts`
- Create: `web/src/ui/task-detail-view.ts`
- Modify: `web/src/styles.css`
- Modify: `web/src/app.ts`
- Create: `web/test/workspace-view.test.ts`
- Modify: `web/test/app.test.ts`

**Interfaces:**
- `WorkspaceView.mount(root, sync, onLogout)` 继续返回 unsubscribe；视图内部只读取 `sync.state.snapshot`，过滤/分组委托 `task-view-model.ts`。
- `TaskDetailView.mount(container, task, members, actions)` 接收 `onTransition`, `onComment`, `onDelay`, `onSave` 回调；详情关闭后销毁临时 DOM，不写 localStorage/sessionStorage。
- 页面模式为 `list | board`，另有 `myOnly: boolean`；模式切换只改变投影，不改变任务状态。

- [ ] **Step 1: 写 DOM 失败测试**

在 `web/test/workspace-view.test.ts` 用最小 fake sync 快照断言：默认显示“我的任务”筛选入口、固定五个状态列、WAITING 显示阻塞原因、过期任务显示提醒、切换看板不产生第二个状态字段；点击 DONE 动作调用 `transitionTask` 并传入快照中的 `status_version`。运行 `npm test -- --run test/workspace-view.test.ts`，预期失败。

- [ ] **Step 2: 重组页面骨架**

在 `workspace-view.ts` 增加紧凑 summary 区（我的任务、阻塞、24 小时内、已过期、待处理冲突）、`列表/看板` 分段控件和“只看我的任务” checkbox。所有控件在 640px 以下纵向排列，任务卡保持稳定间距；不添加项目/团队选择器。

- [ ] **Step 3: 实现列表与看板投影**

列表按 `updated_at` 降序显示任务；看板使用 `groupTasksByStatus`，列标题和任务状态来自同一 `TaskItem.status`。每项展示标题、描述摘要、负责人/参与人数量、截止时间、延期次数、WAITING 原因和版本。已删除任务不渲染。

- [ ] **Step 4: 接入最小任务操作详情**

点击任务打开详情：可编辑标题/描述/计划开始/截止/预计分钟、选择当前处理人、选择状态动作；WAITING 表单要求阻塞原因和恢复负责人；评论和延期表单调用 controller，失败时保留输入并显示 API 错误。冲突面板保留“保留当前/采用提议”，不自动覆盖。

- [ ] **Step 5: 做响应式和组合回归测试**

在 `app.test.ts` 增加“登出后旧快照不回流”的现有回归断言，并断言 QR 登录成功后只挂载一个 workspace 根节点。运行：

```bash
cd web
npm test -- --run
npm run typecheck
npm run build
```

- [ ] **Step 6: 提交 Web 界面**

```bash
git add web/src web/test
git commit -m "feat: add action-first web workspace"
```

---

### Task 5: Android 行动优先界面

**Files:**
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Create: `client/lib/screens/task_detail_screen.dart`
- Modify: `client/lib/models/task.dart`
- Modify: `client/lib/models/workspace_snapshot.dart`
- Modify: `client/lib/sync/workspace_sync_controller.dart`
- Create: `client/test/screens/cloud_workspace_screen_test.dart`
- Modify: `client/test/screens/manual_refresh_test.dart`

**Interfaces:**
- `CloudWorkspaceScreen` 继续接收现有 `ApiClient`/`DeviceSigningKey`，不改变登录、设备批准或 Web QR 扫码入口。
- 页面使用 `TabBar` 的 `我的任务`、`全部任务`、`看板` 三个投影；`TaskView` 负责筛选和分组，Widget 不维护另一份任务列表。
- `TaskDetailScreen` 接收一个 `TaskItem` 和 `WorkspaceSyncController`，状态/评论/延期/阻塞按钮均调用 controller；返回后由 snapshot/cursor 刷新详情。

- [ ] **Step 1: 写 Widget 失败测试**

在 `client/test/screens/cloud_workspace_screen_test.dart` 构造包含 TODO、WAITING、DONE 和过期任务的 fake snapshot，断言：我的任务 tab 只显示当前用户命中的任务；看板显示五列；WAITING 展示原因；点击刷新调用 `refresh`；点击任务进入详情。运行 `flutter test test/screens/cloud_workspace_screen_test.dart`，预期失败。

- [ ] **Step 2: 实现模型投影和 summary**

在 `task_view.dart` 使用不可变列表实现 `mine`, `byStatus`, `summary`；状态标签统一映射中文文案，公共值仍保留 `DONE`。不要在 Widget 中按字符串复制筛选逻辑。

- [ ] **Step 3: 扩展 Android 同步写入**

为 `WorkspaceSyncRepository` 增加 transition/comment/delay 方法，HTTP 实现沿用 `ApiClient.request(authenticated: true)`；controller 在成功后 `refresh/pull`，在 409 显示冲突页或 SnackBar，不清空用户表单；网络失败保持 `isStale=true`。

- [ ] **Step 4: 实现任务详情和轻量操作**

详情页提供标题/描述编辑、负责人选择、状态动作、阻塞/解除阻塞、延期原因与备注、评论列表；没有附件入口、依赖图或自定义状态编辑器。表单验证失败时保留输入，成功后返回并显示最新 cursor。

- [ ] **Step 5: 运行 Android 检查并提交**

```bash
cd client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8090
```

确认 APK 路径为 `client/build/app/outputs/flutter-apk/app-debug.apk`，再提交：

```bash
git add client/lib client/test
git commit -m "feat: add action-first android workspace"
```

---

### Task 6: 双用户验收、文档和交付边界

**Files:**
- Create: `backend/tests/e2e/test_lightweight_workspace.py`
- Create: `scripts/smoke-lightweight-workspace.sh`
- Modify: `Makefile`
- Modify: `docs/README.md`
- Modify: `docs/05-development-status.md`
- Modify: `.github/workflows/release.yml`（仅在现有 release workflow 已存在对应 job 时调整命令；不改变 tag/release-only 触发器）

**Interfaces:**
- `scripts/smoke-lightweight-workspace.sh` 接收 `API_BASE_URL`、`AUTH_PASSWORD`，只输出 HTTP 状态码、任务状态和 cursor，不输出手机号验证码、Bearer token、cookie 或密码。
- Makefile 新增 `smoke-lightweight-workspace`，并让 `verify` 依次执行后端专项、Flutter、Web、boundary/deployment 检查；不增加新的必需服务。
- 文档明确固定状态、五个页面投影、无离线写入、无附件/依赖/自定义工作流，并记录每条命令的实际通过/未运行原因。

- [ ] **Step 1: 写可执行双用户验收测试**

在 `backend/tests/e2e/test_lightweight_workspace.py` 使用两个已认证 actor，按顺序断言：A 创建父/子任务；B snapshot 可见；A 指派 B、转为 IN_PROGRESS、阻塞并延期；B 添加评论并完成任务；双方 `GET /snapshot` 的任务状态、assignee_ids、delay_count、活动和 cursor 一致；用旧 status version 提交一次请求得到 409。

运行：`cd backend && python -m pytest tests/e2e/test_lightweight_workspace.py -q`。没有 PostgreSQL 时命令必须明确失败并在报告中写明，不得用 SQLite 冒充 PostgreSQL 并发验收。

- [ ] **Step 2: 实现 smoke 脚本和 Makefile 入口**

脚本使用 `curl --fail --silent --show-error`，从环境读取临时验证码/fake provider，使用 `jq` 或 Python 只提取 `status`、`cursor`、`delay_count`；执行后删除临时响应文件。加入 `make smoke-lightweight-workspace`，保持现有 `make test`、`make verify` 目标兼容。

- [ ] **Step 3: 完成文档和范围审计**

在 `docs/05-development-status.md` 追加本计划的变更、迁移（本轮无新增表；仅 API/客户端契约）、专项测试计数、APK 路径、Web `dist` 构建结果和 PostgreSQL smoke 结果。在 `docs/README.md` 增加从创建任务到完成/阻塞/延期/评论的最短使用流程，并列出明确不支持的附件、依赖和离线写入。

- [ ] **Step 4: 运行最终验证**

```bash
make test
make web-build
make client-build API_BASE_URL=http://10.0.2.2:8090
make boundary-check
make legacy-check
docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config
bash -n scripts/smoke-lightweight-workspace.sh
```

使用隔离 PostgreSQL Compose 数据卷运行 `make smoke-lightweight-workspace` 和 `backend/tests/e2e/test_lightweight_workspace.py`；如有真实 Android 设备，再执行一次登录、刷新、状态切换和 QR Web 登录人工检查。记录警告与未执行项，不能把未运行的设备测试写成通过。

- [ ] **Step 5: 提交交付记录**

```bash
git add backend/tests/e2e/test_lightweight_workspace.py scripts/smoke-lightweight-workspace.sh Makefile docs/README.md docs/05-development-status.md .github/workflows/release.yml
git commit -m "test: verify lightweight collaboration delivery"
```

## 计划自审

- 规格中的固定状态、一级子任务、参与人、负责人、截止/计划开始/预计耗时、WAITING 阻塞、追加延期、评论/活动、字段版本/409、我的任务、列表/看板、基础提醒统计和 Android/Web 同步均在 Task 1-5 有对应实现与测试。
- 规格明确排除的 Project/Team 层级、依赖图、附件、可配置工作流、Scrum 报表、自动化和离线写入没有进入任何数据模型或任务接口。
- `COMPLETED -> DONE` 只在公共 API 边界兼容现有数据库值，避免为轻量版本引入破坏性数据库迁移；所有新客户端只产生 `DONE`。
- 每个任务都有失败测试、最小实现、专项命令和独立 commit；最终任务补充 PostgreSQL、APK、Vite、边界脚本和文档证据。
