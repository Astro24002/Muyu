# Android Task Navigation And Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Android 工作区加入“清单 / 四象限 / 日程 / 我的”底部导航，移除看板，并以必选四象限和多标签分类贯通 PostgreSQL、FastAPI、同步协议及客户端展示。

**Architecture:** PostgreSQL 的 `tasks` 表保存非空 `quadrant` 和 JSONB `labels` 数组；FastAPI 对两者执行统一规范化、字段版本和双人审批规则。Android 只维护一个 `WorkspaceSyncController`，底部 destination 从同一快照派生不同视图；Web 保持当前页面布局，仅同步并编辑相同字段。

**Tech Stack:** FastAPI、SQLAlchemy 2、Alembic、PostgreSQL、pytest/httpx、Flutter/Dart、TypeScript/Vite、Vitest。

**Spec:** `docs/superpowers/specs/2026-08-31-android-task-navigation-labels-design.md`

> **执行状态（2026-08-31）**：本计划已完成并合并到 `main` 的提交
> `df237b6`（`feat: add task navigation quadrants and labels`）。后端、Flutter、Web
> 及文档改动均已落地；验证结果记录在 `docs/05-development-status.md`。

## Global Constraints

- Workspace 始终最多两名 ACTIVE 成员；审批始终是一人发起、另一人审批。
- `quadrant` 必须是 `Q1`、`Q2`、`Q3`、`Q4` 之一，创建时无默认值，数据库为 `NOT NULL`。
- `labels` 是任务内最多 10 个的规范化字符串数组，首版不建立标签实体或标签管理 API。
- 负责人可以直接修改标签/象限；另一成员修改返回 HTTP 202 并创建现有 `TASK_UPDATE` 或 `QUADRANT_UPDATE` 审批请求。
- 任务仍使用现有状态、负责人、字段版本、软删除和 cursor 语义；不引入离线写入、看板、P2P 或新外部依赖。
- Android 底部导航只有清单、四象限、日程、我的；看板不得出现在 Android UI 或测试断言中。
- 未验证设备只能读；Web 会话不作为长期 Android 设备显示。
- 每个任务结束一个独立测试周期并提交；生产代码必须遵守 TDD：先写失败测试并确认失败，再实现最小代码。

## File Map

### Backend

- Create: `backend/alembic/versions/0004_required_quadrant_task_labels.py` for the non-null quadrant and JSONB labels columns/constraints.
- Modify: `backend/app/db/models.py`, `backend/app/tasks/schemas.py`, `backend/app/tasks/service.py`, `backend/app/tasks/routes.py`, `backend/app/tasks/approvals.py`, `backend/app/tasks/approval_schemas.py`.
- Modify: `backend/app/sync/service.py`, `backend/app/sync/routes.py` only where complete task resources are serialized or validated.
- Test: `backend/tests/db/test_task_navigation_labels_schema.py`, `backend/tests/tasks/test_task_labels.py`, `backend/tests/httpapi/test_task_labels_routes.py`, `backend/tests/sync/test_task_labels_sync.py`.

### Flutter Android

- Modify: `client/lib/models/task.dart`, `client/lib/models/task_view.dart`, `client/lib/models/workspace_snapshot.dart` only if wire parsing requires it.
- Modify: `client/lib/screens/cloud_workspace_screen.dart` to host the one controller and four destinations.
- Create: `client/lib/screens/task_list_view.dart`, `client/lib/screens/task_quadrant_view.dart`, `client/lib/screens/task_schedule_view.dart` if extracting views keeps `cloud_workspace_screen.dart` focused.
- Modify: `client/lib/screens/task_detail_screen.dart` and the task creation form for required quadrant and multiple labels.
- Test: `client/test/models/task_view_test.dart`, `client/test/screens/cloud_workspace_screen_test.dart`, `client/test/screens/task_detail_screen_test.dart`, `client/test/screens/task_navigation_test.dart`.

### Web and documentation

- Modify: `web/src/api/types.ts`, `web/src/tasks/task-model.ts`, `web/src/ui/task-detail-view.ts`, `web/src/ui/workspace-view.ts`.
- Test: `web/test/task-view-model.test.ts`, `web/test/task-detail-view.test.ts`, `web/test/api-client.test.ts`.
- Update after implementation: `docs/05-development-status.md`, `docs/operations/task-workflow.md`, release/verification notes if the client version changes.

---

