# Six-State Task Status Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 将任务状态从旧的 WAITING/COMPLETED 契约迁移为 TODO/IN_PROGRESS/BLOCKED/REVIEW/DONE/CANCELLED，并让 FastAPI、PostgreSQL、Web、Android、同步协议、首页和测试使用同一套双人协作规则。

**Architecture:** 服务端拥有唯一状态机和验收规则，客户端只展示中文名称、提交动作和渲染服务端快照。任务仍只有一个 current_handler_id；BLOCKED 保存阻塞上下文，REVIEW 保存服务端推导的另一位成员验收人。首页使用服务端聚合接口返回三类行动清单，客户端只在接口不可用时使用缓存。

**Tech Stack:** FastAPI, SQLAlchemy 2, Alembic, PostgreSQL enum/JSONB, Pydantic 2, React + TypeScript + Vite, Flutter/Dart, pytest, Vitest, Flutter test.

**Spec:** docs/superpowers/specs/2026-09-02-web-action-workbench-task-status-design.md

## Global Constraints

- 用户可见状态只显示中文：TODO 待进行、IN_PROGRESS 进行中、BLOCKED 阻塞中、REVIEW 待验收、DONE 已完成、CANCELLED 已取消。
- 用户只有一个任务负责人字段 current_handler_id；不恢复 task_assignees 或参与人字段。
- Workspace 永远只有两位 ACTIVE 成员；Review 默认验收人为另一位 ACTIVE 成员。
- 只有负责人可以直接修改任务状态；非负责人沿用双人审批规则。
- BLOCKED 必须有 blocked_reason、blocked_since、resume_handler_id；waiting_for_user_id 可为空。
- REVIEW -> DONE 只能由服务端指定验收人执行；REVIEW -> IN_PROGRESS 必须携带退回原因。
- TODO 和 IN_PROGRESS 才进入“当前任务”；BLOCKED 进入“当前阻塞”；REVIEW 进入“待我验收”。
- API 正式路径统一以 /api/v1 开头；英文状态名只存在于 API、数据库、同步协议和测试内部。
- 保留 append-only ActivityEvent、状态版本、幂等 request_id 和冲突记录。
- 本计划只覆盖 Android、Web、FastAPI 和 PostgreSQL；不引入 iOS、P2P 或新的云端能力。

---

### Task 1: Freeze the Cross-Client Status Contract

**Files:**
- Create: backend/tests/tasks/test_six_state_contract.py
- Create: web/test/task-status-contract.test.ts
- Create: client/test/models/task_status_contract_test.dart
- Modify: docs/02-technical-design.md:116-130,380-420
- Modify: docs/03-roadmap.md:99-110,173-182

**Interfaces:**
- Produces the canonical status set and Chinese labels used by later tasks.
- Defines legacy read migration: WAITING -> BLOCKED, COMPLETED -> DONE.

- [ ] Step 1: Write failing contract tests.

~~~python
def test_canonical_statuses_are_exactly_six():
    assert canonical_statuses() == {
        "TODO", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE", "CANCELLED"
    }
~~~

~~~ts
it('maps every internal status to the approved Chinese label', () => {
  expect(statusLabel('TODO')).toBe('待进行');
  expect(statusLabel('IN_PROGRESS')).toBe('进行中');
  expect(statusLabel('BLOCKED')).toBe('阻塞中');
  expect(statusLabel('REVIEW')).toBe('待验收');
  expect(statusLabel('DONE')).toBe('已完成');
  expect(statusLabel('CANCELLED')).toBe('已取消');
});
~~~

- [ ] Step 2: Run tests and verify failure.

Run: pytest backend/tests/tasks/test_six_state_contract.py -q
Run: cd web && npm test -- --run test/task-status-contract.test.ts
Run: cd client && flutter test test/models/task_status_contract_test.dart

Expected: FAIL because current code exposes WAITING, COMPLETED, 待开始 and 等待中.

- [ ] Step 3: Update active design docs.

Update task schema, status table, transitions and API examples to six states and /api/v1. Replace task_assignees with current_handler_id ownership. Move the Review action note outside the API code fence. Update the roadmap from WAITING to BLOCKED/REVIEW.

- [ ] Step 4: Run stale-document scan.

Run: rg -n "task_assignees|WAITING 状态|/api/auth|/api/tasks" docs/02-technical-design.md docs/03-roadmap.md

