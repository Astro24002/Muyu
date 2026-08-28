# Two-Person Task Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在严格两人 Workspace 内实现任务负责人保护、另一位成员单人审批、评论软删除、四象限/进度/任务编号和 Android/Web 一致同步。

**Architecture:** PostgreSQL 是唯一事实源。任务负责人直接写入；非负责人提交 `TaskApprovalRequest`，服务端自动把同一 Workspace 的另一名 ACTIVE 成员设为唯一审批人，审批事务重新校验版本后应用原子变更。Android 和 Web 通过现有快照、增量 cursor 和 WebSocket 提示读取任务及审批状态，不建立管理员、群组或投票层。

**Tech Stack:** FastAPI、SQLAlchemy 2、Alembic、PostgreSQL、pytest/httpx、Flutter/Dart、TypeScript/Vite、Vitest。

**Spec:** `docs/superpowers/specs/2026-08-28-two-person-task-approval-design.md`

## Global Constraints

- 一个 Workspace 最多拥有两名 `ACTIVE` 成员。
- 所有审批均为一人发起、另一人审批，且每个请求只有一个审批人。
- 审批人由服务端根据 Workspace 成员关系自动确定，客户端不能选择审批人。
- `current_handler_id` 是唯一任务负责人字段，不新增 `owner_user_id`。
- 未验证设备只能读取；已验证 Android 设备或有效 Web 会话才能写入或处理审批。
- 任务和子任务使用同一个 `Task` 模型，首版只允许一层子任务。
- 任务正文和评论历史不物理删除；评论和任务删除使用软删除并保留审计。
- 所有写入、审批、拒绝、取消和冲突结果必须在同一事务中写入操作记录、活动记录和 Workspace cursor。
- 不新增 Project、Team、RBAC、群组审批、投票、离线写入队列或新的外部基础设施。
- Flutter 只构建 Android；Web 使用 TypeScript + Vite；iOS 仅保持协议兼容，不纳入构建和验收。

## File Map

Backend changes are split into persistence, task domain, approval domain, HTTP and synchronization. Flutter receives typed models and repository/controller operations before UI changes. Web receives the same wire contract and renders the approval inbox/outbox without choosing an approver.

### Backend

- Create `backend/alembic/versions/0003_two_person_task_approval.py`: schema migration, constraints and indexes.
- Create `backend/app/tasks/numbering.py`: atomic human-readable task number allocator.
- Create `backend/app/tasks/approvals.py`: approval request domain service and atomic application.
- Create `backend/app/tasks/approval_schemas.py`: Pydantic request/response contracts.
- Create `backend/app/tasks/approval_routes.py`: approval request HTTP routes.
- Modify `backend/app/db/enums.py`, `backend/app/db/models.py`: quadrant/progress/comment tombstone/approval models.
- Modify `backend/app/tasks/service.py`, `backend/app/tasks/schemas.py`, `backend/app/tasks/routes.py`, `backend/app/tasks/comments.py`: task owner authorization, numbering, fields and comment deletion.
- Modify `backend/app/sync/service.py`, `backend/app/sync/routes.py`, `backend/app/main.py`: approval resources, viewer identity and router registration.

### Flutter Android

- Create `client/lib/models/task_approval_request.dart`.
- Modify `client/lib/models/task.dart`, `client/lib/models/workspace_snapshot.dart`, `client/lib/models/workspace_change.dart`.
- Modify `client/lib/sync/workspace_sync_repository.dart`, `client/lib/sync/workspace_sync_controller.dart`, `client/lib/task/cloud_task_repository.dart`.
- Create `client/lib/screens/task_approval_screen.dart`.
- Modify `client/lib/screens/cloud_workspace_screen.dart`, `client/lib/screens/task_detail_screen.dart`.

### Web

- Modify `web/src/api/types.ts`, `web/src/api/client.ts`, `web/src/sync/workspace-sync.ts`, `web/src/tasks/task-model.ts`.
- Create `web/src/ui/approval-view.ts`.
- Modify `web/src/ui/workspace-view.ts`, `web/src/ui/task-detail-view.ts`, `web/src/styles.css`.

### Tests and documentation