### Task 1: Establish the failing wire-contract and persistence tests

**Files:**
- Create: `backend/tests/db/test_task_navigation_labels_schema.py`
- Create: `backend/tests/tasks/test_task_labels.py`
- Modify: `backend/tests/httpapi/test_task_contract_regressions.py`

**Interfaces:**
- The tests define `Task.quadrant: TaskQuadrant` as non-null and `Task.labels: list[str]` as a JSONB array.
- The tests define accepted labels such as `工作`, `婚礼`, and `党员`, plus rejection cases for missing quadrant, null quadrant, empty labels, 11 labels, and a 33-character label.

- [x] **Step 1: Write the failing schema test.**

  Assert `tasks.quadrant` is non-null, `tasks.labels` is non-null JSONB with a `[]` server default, and the migration head exposes an array-type check. Assert the existing quadrant enum still has exactly `Q1` through `Q4`.

- [x] **Step 2: Write the failing service/HTTP contract tests.**

  Add cases that call the task service and `POST /api/v1/tasks` with a missing quadrant, a null quadrant, valid multiple labels, duplicate labels with whitespace, and invalid label counts/lengths. Expect the missing/null/invalid requests to fail before a task is committed.

- [x] **Step 3: Run the tests and verify the failure is feature-related.**

  Run:

  ```bash
  cd backend && pytest tests/db/test_task_navigation_labels_schema.py tests/tasks/test_task_labels.py tests/httpapi/test_task_contract_regressions.py -q
  ```

  Expected: FAIL because `labels` is absent and `quadrant` is still nullable/optional.

### Task 2: Add required quadrant and normalized task labels to the backend