Expected: no active-design matches; historical files under docs/superpowers/superseded are excluded.

- [ ] Step 5: Commit.

~~~bash
git add backend/tests/tasks/test_six_state_contract.py web/test/task-status-contract.test.ts client/test/models/task_status_contract_test.dart docs/02-technical-design.md docs/03-roadmap.md
git commit -m "docs: freeze six-state task contract"
~~~

### Task 2: Migrate PostgreSQL and the Task ORM

**Files:**
- Create: backend/alembic/versions/0007_six_state_task_status.py
- Modify: backend/app/db/enums.py:65-105
- Modify: backend/app/db/models.py:286-323
- Test: backend/tests/db/test_task_status_schema.py

**Interfaces:**
- Produces a six-value TaskStatus and Review metadata columns.
- Preserves existing rows by mapping WAITING to BLOCKED and COMPLETED to DONE.

- [ ] Step 1: Add a schema inspection test.

~~~python
def test_task_status_enum_and_review_columns(inspector):
    assert inspector.enum_values("task_status") == [
        "TODO", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE", "CANCELLED"
    ]
    assert {
        "reviewer_user_id",
        "review_submitted_at",
        "reviewed_at",
        "review_rejection_reason",
    } <= inspector.columns("tasks")
~~~

- [ ] Step 2: Verify failure.

Run: make backend-test TEST=backend/tests/db/test_task_status_schema.py -q

Expected: FAIL against the current enum and missing columns.

- [ ] Step 3: Write migration 0007.

Add BLOCKED, REVIEW and DONE; convert existing WAITING/COMPLETED rows; recreate the enum without retired values; add reviewer_user_id with a users.id foreign key and RESTRICT; add review_submitted_at, reviewed_at and review_rejection_reason. Use Alembic operations and SQLAlchemy expressions. Do not delete task data.

- [ ] Step 4: Update ORM definitions.

~~~python
class TaskStatus(StrEnum):
    TODO = "TODO"
    IN_PROGRESS = "IN_PROGRESS"
    BLOCKED = "BLOCKED"
    REVIEW = "REVIEW"
    DONE = "DONE"
    CANCELLED = "CANCELLED"
~~~

Add the four Review fields to Task. Make PUBLIC_TASK_STATUS an identity mapping and remove the COMPLETED conversion after migration.

- [ ] Step 5: Run migration and schema tests.

Run: alembic upgrade head
Run: pytest backend/tests/db/test_task_status_schema.py -q

Expected: exact six enum values and all Review columns exist.

- [ ] Step 6: Commit.

~~~bash
git add backend/alembic/versions/0007_six_state_task_status.py backend/app/db/enums.py backend/app/db/models.py backend/tests/db/test_task_status_schema.py
git commit -m "feat: migrate tasks to six-state status model"
~~~

### Task 3: Implement the Server State Machine and Review Rules

**Files:**
- Modify: backend/app/tasks/schemas.py:41-66
- Modify: backend/app/tasks/service.py:30-41,286-377,572-608
- Modify: backend/app/tasks/routes.py
- Modify: backend/app/tasks/approvals.py:780-870
- Test: backend/tests/tasks/test_six_state_transitions.py
- Test: backend/tests/tasks/test_review_workflow.py

**Interfaces:**
- Consumes Task 2 enum and fields.
- Produces TaskService.transition with optional review_rejection_reason and snapshots containing Review metadata.

- [ ] Step 1: Add failing tests.

~~~python
def test_in_progress_can_submit_review_and_derives_other_member(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "交付", quadrant="Q1")
        TaskService(session).transition(workspace.id, user_a.id, task.id, uuid4(), "IN_PROGRESS", 1)
        review = TaskService(session).transition(workspace.id, user_a.id, task.id, uuid4(), "REVIEW", 2)
        assert review.status.value == "REVIEW"
        assert review.current_handler_id == user_a.id
        assert review.reviewer_user_id == user_b.id
        assert review.review_submitted_at is not None