- Create focused backend domain/HTTP tests under `backend/tests/tasks/`, `backend/tests/httpapi/` and `backend/tests/db/`.
- Modify existing Flutter task/sync/screen tests and add approval screen tests.
- Modify existing Web API/sync/workspace/detail tests and add approval-view tests.
- Add two-user acceptance coverage under `backend/tests/e2e/test_two_person_task_approval.py` and update `docs/operations/task-workflow.md` with the final request lifecycle.

---

### Task 1: Add persistence model, enums and migration

**Files:**
- Create: `backend/alembic/versions/0003_two_person_task_approval.py`
- Modify: `backend/app/db/enums.py`
- Modify: `backend/app/db/models.py`
- Test: `backend/tests/db/test_task_approval_schema.py`
- Modify: `backend/tests/db/test_cloud_schema.py`

**Interfaces:**
- Produces `TaskQuadrant` with values `Q1`, `Q2`, `Q3`, `Q4`.
- Produces `TaskApprovalRequestType` with values `TASK_UPDATE`, `QUADRANT_UPDATE`, `STATUS_UPDATE`, `TASK_DELETE`, `TASK_RESTORE`, `COMMENT_DELETE`, `ASSIGNEE_UPDATE`, `HANDLER_TRANSFER`.
- Produces `TaskApprovalRequestStatus` with values `PENDING`, `APPROVED`, `REJECTED`, `CONFLICTED`, `CANCELLED`.
- Extends `Task` with `task_number: str`, nullable `quadrant`, nullable persisted progress value, and response-compatible field versions.
- Extends `TaskComment` with `version`, `deleted_at`, and `deleted_by`.
- Produces `TaskNumberSequence(period CHAR(4) PRIMARY KEY, next_value INTEGER NOT NULL)` and `TaskApprovalRequest` with `workspace_id`, `task_id`, nullable `comment_id`, `requester_id`, `approver_id`, `request_type`, `proposed_changes`, `base_field_versions`, `request_id`, lifecycle timestamps, status, rejection reason and resolved cursor.

- [ ] **Step 1: Write failing schema tests.** Assert the new table names, columns, enum values, unique `tasks.task_number`, approval indexes, requester/approver distinctness, progress check (`NULL` or `20/40/60/80`) and the existing maximum-two-member constraints.
- [ ] **Step 2: Run the focused tests to verify they fail.**

  Run: `cd backend && pytest tests/db/test_task_approval_schema.py tests/db/test_cloud_schema.py -q`

  Expected: FAIL because the approval table, task number fields and comment tombstone fields do not exist.

- [ ] **Step 3: Implement the SQLAlchemy models and migration.** Add the model fields and enums, create `task_number_sequences` and `task_approval_requests`, add foreign keys with `CASCADE` only for Workspace ownership and `RESTRICT` for actors, add indexes on `(workspace_id, status, approver_id)`, `(workspace_id, status, requester_id)`, `(task_id, status)`, and `(comment_id, status)`. For existing rows, add `task_number` nullable, populate numbers ordered by `(created_at, id)` using `YYMM` plus a four-digit sequence, then make it non-null and unique. Keep the migration safe for the empty production database and isolated test schemas.
- [ ] **Step 4: Run the schema tests and migration checks.**

  Run: `cd backend && pytest tests/db/test_task_approval_schema.py tests/db/test_cloud_schema.py -q`

  Expected: PASS with the new tables, constraints and indexes visible through SQLAlchemy inspection.

- [ ] **Step 5: Commit the persistence slice.**

  ```bash
  git add backend/alembic/versions/0003_two_person_task_approval.py backend/app/db/enums.py backend/app/db/models.py backend/tests/db/test_task_approval_schema.py backend/tests/db/test_cloud_schema.py
  git commit -m "feat: add task approval persistence model"
  ```

### Task 2: Implement task numbering, quadrant/progress and owner-only domain writes

**Files:**
- Create: `backend/app/tasks/numbering.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/schemas.py`
- Modify: `backend/app/tasks/comments.py`
- Test: `backend/tests/tasks/test_two_person_task_domain.py`