**Files:**
- Create: `backend/alembic/versions/0004_required_quadrant_task_labels.py`
- Modify: `backend/app/db/models.py`
- Modify: `backend/app/tasks/schemas.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Test: files from Task 1

**Interfaces:**
- `TaskService.create(..., quadrant: str, labels: list[str] | None = None) -> Task` rejects missing/invalid quadrant and stores normalized labels.
- `TaskService.patch(..., changes: dict[str, Any], ...) -> Task` accepts `labels` and rejects `quadrant=None`.
- `normalize_task_labels(value: object) -> list[str]` trims, deduplicates case-insensitively, preserves first display spelling/order, and enforces the 10/32/320 limits.
- `TaskService.snapshot(task)` always returns a non-null `quadrant` and a JSON-safe `labels` list.

- [x] **Step 1: Implement only the migration and SQLAlchemy fields.**

  Add `labels JSONB NOT NULL DEFAULT '[]'`, a JSON array check, and make `quadrant` non-null. Because old development data may be discarded, the migration must fail clearly if existing rows contain null quadrants rather than silently assigning a quadrant. Keep downgrade explicit and limited to development rollback.

- [x] **Step 2: Run the schema tests.**

  Run `cd backend && pytest tests/db/test_task_navigation_labels_schema.py -q` and expect PASS.

- [x] **Step 3: Implement label normalization and required quadrant validation.**

  Add the helper in the task domain module, include `labels` in `MUTABLE_FIELDS`, create fingerprints and field versions with the normalized list, validate every create/patch path, and include labels in conflict `base_value`, `current_value`, `proposed_value`, operation snapshots and cursor changes.

- [x] **Step 4: Run the focused backend tests.**

  Run:

  ```bash
  cd backend && pytest tests/tasks/test_task_labels.py tests/httpapi/test_task_contract_regressions.py -q
  ```

  Expected: PASS for all valid and invalid cases, including no database mutation on validation failure.

- [x] **Step 5: Commit the persistence/domain slice.**

  ```bash
  git add backend/alembic/versions/0004_required_quadrant_task_labels.py backend/app/db/models.py backend/app/tasks/schemas.py backend/app/tasks/service.py backend/app/tasks/routes.py backend/tests/db/test_task_navigation_labels_schema.py backend/tests/tasks/test_task_labels.py backend/tests/httpapi/test_task_contract_regressions.py
  git commit -m "feat: require task quadrants and store labels"
  ```

### Task 3: Extend approval and synchronization contracts

**Files:**
- Modify: `backend/app/tasks/approvals.py`, `backend/app/tasks/approval_schemas.py`
- Modify: `backend/app/sync/service.py`, `backend/app/sync/routes.py`
- Test: `backend/tests/httpapi/test_task_labels_routes.py`, `backend/tests/sync/test_task_labels_sync.py`

**Interfaces:**
- Label-only non-owner patches use the existing `TASK_UPDATE` request type; quadrant-only patches continue to use `QUADRANT_UPDATE`.
- Approval application treats the complete label array as one field and rechecks `field_versions["labels"]` before committing.
- Snapshot and cursor change JSON always includes `quadrant` and `labels`, including approved changes and conflict records.

- [x] **Step 1: Write failing approval tests.**

  Create a task owned by user A. Submit a labels patch from user B and assert HTTP 202, `TASK_UPDATE`, unchanged task labels, and an incoming request for A. Approve as A and assert the full normalized label array is applied. Add a stale-version case that becomes `CONFLICTED` without partially applying labels.

- [x] **Step 2: Write failing sync tests.**

  Assert a snapshot and a cursor change round-trip `quadrant="Q2"` and `labels=["工作", "婚礼"]`; assert applying an update replaces the labels atomically and preserves task version/field versions.

- [x] **Step 3: Run the tests to verify RED.**

  ```bash
  cd backend && pytest tests/httpapi/test_task_labels_routes.py tests/sync/test_task_labels_sync.py -q
  ```

- [x] **Step 4: Implement approval/sync support.**

  Permit labels in normal task updates, retain the existing approval type selection, serialize labels in approval proposed changes, and use the existing cursor/resource serializers. Do not add a new approval type or a new sync endpoint.

- [x] **Step 5: Run the approval, sync and regression suites.**

  ```bash
  cd backend && pytest tests/tasks/test_task_approvals.py tests/httpapi/test_task_approval_routes.py tests/sync/test_task_approval_sync.py tests/httpapi/test_task_labels_routes.py tests/sync/test_task_labels_sync.py -q
  ```

- [x] **Step 6: Commit the contract slice.**

  ```bash
  git add backend/app/tasks/approvals.py backend/app/tasks/approval_schemas.py backend/app/sync/service.py backend/app/sync/routes.py backend/tests/httpapi/test_task_labels_routes.py backend/tests/sync/test_task_labels_sync.py
  git commit -m "feat: synchronize task labels through approvals"
  ```

### Task 4: Add Flutter task models and derived view selectors

**Files:**
- Modify: `client/lib/models/task.dart`
- Modify: `client/lib/models/task_view.dart`
- Modify: `client/lib/models/workspace_snapshot.dart` if required by parsing
- Test: `client/test/models/task_test.dart`, `client/test/models/task_view_test.dart`

**Interfaces:**
- `TaskItem.quadrant` is non-null and `TaskItem.labels` is an immutable `List<String>`.
- `TaskView.byStatus` returns the existing status map without a board view.
- Add `TaskView.byQuadrant(Iterable<TaskItem>) -> Map<String, List<TaskItem>>` with exactly Q1-Q4 keys.
- Add `TaskView.byDueDate(Iterable<TaskItem>, {DateTime? now}) -> Map<String, List<TaskItem>>` with ISO-local date keys and `未安排` for null due dates.
- Add `TaskView.filterByLabel(Iterable<TaskItem>, String?) -> List<TaskItem>`; null/empty filter returns all tasks.

- [x] **Step 1: Write failing Dart model/view tests.**

  Assert JSON parsing rejects a missing quadrant, parses labels, preserves immutable labels, groups four quadrants without an unset key, groups dates chronologically with `未安排`, and filters tasks by a single label.

- [x] **Step 2: Run the focused tests and verify RED.**

  ```bash
  cd client && flutter test test/models/task_test.dart test/models/task_view_test.dart
  ```

- [x] **Step 3: Implement the model and pure selectors.**

  Parse `labels` defensively as a string list, expose non-null quadrant data, and keep all grouping/filtering pure so widgets can test them without a network client.

- [x] **Step 4: Run the focused tests and the existing model suite.**

  ```bash
  cd client && flutter test test/models/task_test.dart test/models/task_view_test.dart
  ```

- [x] **Step 5: Commit the Flutter data slice.**

  ```bash
  git add client/lib/models/task.dart client/lib/models/task_view.dart client/lib/models/workspace_snapshot.dart client/test/models/task_test.dart client/test/models/task_view_test.dart
  git commit -m "feat: add task label and navigation view selectors"
  ```

### Task 5: Replace Android workspace tabs with the four bottom destinations

**Files:**
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Create: `client/lib/screens/task_list_view.dart`
- Create: `client/lib/screens/task_quadrant_view.dart`
- Create: `client/lib/screens/task_schedule_view.dart`
- Test: `client/test/screens/task_navigation_test.dart`, `client/test/screens/cloud_workspace_screen_test.dart`

**Interfaces:**
- `CloudWorkspaceScreen` owns one `WorkspaceSyncController` and renders a Material 3 `NavigationBar` with destinations `清单`, `四象限`, `日程`, `我的`.
- The task views accept the existing `WorkspaceSyncController`, `WorkspaceSyncState`, `canWrite`, and task navigation callback; they do not create repositories or controllers.
- No Android widget or route exposes `看板` or the old three-tab labels.

- [x] **Step 1: Write failing widget tests.**

  Mount a ready fake sync controller and assert four navigation destinations, initial `清单`, switching to `四象限` shows Q1-Q4, switching to `日程` shows date groups, switching to `我的` shows `MyProfileScreen`, and the old `看板` tab is absent. Assert refresh and approval/QR actions remain available where applicable.

- [x] **Step 2: Run the widget tests to verify RED.**

  ```bash
  cd client && flutter test test/screens/task_navigation_test.dart test/screens/cloud_workspace_screen_test.dart
  ```

- [x] **Step 3: Implement the navigation shell.**

  Replace `DefaultTabController`/`TabBar` with `NavigationBar`, keep the create-task bar only on `清单`, move profile content into the `我的` destination, and pass the same sync state to all task views. Use stable keys for the four destinations and preserve read-only banners on task destinations.

- [x] **Step 4: Implement the three task views.**

  Render compact cards using the existing task detail route. Four-quadrant groups must be exactly Q1-Q4; schedule groups use local date labels and `未安排`; label filter state stays local to the view and never mutates the snapshot.

- [x] **Step 5: Run focused and full Flutter tests.**

  ```bash
  cd client && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test
  ```

- [x] **Step 6: Commit the navigation slice.**

  ```bash
  git add client/lib/screens/cloud_workspace_screen.dart client/lib/screens/task_list_view.dart client/lib/screens/task_quadrant_view.dart client/lib/screens/task_schedule_view.dart client/test/screens/task_navigation_test.dart client/test/screens/cloud_workspace_screen_test.dart
  git commit -m "feat: add Android task bottom navigation"
  ```

### Task 6: Require quadrant and support multi-label editing in Android

**Files:**
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Modify: `client/lib/screens/task_detail_screen.dart`
- Modify: `client/lib/screens/cloud_workspace_screen.dart` for the existing `_CreateTaskBar` form
- Test: `client/test/screens/task_detail_screen_test.dart`, `client/test/task/task_creation_flow_test.dart`

**Interfaces:**
- Create task submits `quadrant` and `labels`; submit is disabled until a quadrant is selected and the title is non-empty.
- Task detail renders a required quadrant selector and a multi-label editor with add/remove behavior.
- Non-owner label/quadrant edits use the existing `PendingApproval` result and never optimistically alter the task.

- [x] **Step 1: Write failing widget tests.**

  Assert creation cannot submit without a quadrant, valid creation sends Q2 plus two labels, duplicate labels are shown once, removing a label sends the complete remaining array, and a pending non-owner update shows the existing approval feedback while the old task remains visible.

- [x] **Step 2: Run focused tests to verify RED.**

  ```bash
  cd client && flutter test test/screens/task_detail_screen_test.dart test/task/task_creation_flow_test.dart
  ```

- [x] **Step 3: Implement the form and detail controls.**

  Reuse existing repository/controller mutation methods, add the `labels` field to the request body and field versions, and keep the UI bounded to ten labels. Show concise validation messages for empty/oversized input. Do not add a tag-management route.

- [x] **Step 4: Run focused tests and analyzer.**

  ```bash
  cd client && flutter test test/screens/task_detail_screen_test.dart test/task/task_creation_flow_test.dart && flutter analyze
  ```

- [x] **Step 5: Commit the editing slice.**

  ```bash
  git add client/lib/screens/cloud_workspace_screen.dart client/lib/screens/task_detail_screen.dart client/test/screens/task_detail_screen_test.dart client/test/task/task_creation_flow_test.dart
  git commit -m "feat: require quadrants and edit task labels on Android"
  ```

### Task 7: Keep Web wire compatibility without changing its layout

**Files:**
- Modify: `web/src/api/types.ts`, `web/src/tasks/task-model.ts`
- Modify: `web/src/ui/task-detail-view.ts`, `web/src/ui/workspace-view.ts`
- Test: `web/test/task-detail-view.test.ts`, `web/test/task-view-model.test.ts`, `web/test/api-client.test.ts`

**Interfaces:**
- `TaskItem.quadrant` is non-null and `TaskItem.labels` is `string[]`.
- Web task detail submits the complete labels array and a required quadrant using existing patch/approval calls.
- Web task rows display labels but do not introduce a new navigation layout or board.

- [x] **Step 1: Write failing Web tests.**

  Assert a task with two labels renders both, the detail editor submits the complete label list and Q1-Q4 only, missing/null quadrant is rejected client-side, and a `202` response remains a pending approval rather than a local task mutation.

- [x] **Step 2: Run Web tests to verify RED.**

  ```bash
  cd web && npm test -- --run test/task-detail-view.test.ts test/task-view-model.test.ts test/api-client.test.ts
  ```

- [x] **Step 3: Implement wire types and detail controls.**

  Add typed labels parsing, render label chips/text in existing task rows, and serialize labels with the same base field versions used by the API. Keep Web’s current page/navigation structure unchanged.

- [x] **Step 4: Run typecheck, tests and build.**

  ```bash
  cd web && npm run typecheck && npm test -- --run && npm run build
  ```

- [x] **Step 5: Commit the compatibility slice.**

  ```bash
  git add web/src/api/types.ts web/src/tasks/task-model.ts web/src/ui/task-detail-view.ts web/src/ui/workspace-view.ts web/test/task-detail-view.test.ts web/test/task-view-model.test.ts web/test/api-client.test.ts
  git commit -m "feat: keep Web compatible with task labels"
  ```

### Task 8: Full verification, documentation and release decision

**Files:**
- Modify: `docs/05-development-status.md`
- Modify: `docs/operations/task-workflow.md`
- Modify: `docs/operations/release-checklist.md` only if a release is explicitly requested
- Test: existing project verification commands

**Interfaces:**
- Documentation states the Android four-destination navigation, required quadrant, multi-label limits and approval semantics.
- No APK/version/tag/release is created by this plan unless a separate release instruction is issued.

- [x] **Step 1: Run backend verification on a fresh PostgreSQL database.**

  ```bash
  make backend-test
  ```

  Expected: all existing backend tests plus the new schema, label, approval and sync tests pass; any existing deprecation warnings remain non-fatal.

- [x] **Step 2: Run Flutter verification.**

  ```bash
  make client-test
  ```

  Expected: format, analyzer and all Flutter tests pass, including navigation and required-quadrant creation.

- [x] **Step 3: Run Web and boundary verification.**

  ```bash
  cd web && npm run typecheck && npm test -- --run && npm run build
  cd .. && make boundary-check && make check-deployment
  ```

- [x] **Step 4: Run the two-person acceptance flow.**

  Use the existing disposable PostgreSQL smoke entrypoint to create a task with Q2 and labels `工作, 婚礼`, verify both members see it, submit a label update from the non-owner, approve it, and verify the cursor snapshot contains the normalized labels and unchanged quadrant.

- [x] **Step 5: Update implementation status.**

  Record test counts, migration head, API contract changes, and the fact that Android has no board. Record any real-device checks separately; do not claim QR login or APK acceptance from emulator-free tests.

- [x] **Step 6: Commit documentation only.**

  ```bash
  git add docs/05-development-status.md docs/operations/task-workflow.md
  git commit -m "docs: record Android task navigation and labels"
  ```

## Self-review checklist

- [x] The schema task makes quadrant non-null without silently assigning old null rows.
- [x] The label limits, normalization order and JSON field name are identical in spec, plan, API and clients.
- [x] Android has exactly four destinations and no board UI/runtime code remains; tests explicitly assert its absence.
- [x] Non-owner label and quadrant changes use the existing two-person approval path and are not optimistic.
- [x] `MyProfileScreen` remains the fourth destination and current-device deletion remains impossible.
- [x] Web receives the fields without expanding the current product scope.
- [x] Every implementation task has a failing test, a RED command, a minimal implementation, a GREEN command and a commit.
- [x] This plan does not include APK build, tag or release work without a separate user instruction.