def test_reviewer_can_accept_review(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = _review_task(session, workspace, user_a, user_b)
        done = TaskService(session).transition(workspace.id, user_b.id, task.id, uuid4(), "DONE", task.status_version)
        assert TaskService(session).snapshot(done)["status"] == "DONE"
        assert done.reviewed_at is not None

def test_reviewer_return_requires_reason_and_restores_handler(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = _review_task(session, workspace, user_a, user_b)
        with pytest.raises(TaskConflictError, match="review_rejection_reason"):
            TaskService(session).transition(workspace.id, user_b.id, task.id, uuid4(), "IN_PROGRESS", task.status_version)
        returned = TaskService(session).transition(workspace.id, user_b.id, task.id, uuid4(), "IN_PROGRESS", task.status_version, review_rejection_reason="补充验收材料")
        assert returned.status.value == "IN_PROGRESS"
        assert returned.current_handler_id == user_a.id
        assert returned.review_rejection_reason == "补充验收材料"

def test_blocked_cannot_complete_directly(db_engine):
    with Session(db_engine) as session:
        user_a, _, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "等待资料", quadrant="Q2")
        blocked = TaskService(session).transition(workspace.id, user_a.id, task.id, uuid4(), "BLOCKED", 1, blocked_reason="等待对方确认", resume_handler_id=user_a.id)
        with pytest.raises(TaskConflictError, match="cannot transition"):
            TaskService(session).transition(workspace.id, user_a.id, blocked.id, uuid4(), "DONE", blocked.status_version)

def test_non_handler_status_change_creates_existing_approval(db_engine):
    with Session(db_engine) as session:
        user_a, user_b, workspace = _workspace_with_two_users(session)
        task = TaskService(session).create(workspace.id, user_a.id, uuid4(), "协作任务", quadrant="Q3")
        request = ApprovalService(session).create_status_request(workspace.id, user_b.id, task.id, "IN_PROGRESS", task.status_version)
        assert request.approver_id == user_a.id
        assert request.status.value == "PENDING"
~~~

Assert reviewer identity, timestamps, rejection reason, status version and ActivityEvent records.

- [ ] Step 2: Verify failure.

Run: pytest backend/tests/tasks/test_six_state_transitions.py backend/tests/tasks/test_review_workflow.py -q

Expected: FAIL because the transition table has no BLOCKED or REVIEW.

- [ ] Step 3: Replace the transition table.

~~~python
TRANSITIONS = {
    "TODO": {"IN_PROGRESS", "BLOCKED", "CANCELLED"},
    "IN_PROGRESS": {"BLOCKED", "REVIEW", "CANCELLED"},
    "BLOCKED": {"IN_PROGRESS", "CANCELLED"},
    "REVIEW": {"DONE", "IN_PROGRESS", "CANCELLED"},
    "DONE": {"TODO", "IN_PROGRESS", "CANCELLED"},
    "CANCELLED": {"TODO", "IN_PROGRESS"},
}
~~~

Reject BLOCKED to DONE and any REVIEW completion path without reviewer authorization.

- [ ] Step 4: Implement Blocked validation.

Require non-blank blocked_reason, validate resume_handler_id as an ACTIVE member, set server blocked_since and clear Review fields. BLOCKED -> IN_PROGRESS clears blocking fields and uses the stored or explicitly validated resume handler.

- [ ] Step 5: Implement Review validation.

IN_PROGRESS -> REVIEW requires the current handler, derives the only other ACTIVE member as reviewer_user_id, sets review_submitted_at and preserves current_handler_id. REVIEW -> DONE or REVIEW -> IN_PROGRESS requires that reviewer. Acceptance sets reviewed_at; return requires non-blank review_rejection_reason and keeps the original handler.

- [ ] Step 6: Update approval validation and snapshots.

Allow six statuses in STATUS_UPDATE. Replace WAITING branches with BLOCKED branches. Include Review fields in snapshots and operation fingerprints.

- [ ] Step 7: Run task tests.

Run: pytest backend/tests/tasks/test_six_state_transitions.py backend/tests/tasks/test_review_workflow.py backend/tests/tasks/test_task_approvals.py -q

Expected: PASS with no old-status assertions.

- [ ] Step 8: Commit.

~~~bash
git add backend/app/tasks/schemas.py backend/app/tasks/service.py backend/app/tasks/routes.py backend/app/tasks/approvals.py backend/tests/tasks/test_six_state_transitions.py backend/tests/tasks/test_review_workflow.py
git commit -m "feat: enforce blocked and review task workflow"
~~~

### Task 4: Extend Sync, Conflict, and Activity Contracts

**Files:**
- Modify: backend/app/sync/service.py
- Modify: backend/app/tasks/operations.py
- Modify: backend/app/tasks/service.py
- Modify: web/src/sync/workspace-sync.ts:920-940
- Test: backend/tests/sync/test_six_state_sync.py
- Test: web/test/workspace-sync-status.test.ts
- Test: client/test/sync/six_state_sync_test.dart

**Interfaces:**
- Consumes six-state snapshots from Task 3.
- Produces typed changes preserving Blocked/Review metadata, versions and conflicts.

- [ ] Step 1: Add failing round-trip tests for Review metadata, Blocked metadata and stale Review conflicts.
- [ ] Step 2: Verify failure.

Run: pytest backend/tests/sync/test_six_state_sync.py -q
Run: cd web && npm test -- --run test/workspace-sync-status.test.ts
Run: cd client && flutter test test/sync/six_state_sync_test.dart

- [ ] Step 3: Update typed status guards.

~~~ts
const LEGACY_STATUS_MAP = { WAITING: 'BLOCKED', COMPLETED: 'DONE' } as const;
~~~

Normalize legacy values only while reading cached/old snapshots. Never emit legacy values in requests.

- [ ] Step 4: Extend sync projections.

Include reviewer_user_id, review_submitted_at, reviewed_at and review_rejection_reason in REST snapshots, cursor changes, cached snapshots and conflicts. Preserve field_versions, status_version and lifecycle_version.

- [ ] Step 5: Record typed activities.

Use the existing append-only infrastructure with BLOCKED, UNBLOCKED, REVIEW_SUBMITTED, REVIEW_ACCEPTED and REVIEW_RETURNED. Do not add a second event store.

- [ ] Step 6: Run sync tests and commit.

~~~bash
git add backend/app/sync/service.py backend/app/tasks/operations.py backend/app/tasks/service.py web/src/sync/workspace-sync.ts backend/tests/sync/test_six_state_sync.py web/test/workspace-sync-status.test.ts client/test/sync/six_state_sync_test.dart
git commit -m "feat: sync blocked and review task metadata"
~~~

### Task 5: Add the Action-First Home Aggregation

**Files:**
- Create: backend/app/home/__init__.py
- Create: backend/app/home/schemas.py
- Create: backend/app/home/routes.py
- Modify: backend/app/main.py:73-83
- Create: backend/tests/httpapi/test_home_routes.py
- Modify: web/src/tasks/task-view-model.ts

**Interfaces:**
- Produces GET /api/v1/home with current_tasks, blocked_tasks, review_tasks and pending_approval_count.
- Lists are filtered/sorted by server and include has_more.

- [ ] Step 1: Add failing API tests.

~~~python
def test_home_returns_current_tasks_max_five_and_excludes_blocked_review(db_client):
    seed_home_tasks(db_client, viewer="user-a", current_count=6, blocked_count=1, review_count=1)
    response = db_client.get("/api/v1/home", headers=auth_headers("user-a"))
    assert response.status_code == 200
    body = response.json()
    assert len(body["current_tasks"]) == 5
    assert {item["status"] for item in body["current_tasks"]} <= {"TODO", "IN_PROGRESS"}

def test_home_returns_only_viewer_owned_blocked_tasks(db_client):
    seed_blocked_task(db_client, task_id="mine", handler="user-a", reason="等待确认")
    seed_blocked_task(db_client, task_id="partner", handler="user-b", reason="等待文件")
    response = db_client.get("/api/v1/home", headers=auth_headers("user-a"))
    assert [item["id"] for item in response.json()["blocked_tasks"]] == ["mine"]

def test_home_returns_review_tasks_where_viewer_is_reviewer(db_client):
    seed_review_task(db_client, task_id="for-a", handler="user-b", reviewer="user-a")
    seed_review_task(db_client, task_id="for-b", handler="user-a", reviewer="user-b")
    response = db_client.get("/api/v1/home", headers=auth_headers("user-a"))
    assert [item["id"] for item in response.json()["review_tasks"]] == ["for-a"]

def test_home_sorts_overdue_then_due_then_updated(db_client):
    seed_home_sort_fixture(db_client, viewer="user-a")
    response = db_client.get("/api/v1/home", headers=auth_headers("user-a"))
    assert [item["id"] for item in response.json()["current_tasks"]] == ["overdue", "soon", "later", "no-due"]
~~~

- [ ] Step 2: Verify failure.

Run: pytest backend/tests/httpapi/test_home_routes.py -q

Expected: 404 because no home router exists.

- [ ] Step 3: Implement route and query rules.

~~~text
current_tasks: current_handler_id == viewer and status in {TODO, IN_PROGRESS}, limit 5
blocked_tasks: current_handler_id == viewer and status == BLOCKED, limit 3
review_tasks: reviewer_user_id == viewer and status == REVIEW, limit 3
~~~

Sort current tasks by overdue first, due date ascending, no due date last, updated time descending, then task ID.

- [ ] Step 4: Replace client derivation.

Map the server response in deriveTodayModel. Keep a cache fallback only when the home request is unavailable; never put another member’s ordinary tasks in the current-task module.

- [ ] Step 5: Run and commit.

Run: pytest backend/tests/httpapi/test_home_routes.py -q
Run: cd web && npm test -- --run test/today-view-model.test.ts test/today-page.test.tsx

~~~bash
git add backend/app/home backend/app/main.py backend/tests/httpapi/test_home_routes.py web/src/tasks/task-view-model.ts web/test/today-view-model.test.ts web/test/today-page.test.tsx
git commit -m "feat: add action-first home task aggregation"
~~~

### Task 6: Align Web Labels, Forms, and Review Actions

**Files:**
- Modify: web/src/api/types.ts:1-25
- Create: web/src/tasks/task-status.ts
- Modify: web/src/components/tasks/TaskStatusLabel.tsx
- Modify: web/src/components/tasks/TaskEditForm.tsx
- Modify: web/src/components/tasks/TaskMeta.tsx
- Modify: web/src/pages/TodayPage.tsx
- Test: web/test/task-status.test.ts
- Test: web/test/task-edit-review.test.tsx

**Interfaces:**
- Produces statusLabel(status) and statusTone(status) as the sole Web status presentation API.

- [ ] Step 1: Add failing UI tests for Chinese labels, Blocked fields, Submit Review, reviewer-only accept/return and required return reason.
- [ ] Step 2: Verify failure.

Run: cd web && npm test -- --run test/task-status.test.ts test/task-edit-review.test.tsx

- [ ] Step 3: Create one mapping.

~~~ts
export const TASK_STATUS_LABELS = {
  TODO: '待进行',
  IN_PROGRESS: '进行中',
  BLOCKED: '阻塞中',
  REVIEW: '待验收',
  DONE: '已完成',
  CANCELLED: '已取消',
} as const;
~~~

Use it in labels, filters, detail metadata, empty states, aria labels and notifications. Components must not define private status text.

- [ ] Step 4: Replace form behavior.

Replace WAITING fields with Blocked fields. Call the transition client with target_status and review_rejection_reason. Disable Review actions unless the viewer is the server-provided reviewer.

- [ ] Step 5: Render headings 当前任务, 当前阻塞 and 待我验收. Exclude Done and Cancelled.
- [ ] Step 6: Run and commit.

Run: cd web && npm test -- --run

~~~bash
git add web/src/api/types.ts web/src/tasks/task-status.ts web/src/components/tasks/TaskStatusLabel.tsx web/src/components/tasks/TaskEditForm.tsx web/src/components/tasks/TaskMeta.tsx web/src/pages/TodayPage.tsx web/test
git commit -m "feat: align web task status and action-first home"
~~~

### Task 7: Align Android Models, List, Detail, and Navigation

**Files:**
- Modify: client/lib/models/task_view.dart:28-35,240-254
- Modify: client/lib/models/task.dart:208-215
- Modify: client/lib/screens/task_list_view.dart:376-432,560-575
- Modify: client/lib/screens/task_detail_screen.dart:345-415,702-738
- Modify: client/lib/sync/workspace_sync_controller.dart
- Create: client/lib/tasks/task_status.dart
- Test: client/test/models/task_status_contract_test.dart
- Test: client/test/screens/task_status_display_test.dart
- Test: client/test/screens/task_review_actions_test.dart

**Interfaces:**
- Produces one Dart status mapping used by 清单、四象限、日程、详情和无障碍文本.

- [ ] Step 1: Add failing tests for six statuses, Chinese semantics, Chinese detail buttons and reviewer-only actions.
- [ ] Step 2: Verify failure.

Run: cd client && flutter test test/models/task_status_contract_test.dart test/screens/task_status_display_test.dart test/screens/task_review_actions_test.dart

- [ ] Step 3: Create the Dart mapping.

~~~dart
const taskStatusLabels = <String, String>{
  'TODO': '待进行',
  'IN_PROGRESS': '进行中',
  'BLOCKED': '阻塞中',
  'REVIEW': '待验收',
  'DONE': '已完成',
  'CANCELLED': '已取消',
};
~~~

Use it for visible text, semantic labels, icons, filters and summaries. Normalize legacy values only while reading cached snapshots.

- [ ] Step 4: Update list and detail.

Replace WAITING conditions with BLOCKED. Add Review summary and accept/return actions. Return opens a required reason dialog. Remove raw English buttons. CANCELLED displays 已取消, not 已失败.

- [ ] Step 5: Connect home modules.

Render server current_tasks, blocked_tasks and review_tasks in existing navigation without a fifth tab or board tab.

- [ ] Step 6: Run and commit.

Run: cd client && flutter analyze
Run: cd client && flutter test

~~~bash
git add client/lib/models/task_view.dart client/lib/models/task.dart client/lib/screens/task_list_view.dart client/lib/screens/task_detail_screen.dart client/lib/sync/workspace_sync_controller.dart client/lib/tasks/task_status.dart client/test
git commit -m "feat: align android task status workflow"
~~~

### Task 8: Remove Obsolete Contracts and Complete Verification

**Files:**
- Modify: backend/tests/tasks/test_lightweight_contract.py
- Modify: backend/tests/db/test_task_approval_schema.py
- Modify: backend/tests/tasks/test_task_approvals.py
- Modify: backend/tests/e2e/test_cloud_protocol.py
- Modify: web/test/task-row.test.tsx
- Modify: web/test/all-tasks-page.test.tsx
- Modify: client/test/screens/task_detail_screen_test.dart
- Modify: docs/01-product.md
- Modify: docs/02-technical-design.md
- Modify: docs/03-roadmap.md
- Modify: docs/05-development-status.md

**Interfaces:**
- Produces a repository whose active docs, source types, fixtures and tests contain no retired task-state contract.

- [ ] Step 1: Convert fixtures from WAITING to BLOCKED and COMPLETED to DONE. Add explicit Review fixtures; do not treat waiting approvals as Review.
- [ ] Step 2: Remove active WAITING/COMPLETED branches after all clients consume six states. Keep only one documented read-side normalizer if older deployed clients require it.
- [ ] Step 3: Run the stale-contract scan.

~~~bash
rg -n "WAITING|COMPLETED|待开始|等待中|task_assignees|/api/auth|/api/tasks" backend/app backend/tests web/src web/test client/lib client/test docs/01-product.md docs/02-technical-design.md docs/03-roadmap.md docs/05-development-status.md
~~~

Expected: only historical migration comments, WAITING_PARTNER delay reason, WAITING_FOR_PARTNER bootstrap state and explicitly marked superseded documents remain.

- [ ] Step 4: Repair the backend test database. Start disposable PostgreSQL with credentials matching repository settings, then run make backend-test. A password authentication failed error is not accepted as completed verification.
- [ ] Step 5: Run full verification.

~~~bash
cd web && npm test -- --run
cd ../client && flutter analyze && flutter test
cd .. && pytest backend/tests -q
~~~

Expected: all suites pass and no active source file contains retired task status values.

- [ ] Step 6: Commit.

~~~bash
git add backend/tests web/test client/test docs
git commit -m "test: finalize six-state task status migration"
~~~

## Release Gate

- alembic upgrade head succeeds on empty and legacy-data databases.
- GET /api/v1/home returns bounded, viewer-filtered action lists.
- BLOCKED cannot be completed directly.
- REVIEW can only be accepted or returned by the derived opposite member.
- Return-to-In-Progress requires a non-blank reason.
- Android and Web render the same six Chinese labels.
- Snapshots and cursor changes preserve Review metadata.
- current_handler_id remains the only owner field.
- Backend, Web and Flutter tests pass in a clean test environment.
- APK naming and release CI remain unchanged unless separately planned.

## Self-Review Checklist

- [ ] Every requirement in the six-state design spec maps to a task above.
- [ ] Every function, field and endpoint used by a later task is defined by an earlier task or existing module.
- [ ] No active task restores the retired participant model.
- [ ] Behavior-changing tasks write tests before implementation.
- [ ] Database, API, sync, Web, Android, docs and tests are updated as one versioned change.