**Interfaces:**
- `TaskNumberAllocator.allocate(session: Session, at: datetime) -> str` atomically returns `YYMMNNNN` and never reuses a number in the same period.
- `TaskService.create(..., quadrant: str | None = None) -> Task` validates one-level parentage and assigns a number to every task and subtask.
- `TaskService.patch(...)` accepts `quadrant` and `progress`, validates `progress` as `None` or `20/40/60/80`, and rejects non-owner direct writes with `TaskConflictError("approval_required", ...)`.
- `TaskService.transition(...)` sets a new `IN_PROGRESS` task with progress `20` when no value exists, preserves the persisted value while waiting, and exposes `0`/`100` as derived values for `TODO`/`DONE`.
- `TaskService.delete_comment(workspace_id: UUID, actor_user_id: UUID, comment_id: UUID, request_id: UUID, base_version: int) -> TaskComment` soft-deletes an author-owned comment directly and writes operation/activity/cursor data.
- `TaskService.snapshot(task)` includes `task_number`, `quadrant`, and public `progress` in addition to all existing fields.

- [ ] **Step 1: Write failing domain tests.** Cover atomic concurrent-looking number allocation (`26080001`, `26080002`), subtask numbering, nested-subtask rejection, quadrant validation, progress validation, TODO/IN_PROGRESS/DONE progress behavior, owner direct mutation, non-owner `approval_required`, comment-author soft delete, repeated delete rejection and snapshot fields.
- [ ] **Step 2: Run the focused domain tests to verify they fail.**

  Run: `cd backend && pytest tests/tasks/test_two_person_task_domain.py -q`

  Expected: FAIL with missing allocator/model fields and missing authorization behavior.

- [ ] **Step 3: Implement the allocator and domain changes.** Lock or upsert one `TaskNumberSequence` row per `YYMM`, format the number with four digits, extend `MUTABLE_FIELDS`, normalize enums/UUIDs, call `_validated_member` for quadrant-independent member checks, and add a handler guard to every direct patch/transition/lifecycle path. Set comment tombstone metadata without deleting the row and emit an operation plus cursor.
- [ ] **Step 4: Run the domain tests and the existing task suite.**

  Run: `cd backend && pytest tests/tasks/test_two_person_task_domain.py tests/tasks/test_cloud_mutations.py tests/tasks/test_lightweight_contract.py -q`

  Expected: PASS. Existing owner-created task tests must remain valid; tests that intentionally mutate a task as the other member must now expect `approval_required` until Task 3 routes the request.

- [ ] **Step 5: Commit the task-domain slice.**

  ```bash
  git add backend/app/tasks/numbering.py backend/app/tasks/service.py backend/app/tasks/schemas.py backend/app/tasks/comments.py backend/tests/tasks/test_two_person_task_domain.py backend/tests/tasks/test_cloud_mutations.py
  git commit -m "feat: enforce task ownership and progress fields"
  ```

### Task 3: Implement the unified two-person approval service

**Files:**
- Create: `backend/app/tasks/approvals.py`
- Create: `backend/app/tasks/approval_schemas.py`
- Test: `backend/tests/tasks/test_task_approvals.py`

**Interfaces:**
- `TaskApprovalService.create(workspace_id: UUID, requester_id: UUID, request_id: UUID, task_id: UUID, request_type: TaskApprovalRequestType, proposed_changes: dict[str, Any], base_field_versions: dict[str, int], comment_id: UUID | None = None) -> TaskApprovalRequest`.
- `TaskApprovalService.list(workspace_id: UUID, viewer_id: UUID, box: Literal["incoming", "outgoing"] | None = None) -> list[TaskApprovalRequest]`.
- `TaskApprovalService.approve(workspace_id: UUID, approver_id: UUID, approval_id: UUID, action_request_id: UUID) -> TaskApprovalResult`.
- `TaskApprovalService.reject(workspace_id: UUID, approver_id: UUID, approval_id: UUID, action_request_id: UUID, reason: str | None) -> TaskApprovalRequest`.
- `TaskApprovalService.cancel(workspace_id: UUID, requester_id: UUID, approval_id: UUID, action_request_id: UUID) -> TaskApprovalRequest`.
- `TaskApprovalService.cancel_stale_for_task(workspace_id: UUID, task_id: UUID, reason: str) -> int`.
- `TaskApprovalResult` returns the updated request and optional updated `Task`/`TaskComment` plus `cursor`.

- [ ] **Step 1: Write failing approval-domain tests.** Cover exactly-two-member approval derivation, no-member/one-member setup rejection, self-approval rejection, cross-workspace rejection, duplicate `request_id` replay, owner/non-owner request creation, incoming/outgoing listing, approve/reject/cancel permissions, stale field version becoming `CONFLICTED`, task delete/handler transfer cancelling old requests, comment delete approval by comment author, and one-time application of an approved request.
- [ ] **Step 2: Run the approval tests to verify they fail.**

  Run: `cd backend && pytest tests/tasks/test_task_approvals.py -q`

  Expected: FAIL because `TaskApprovalService` and `TaskApprovalRequest` behavior are not implemented.

- [ ] **Step 3: Implement approval creation.** Lock the Workspace membership rows, require exactly two ACTIVE members for task approvals, compute the other member as `approver_id`, validate the target task/comment belongs to the same Workspace, validate request type and proposed field set, persist immutable base versions, and use the existing workspace idempotency mechanism for `request_id`.
- [ ] **Step 4: Implement atomic approval/rejection/cancellation.** Lock the request and target task/comment in one transaction. For approval, require `PENDING`, require the caller to equal `approver_id`, require an active writable principal, recheck task owner/comment author/lifecycle/field versions, then invoke the owner-authorized TaskService mutation using the approval UUID as the applied operation request key. Mark the request `APPROVED` only after the target mutation, operation, activity and cursor are ready. Rejection and requester cancellation update status once and emit activity/cursor records without changing the target.
- [ ] **Step 5: Implement stale-request cleanup and typed errors.** Use stable codes `approval_required`, `approval_not_allowed`, `approval_not_found`, `approval_conflicted`, `approval_already_resolved`, and `approval_request_reused`; cancel pending requests when a task is deleted/restored or its handler changes if the old owner is the approver.
- [ ] **Step 6: Run the approval and task domain suites.**

  Run: `cd backend && pytest tests/tasks/test_task_approvals.py tests/tasks/test_two_person_task_domain.py tests/tasks/test_cloud_mutations.py -q`

  Expected: PASS with exactly one approver and no multi-user approval branches.

- [ ] **Step 7: Commit the approval-domain slice.**

  ```bash
  git add backend/app/tasks/approvals.py backend/app/tasks/approval_schemas.py backend/tests/tasks/test_task_approvals.py
  git commit -m "feat: add unified two-person task approvals"
  ```

### Task 4: Expose task approval and comment deletion HTTP APIs

**Files:**
- Create: `backend/app/tasks/approval_routes.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/app/main.py`
- Modify: `backend/app/tasks/approval_schemas.py`
- Test: `backend/tests/httpapi/test_task_approval_routes.py`
- Modify: `backend/tests/httpapi/test_lightweight_routes.py`

**Interfaces:**
- `POST /api/v1/workspaces/{workspace_id}/approval-requests` returns `201` with a serialized `TaskApprovalRequest`.
- `GET /api/v1/workspaces/{workspace_id}/approval-requests?box=incoming|outgoing` returns requests visible to the authenticated member.
- `POST /api/v1/approval-requests/{approval_id}/approve` returns `200` with `{request, task?, comment?, cursor}`.
- `POST /api/v1/approval-requests/{approval_id}/reject` returns `200` with the rejected request.
- `POST /api/v1/approval-requests/{approval_id}/cancel` returns `200` with the cancelled request.
- Non-owner `PATCH /tasks/{task_id}`, `POST /transition`, `POST /lifecycle` and `POST /restore` return `202` with `{approval_request, pending: true}` instead of changing the task.
- `DELETE /api/v1/tasks/{task_id}/comments/{comment_id}` directly soft-deletes an author-owned comment and returns `200`, or returns `202` with a `COMMENT_DELETE` request when the caller is the task owner deleting the other member's comment.

- [ ] **Step 1: Write failing HTTP tests.** Authenticate two members with the existing test helpers. Assert owner direct patch/transition responses remain task snapshots, non-owner actions create pending requests, request list filters incoming/outgoing, only the derived approver can approve, action request IDs are idempotent, comment author direct delete works, owner comment delete creates approval, and all invalid workspace/device/self-approval cases return stable 4xx codes.
- [ ] **Step 2: Run the focused HTTP tests to verify they fail.**

  Run: `cd backend && pytest tests/httpapi/test_task_approval_routes.py tests/httpapi/test_lightweight_routes.py -q`

  Expected: FAIL because routes and response unions do not exist.

- [ ] **Step 3: Add request/response schemas and router registration.** Keep task routes under `/api/v1`, add the approval router in `create_app`, require the path Workspace ID to equal `Actor.workspace_id`, and serialize UUIDs/timestamps/enums consistently with existing APIs.
- [ ] **Step 4: Route owner and non-owner writes.** Load the task before mutation, dispatch owner calls to `TaskService`, dispatch the other member to `TaskApprovalService.create`, map `approval_required` to the pending response, preserve `x-request-id` and BackgroundTasks cursor hints, and never let a pending request mutate the task response.
- [ ] **Step 5: Implement comment listing/deletion responses.** Include `version`, `deleted_at`, `deleted_by` and `can_delete`-relevant actor metadata in comment JSON; default list output keeps tombstones so both clients can render deletion history.
- [ ] **Step 6: Run HTTP, auth and device-readonly suites.**

  Run: `cd backend && pytest tests/httpapi/test_task_approval_routes.py tests/httpapi/test_lightweight_routes.py tests/httpapi/test_device_readonly_permissions.py tests/auth/test_mobile_sessions.py -q`

  Expected: PASS; PENDING devices can read requests but receive `device_not_verified` for create/approve/reject/cancel.

- [ ] **Step 7: Commit the HTTP slice.**

  ```bash
  git add backend/app/tasks/approval_routes.py backend/app/tasks/routes.py backend/app/main.py backend/app/tasks/approval_schemas.py backend/tests/httpapi/test_task_approval_routes.py backend/tests/httpapi/test_lightweight_routes.py
  git commit -m "feat: expose task approval APIs"
  ```

### Task 5: Add approval/comment resources to snapshot and incremental sync

**Files:**
- Modify: `backend/app/sync/service.py`
- Modify: `backend/app/sync/routes.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/approvals.py`
- Test: `backend/tests/httpapi/test_task_approval_sync.py`
- Modify: `backend/tests/e2e/test_cloud_protocol.py`

**Interfaces:**
- `GET /api/v1/workspaces/current/snapshot` adds `viewer_user_id` and `approval_requests` while preserving existing task/conflict fields.
- `approval_requests` entries contain `id`, `workspace_id`, `task_id`, nullable `comment_id`, `requester_id`, `approver_id`, `request_type`, `proposed_changes`, `base_field_versions`, `status`, timestamps, rejection reason and `resolved_cursor`.
- `WorkspaceChangeLog.resource_type` values used by this feature are `task`, `approval_request`, and `comment`.
- `GET /api/v1/workspaces/current/changes` serializes approval requests and comment tombstones as resources and preserves contiguous cursor behavior.

- [ ] **Step 1: Write failing sync tests.** Create two active members, one task and one pending request. Assert snapshot includes the viewer ID and request, an approval allocates one cursor, changes returns the approval resource, comment deletion produces a comment change/tombstone, and cursor expiry still falls back to a snapshot.
- [ ] **Step 2: Run the focused sync tests to verify they fail.**

  Run: `cd backend && pytest tests/httpapi/test_task_approval_sync.py tests/e2e/test_cloud_protocol.py -q`

  Expected: FAIL because snapshot and changes currently only serialize tasks/conflicts.

- [ ] **Step 3: Extend sync serialization and route decoration.** Keep `SyncService.snapshot(workspace_id)` deterministic, add `viewer_user_id` in the authenticated route layer, serialize all non-expired approval requests, and resolve `WorkspaceChangeLog.resource_id` by resource type without leaking requests from another Workspace.
- [ ] **Step 4: Emit resource changes from approval/comment operations.** Ensure approval lifecycle events and comment tombstones allocate a cursor exactly once, publish WebSocket hints only after commit, and keep task mutation cursor allocation in the same transaction.
- [ ] **Step 5: Run the full backend protocol suite.**

  Run: `cd backend && pytest -q`

  Expected: PASS for all existing cloud, auth, device, web-session and task tests plus the new approval sync tests.

- [ ] **Step 6: Commit the sync slice.**

  ```bash
  git add backend/app/sync/service.py backend/app/sync/routes.py backend/app/tasks/service.py backend/app/tasks/approvals.py backend/tests/httpapi/test_task_approval_sync.py backend/tests/e2e/test_cloud_protocol.py
  git commit -m "feat: synchronize task approvals and comment tombstones"
  ```

### Task 6: Add Flutter approval contracts and repository/controller behavior

**Files:**
- Create: `client/lib/models/task_approval_request.dart`
- Modify: `client/lib/models/task.dart`
- Modify: `client/lib/models/workspace_snapshot.dart`
- Modify: `client/lib/models/workspace_change.dart`
- Modify: `client/lib/sync/workspace_sync_repository.dart`
- Modify: `client/lib/sync/workspace_sync_controller.dart`
- Modify: `client/lib/task/cloud_task_repository.dart`
- Test: `client/test/models/task_approval_request_test.dart`
- Test: `client/test/sync/task_approval_sync_test.dart`
- Modify: `client/test/task/cloud_task_repository_test.dart`

**Interfaces:**
- `TaskItem` exposes `taskNumber`, nullable `quadrant`, nullable/derived `progress`, and existing parent/handler/version fields.
- `TaskApprovalRequest.fromJson(Map<String, dynamic>)` parses the server contract and exposes `isIncoming(String userId)` / `isOutgoing(String userId)` helpers.
- `WorkspaceSnapshot` exposes `viewerUserId` and `approvalRequests` and round-trips them through cache JSON.
- `WorkspaceSyncRepository` adds `createApprovalRequest`, `listApprovalRequests`, `approveApproval`, `rejectApproval`, `cancelApproval`, and `deleteComment` methods with typed return values.
- `WorkspaceSyncController.state` exposes `approvalRequests`; methods return pending request objects when a non-owner write receives HTTP 202 and merge approval/comment resources from cursor changes.

- [ ] **Step 1: Write failing Dart model/repository/controller tests.** Assert task number/quadrant/progress JSON, approval request parsing, snapshot cache round-trip, exact snake_case request bodies, incoming/outgoing filtering, 202 pending handling without optimistic task mutation, approval action refresh and comment tombstone merge.
- [ ] **Step 2: Run the focused Flutter tests to verify they fail.**

  Run: `cd client && flutter test test/models/task_approval_request_test.dart test/sync/task_approval_sync_test.dart test/task/cloud_task_repository_test.dart`

  Expected: FAIL with missing fields, methods and resource handling.

- [ ] **Step 3: Implement the typed contracts and HTTP repository methods.** Preserve the existing `ApiClient` error mapping, represent task-write responses as a union of `TaskItem` and `PendingApproval`, and pass a fresh UUID `request_id` plus `x-request-id` to every approval mutation.
- [ ] **Step 4: Extend the sync controller.** Store approvals in `WorkspaceSyncState`, apply `approval_request` and `comment` change resources, clear/update approval state after actions, and keep stale/read-only behavior unchanged. Do not infer the current user from `members[0]`; use `snapshot.viewerUserId`.
- [ ] **Step 5: Run the Flutter task and sync suite.**

  Run: `cd client && flutter test test/models test/task test/sync`

  Expected: PASS with no regression in task creation, transitions, conflict handling or manual refresh.

- [ ] **Step 6: Commit the Flutter data slice.**

  ```bash
  git add client/lib/models client/lib/sync client/lib/task client/test/models/task_approval_request_test.dart client/test/sync/task_approval_sync_test.dart client/test/task/cloud_task_repository_test.dart
  git commit -m "feat: add Flutter task approval sync contracts"
  ```

### Task 7: Add Android task detail and approval inbox UI

**Files:**
- Create: `client/lib/screens/task_approval_screen.dart`
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Modify: `client/lib/screens/task_detail_screen.dart`
- Test: `client/test/screens/task_approval_screen_test.dart`
- Modify: `client/test/screens/task_detail_screen_test.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`

**Interfaces:**
- `TaskApprovalScreen` receives `WorkspaceSyncController`, `currentUserId` and renders “待我审批” plus “我发起的请求”.
- `TaskDetailScreen` receives the existing task/sync inputs and derives direct-write capability from `snapshot.viewerUserId == task.currentHandlerId` plus device write permission.
- UI actions call controller methods only; no screen directly constructs approval HTTP payloads.

- [ ] **Step 1: Write failing widget tests.** Cover task number and parent/subtask labels, quadrant selector, progress selector visible only for `IN_PROGRESS`, owner direct save, non-owner save showing “等待负责人审批” without changing the task, approval inbox approve/reject/cancel actions, comment author delete, owner comment-delete request, and read-only unverified device behavior.
- [ ] **Step 2: Run the focused widget tests to verify they fail.**

  Run: `cd client && flutter test test/screens/task_approval_screen_test.dart test/screens/task_detail_screen_test.dart test/screens/cloud_workspace_screen_test.dart`

  Expected: FAIL because the approval screen and controls are absent.

- [ ] **Step 3: Implement the approval inbox screen.** Group requests by incoming/outgoing status, show task number/title, request type, requester/approver labels, proposed changes, version-conflict status and expiry/decision state. Enable approve/reject only for incoming `PENDING` requests and cancel only for outgoing `PENDING` requests.
- [ ] **Step 4: Update task detail and workspace navigation.** Display task number, parent relation, handler, quadrant and progress. Route non-owner edits through the controller's request path, render pending badges, load comments including tombstones, and add an approval-inbox entry in the workspace app bar or “我的” area.
- [ ] **Step 5: Run the complete Flutter suite and analyze.**

  Run: `cd client && flutter analyze && flutter test`

  Expected: no analyzer issues and all unit/widget tests pass. Do not run unsupported Chrome integration tests; use the existing Android/emulator integration target for any device smoke test.

- [ ] **Step 6: Commit the Android UI slice.**

  ```bash
  git add client/lib/screens client/test/screens
  git commit -m "feat: add Android task approval workflow"
  ```

### Task 8: Add Web approval API, sync and UI

**Files:**
- Modify: `web/src/api/types.ts`
- Modify: `web/src/api/client.ts`
- Modify: `web/src/sync/workspace-sync.ts`
- Modify: `web/src/tasks/task-model.ts`
- Create: `web/src/ui/approval-view.ts`
- Modify: `web/src/ui/workspace-view.ts`
- Modify: `web/src/ui/task-detail-view.ts`
- Modify: `web/src/styles.css`
- Test: `web/test/approval-view.test.ts`
- Modify: `web/test/api-client.test.ts`, `web/test/workspace-sync.test.ts`, `web/test/workspace-actions.test.ts`, `web/test/task-detail-view.test.ts`

**Interfaces:**
- `TaskApprovalRequest` mirrors the backend JSON and uses the same request/status string unions.
- `WorkspaceSnapshot` adds `viewer_user_id` and `approval_requests`; `WorkspaceChange` accepts `approval_request` and `comment` resources.
- `ApiClient` adds `createApprovalRequest`, `listApprovalRequests`, `approveApproval`, `rejectApproval`, `cancelApproval`, and `deleteTaskComment` with snake_case bodies.
- `WorkspaceSyncState.approvals` is updated by snapshots and incremental changes; pending task writes return a typed `PendingApproval` result and do not call `mergeTask` with speculative data.
- `ApprovalView.mount(root, sync, currentUserId)` returns a cleanup function and renders incoming/outgoing request boxes.

- [ ] **Step 1: Write failing Vitest tests.** Assert API paths/bodies, snapshot parsing, approval resource application, 202 pending handling, approval inbox rendering, approve/reject/cancel callbacks, owner/non-owner task detail controls, quadrant/progress fields, and comment tombstone/delete behavior.
- [ ] **Step 2: Run the focused Web tests to verify they fail.**

  Run: `cd web && npm test -- --run test/approval-view.test.ts test/api-client.test.ts test/workspace-sync.test.ts test/task-detail-view.test.ts`

  Expected: FAIL with missing types, client methods and UI.

- [ ] **Step 3: Implement the API and sync contract.** Keep `ApiClient` credentials/cookie behavior unchanged, encode `request_id`, `request_type`, `task_id`, `comment_id`, `proposed_changes` and `base_field_versions` exactly as the FastAPI schemas require, and map HTTP 202 into a visible pending approval instead of an error.
- [ ] **Step 4: Implement `ApprovalView` and workspace integration.** Add an approval inbox/outbox section without an approver selector, show stable request states and proposed fields, wire actions to `WorkspaceSyncController`, and refresh through the existing WebSocket/cursor path.
- [ ] **Step 5: Update Web task detail.** Show task number/quadrant/progress, disable direct owner-protected controls for the non-owner while providing “提交审批”, render comments with soft-delete tombstones, and allow the comment author/eligible owner actions according to the server response.
- [ ] **Step 6: Run all Web checks.**

  Run: `cd web && npm test -- --run && npm run typecheck && npm run build`

  Expected: all Vitest tests pass, TypeScript emits no errors, and Vite produces a deployable static bundle.

- [ ] **Step 7: Commit the Web slice.**

  ```bash
  git add web/src web/test
  git commit -m "feat: add Web task approval workflow"
  ```

### Task 9: Two-user end-to-end acceptance, documentation and release checks

**Files:**
- Create: `backend/tests/e2e/test_two_person_task_approval.py`
- Modify: `docs/operations/task-workflow.md`
- Modify: `docs/05-development-status.md`
- Modify: `scripts/smoke-cloud-protocol.sh` or create `scripts/smoke-two-person-task-approval.sh`
- Modify: `Makefile` with focused `test-task-approval` and `smoke-task-approval` targets

**Interfaces:**
- Acceptance harness exposes two authenticated users/devices A and B in one Workspace and uses the public HTTP contract only.
- Smoke output reports task number, request ID, approval status and final cursor without printing tokens, OTP codes or private device key material.

- [ ] **Step 1: Write the failing end-to-end acceptance test.** Exercise A creates task `YYMM0001`; B requests title/quadrant/status changes; A sees and approves; B adds a comment; A requests comment deletion and B approves; stale approval becomes `CONFLICTED`; a handler transfer cancels old pending requests; both users receive the same final snapshot and cursor.
- [ ] **Step 2: Run the acceptance test to verify the missing cross-layer behavior.**

  Run: `cd backend && pytest tests/e2e/test_two_person_task_approval.py -q`

  Expected: FAIL until all backend/client contract slices are integrated.

- [ ] **Step 3: Implement the repeatable smoke harness and documentation.** Use the existing fake SMS/device fixtures for CI, document the exact request lifecycle and UI meaning of `PENDING`, `APPROVED`, `REJECTED`, `CONFLICTED` and `CANCELLED`, and document that only the two Workspace members can ever participate.
- [ ] **Step 4: Run the full verification matrix.**

  ```bash
  cd backend && pytest -q
  cd ../web && npm test -- --run && npm run typecheck && npm run build
  cd ../client && flutter analyze && flutter test
  ```

  Expected: all backend/Web/Flutter checks pass. For device smoke, run the supported Android target, for example `flutter test integration_test/mobile_cloud_flow_test.dart -d <android-device>`. Do not claim Web Flutter integration coverage because Flutter reports that Web devices are unsupported for integration tests.

- [ ] **Step 5: Run deployment/release checks without publishing automatically.** Run `scripts/assert-client-boundary.sh`, `scripts/check-ci-trigger.py`, `scripts/check-deployment.sh` and the task approval smoke target. Confirm CI remains tag/release-triggered only, the generated Web bundle contains the new API contract, and APK naming continues to use the current commit ID for test builds.
- [ ] **Step 6: Commit the acceptance/documentation slice.**

  ```bash
  git add backend/tests/e2e/test_two_person_task_approval.py docs/operations/task-workflow.md docs/05-development-status.md scripts Makefile
  git commit -m "test: verify two-person task approval end to end"
  ```

## Self-Review Checklist

- [ ] Every requirement in `2026-08-28-two-person-task-approval-design.md` maps to at least one task: strict two-member membership (Tasks 1, 3, 4), task numbering/one-level subtasks (Tasks 1, 2, 6, 7, 8), owner-only mutation (Tasks 2, 4, 7, 8), progress/quadrant (Tasks 2, 6, 7, 8), comment soft delete (Tasks 1-5, 6-9), unified approval lifecycle (Tasks 3-5, 6-9), cursor/audit/idempotency (Tasks 3-5, 9), and Android/Web acceptance (Tasks 6-9).
- [ ] No task introduces an administrator, role hierarchy, group approval, voting or cross-Workspace access path.
- [ ] HTTP 202 pending responses are represented explicitly in both clients and never mistaken for an applied Task snapshot.
- [ ] Approval application uses one transaction and a stable idempotency key; stale requests become `CONFLICTED` rather than overwriting newer fields.
- [ ] The plan uses existing FastAPI/SQLAlchemy, Flutter and Vite boundaries and adds no required service beyond PostgreSQL.
- [ ] Test commands avoid unsupported Flutter Web integration tests and verify Web with Vitest/typecheck/build instead.

