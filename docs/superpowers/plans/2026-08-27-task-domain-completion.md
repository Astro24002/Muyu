# Task Domain Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the shared task workflow across FastAPI, Android and Web using the existing PostgreSQL task model, authoritative cursor synchronization, optimistic conflict handling and append-only activity history.

**Architecture:** PostgreSQL remains the only task fact source. FastAPI performs authorization, validation, idempotency, version checks, state changes, history writes, conflict records and cursor allocation in one transaction. Android and Web use the same `/api/v1` contracts; REST snapshot/changes is the correctness path and WebSocket only announces a newer cursor.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Alembic, PostgreSQL, pytest; Flutter Android, Dart tests; TypeScript, Vite, Vitest.

**Spec:** `docs/superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md`, `docs/superpowers/specs/2026-08-17-task-core-design.md`, `docs/superpowers/specs/2026-08-17-delay-blocking-design.md`.

## Global Constraints

- PostgreSQL is the unique source of truth for Workspace, task state, history, conflicts and synchronization cursors.
- Every visible write must perform authorization, validation, idempotency, current-state update, version update, operation/history append and `workspace_change_log` allocation in one PostgreSQL transaction.
- Task history, comments, delays, activities and conflicts are append-only; task deletion is soft deletion through `deleted_at`.
- A task has one or two ACTIVE Workspace assignees, and `current_handler_id` must be one of those assignees.
- Public task statuses are `TODO`, `IN_PROGRESS`, `WAITING`, `DONE` and `CANCELLED`; `WAITING` requires a reason and a valid resume handler.
- Field edits use `field_versions`; lifecycle/status actions use `lifecycle_version` and `status_version`; an outdated target field returns HTTP 409 and records a conflict.
- Every client write includes a UUID `request_id`; retrying the same request returns the original result without duplicate state or history.
- Only a committed server ACK makes a write successful. Offline clients may display stale cache but may not enqueue or claim offline writes.
- REST snapshot and `after_cursor` changes are the correctness path. WebSocket carries only `workspace.changed` and a cursor.
- The current delivery targets Android and Web. Do not add iOS code, P2P synchronization, encrypted task payloads, Elasticsearch/OpenSearch, attachments, project hierarchy, or third-party workflow configuration in this plan.
- Do not put SMS AppCode, database URLs, bearer tokens, cookies, private keys or real user data in source, tests, documentation or APK build arguments.

## Baseline and File Ownership

The existing backend task service and models are the baseline; implementation tasks must extend them instead of introducing parallel repositories or schemas.

- `backend/app/db/models.py`: authoritative task, assignee, operation, conflict, comment, delay, activity, status-history and handler-history tables.
- `backend/app/tasks/service.py`: domain validation and transactional mutation service.
- `backend/app/tasks/routes.py`: authenticated `/api/v1/tasks` HTTP contract.
- `backend/app/tasks/schemas.py`: request validation and public status input.
- `backend/app/tasks/sync.py` and `backend/app/workspaces/routes.py`: snapshot/change cursor reads.
- `client/lib/task/cloud_task_repository.dart`: Android task mutation API adapter.
- `client/lib/sync/workspace_sync_controller.dart`: Android snapshot, cursor and mutation state.
- `client/lib/screens/cloud_workspace_screen.dart` and `client/lib/screens/task_detail_screen.dart`: Android task UI.
- `web/src/api/client.ts`, `web/src/sync/workspace-sync.ts`, `web/src/ui/workspace-view.ts`, `web/src/ui/task-detail-view.ts`: Web API, sync and UI.

### Task 1: Freeze the Task HTTP and Database Contract

**Files:**
- Modify: `backend/tests/httpapi/test_lightweight_routes.py`
- Modify: `backend/tests/tasks/test_lightweight_contract.py`
- Modify: `backend/tests/tasks/test_cloud_mutations.py`
- Modify: `backend/tests/tasks/test_lightweight_timeline.py`
- Test: `backend/tests/httpapi/test_task_contract_regressions.py`

**Interfaces:**
- Consumes current `TaskService`, `/api/v1/tasks`, `/api/v1/workspaces/current/snapshot` and `/api/v1/workspaces/current/changes` routes.
- Produces executable contract coverage for Tasks 2-8: JSON field names, status values, cursor behavior, idempotency and stable error codes.

- [ ] **Step 1: Write failing contract tests** for authenticated task creation, empty title rejection, one-level child creation, second-level child rejection, and `GET /api/v1/tasks/{id}` returning 404 for another Workspace.
- [ ] **Step 2: Run the contract tests and verify they fail for the missing assertion or behavior.** Set `TEST_DATABASE_URL` to a disposable PostgreSQL URL, then run `make backend-test` with the focused pytest path; expected failures must identify the task contract, not fixture setup.
- [ ] **Step 3: Add only the minimum route/schema/model correction needed for the frozen contract.** Preserve `/api/v1` paths and current JSON snake_case names.
- [ ] **Step 4: Run focused tests and compile checks.** Run `python -m pytest -q backend/tests/httpapi/test_lightweight_routes.py backend/tests/tasks/test_lightweight_contract.py` inside the backend test environment and `python -m compileall -q app alembic`.
- [ ] **Step 5: Commit** with `git add backend/tests backend/app && git commit -m "test: freeze task HTTP contract"`.

### Task 2: Complete Server-Side Task Creation and Editing

**Files:**
- Modify: `backend/app/tasks/schemas.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/tests/tasks/test_cloud_mutations.py`
- Modify: `backend/tests/httpapi/test_lightweight_routes.py`

**Interfaces:**
- Consumes Task 1 contract tests and `CreateTaskRequest`, `PatchTaskRequest`.
- Produces `POST /api/v1/tasks` returning a complete task snapshot plus `cursor`, and `PATCH /api/v1/tasks/{task_id}` using `{request_id, changes, base_field_versions}`.

- [ ] **Step 1: Add failing tests** for trimmed title validation, default `TODO`, default creator/handler/assignee, explicit one-or-two active assignees, planned start/due/estimate fields, field-level concurrent edits, stale field conflict, and same-request replay returning the original cursor.
- [ ] **Step 2: Run the focused tests and verify the expected failures.** Run `python -m pytest -q backend/tests/tasks/test_cloud_mutations.py -k 'create or patch or field'` in the disposable PostgreSQL test environment.
- [ ] **Step 3: Implement the minimal service behavior.** Validate Workspace membership before task creation; normalize title; create `TaskAssignee` and `TaskUserPosition`; update only `MUTABLE_FIELDS`; increment field versions and overall `version`; write operation/activity/change cursor in the same transaction.
- [ ] **Step 4: Verify API behavior.** Run the focused HTTP tests and assert response fields `id`, `workspace_id`, `title`, `status`, `assignee_ids`, `current_handler_id`, `version`, `field_versions` and `cursor`.
- [ ] **Step 5: Commit** with `git add backend/app/tasks backend/tests && git commit -m "feat: complete task creation and editing contract"`.

### Task 3: Complete Status, Handler and Lifecycle Actions

**Files:**
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/tests/tasks/test_lightweight_contract.py`
- Modify: `backend/tests/httpapi/test_lightweight_routes.py`

**Interfaces:**
- Consumes Task 2 task snapshots and version fields.
- Produces authenticated actions for transition, completion, reopen, cancellation, block/unblock, transfer, soft delete and restore with stable 409/422 errors.

- [ ] **Step 1: Add failing tests** for every allowed transition, rejected transition, `WAITING` reason/handler validation, handler reassignment, deleted-task restrictions, parent deletion with live children, restore, lifecycle conflict, and status-version conflict.
- [ ] **Step 2: Run the focused tests and confirm failures are behavior-specific.** Use `python -m pytest -q backend/tests/tasks/test_lightweight_contract.py -k 'status or handler or lifecycle or deleted'`.
- [ ] **Step 3: Implement state-machine and lifecycle rules.** Keep status changes out of PATCH; increment `version`, `status_version` and `lifecycle_version` as defined; append status/handler histories and activities; reject invalid handlers and non-member waiting users.
- [ ] **Step 4: Verify idempotency and conflict responses.** Repeat each action with the same `request_id` and assert one operation/cursor; send an outdated version and assert HTTP 409 with `details.conflicts`.
- [ ] **Step 5: Commit** with `git add backend/app/tasks backend/tests && git commit -m "feat: enforce task lifecycle and status actions"`.

### Task 4: Complete Comments, Delays and Activity Timeline

**Files:**
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/tests/tasks/test_lightweight_timeline.py`
- Modify: `backend/tests/httpapi/test_lightweight_routes.py`

**Interfaces:**
- Consumes Task 3 deletion and permission rules.
- Produces append-only `POST/GET /api/v1/tasks/{id}/comments`, `POST/GET /api/v1/tasks/{id}/delays` and `GET /api/v1/tasks/{id}/activity` behavior.

- [ ] **Step 1: Add failing tests** for comment creation/read ordering, rejection on deleted tasks, delay duration calculation, due-date update, delay history, activity payload, and request replay.
- [ ] **Step 2: Run focused timeline tests and verify red.** Run `python -m pytest -q backend/tests/tasks/test_lightweight_timeline.py`.
- [ ] **Step 3: Implement one-transaction append behavior.** A delay must create `DelayRecord`, update `due_at`, append `TaskOperation` and `ActivityEvent`, and allocate one Workspace cursor. Comments must never be updated or deleted.
- [ ] **Step 4: Verify API JSON and ordering.** Run the timeline HTTP tests and assert missing tasks return 404 rather than an empty collection.
- [ ] **Step 5: Commit** with `git add backend/app/tasks backend/tests && git commit -m "feat: add task comments delays and timeline"`.

### Task 5: Harden Conflict Resolution and Cursor Idempotency

**Files:**
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/tests/tasks/test_cloud_mutations.py`
- Modify: `backend/tests/e2e/test_cloud_protocol.py`

**Interfaces:**
- Consumes `TaskConflict`, `TaskOperation` and `workspace_change_log` records from Tasks 2-4.
- Produces `GET /api/v1/tasks/{id}/conflicts` and `POST /api/v1/tasks/{id}/conflicts/{conflict_id}/resolve` with current/proposed resolution and idempotent cursors.

- [ ] **Step 1: Add failing tests** for different-field auto-merge, same-field 409 creation, current-value resolution, proposed-value resolution based on the latest field version, conflict replay, request-id payload mismatch, and monotonic cursor assignment.
- [ ] **Step 2: Run focused conflict tests and verify red.** Run `python -m pytest -q backend/tests/tasks/test_cloud_mutations.py -k 'conflict or cursor or idempot'`.
- [ ] **Step 3: Implement strict resolution.** Lock the task and conflict rows, require OPEN conflict state, apply the selected value as a new versioned operation, mark resolution metadata, and append activity/change records in one transaction.
- [ ] **Step 4: Verify no duplicate side effects.** Query operation, conflict, activity and change rows after retries and assert exactly one new record per accepted request.
- [ ] **Step 5: Commit** with `git add backend/app/tasks backend/tests && git commit -m "feat: harden task conflicts and cursor idempotency"`.

### Task 6: Finish Android Repository and Synchronization Writes

**Files:**
- Modify: `client/lib/task/cloud_task_repository.dart`
- Modify: `client/lib/sync/workspace_sync_repository.dart`
- Modify: `client/lib/sync/workspace_sync_controller.dart`
- Modify: `client/test/task/cloud_task_repository_test.dart`
- Modify: `client/test/sync/workspace_sync_controller_test.dart`
- Create: `client/test/task/task_creation_flow_test.dart`

**Interfaces:**
- Consumes `/api/v1/tasks` and snapshot/change contracts from Tasks 1-5.
- Produces Android methods `create`, `update`, `transition`, `addComment`, `addDelay`, `refresh`, `pull`, and `resolveConflict`; each write uses a fresh UUID request ID and authoritative refresh after ACK.

- [ ] **Step 1: Add failing Dart tests** for `create` request body, generated request ID, returned task parsing, 409 preservation, successful task insertion, and cursor reconciliation after creation.
- [ ] **Step 2: Run focused Flutter tests and verify red.** Run `cd client && flutter test test/task/task_creation_flow_test.dart test/task/cloud_task_repository_test.dart`.
- [ ] **Step 3: Implement the smallest repository/controller changes.** Send `request_id`, title and optional fields in snake_case; update the current snapshot only from server response; call `pull()` or `refresh()` to establish the authoritative cursor; never add an offline creation queue.
- [ ] **Step 4: Run focused and full client tests.** Run `cd client && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`.
- [ ] **Step 5: Commit** with `git add client/lib client/test && git commit -m "feat: complete Android task synchronization writes"`.

### Task 7: Add Android Task Creation and Detail Actions

**Files:**
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Modify: `client/lib/screens/task_detail_screen.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`
- Modify: `client/test/screens/task_detail_screen_test.dart`

**Interfaces:**
- Consumes Task 6 repository/controller methods and `WorkspaceSnapshot` task/member data.
- Produces a usable Android workflow for creating a task, opening details, editing fields, choosing a handler, starting/completing/cancelling/reopening, adding comments, recording delays and resolving conflicts.

- [ ] **Step 1: Add failing Widget tests** for title-only creation, disabled submit while creating, failed creation retaining input, successful creation appearing in the list, and task detail actions using current task versions.
- [ ] **Step 2: Run the focused Widget tests and verify red.** Run `cd client && flutter test test/screens/cloud_workspace_screen_test.dart test/screens/task_detail_screen_test.dart`.
- [ ] **Step 3: Implement the UI with existing Material components.** Keep the creation form compact; title is required, other fields remain in detail editing. Show stale/error state without claiming offline success; keep scanner accessible only inside the ready Workspace screen.
- [ ] **Step 4: Run the complete Android test suite and analyzer.** Run `cd client && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`.
- [ ] **Step 5: Commit** with `git add client/lib/screens client/test/screens && git commit -m "feat: expose Android task creation and actions"`.

### Task 8: Complete Web Task Views and Conflict Interaction

**Files:**
- Modify: `web/src/api/client.ts`
- Modify: `web/src/api/types.ts`
- Modify: `web/src/sync/workspace-sync.ts`
- Modify: `web/src/ui/workspace-view.ts`
- Modify: `web/src/ui/task-detail-view.ts`
- Modify: `web/src/styles.css`
- Modify: `web/test/workspace-actions.test.ts`
- Modify: `web/test/workspace-sync.test.ts`
- Create: `web/test/task-detail-view.test.ts`

**Interfaces:**
- Consumes the same `/api/v1/tasks` payloads and cursor/conflict semantics as Android.
- Produces Web task creation, editing, status actions, comments, delays, detail history and conflict resolution without browser-local identity or a second data model.

- [ ] **Step 1: Add failing Vitest tests** for create form submission, task detail rendering, status action payloads, comments/delays, conflict resolution and 401/409 error display.
- [ ] **Step 2: Run the focused tests and verify red.** Run `cd web && npm test -- --run test/task-detail-view.test.ts test/workspace-actions.test.ts`.
- [ ] **Step 3: Implement UI/API changes.** Preserve snake_case wire payloads and `credentials: 'include'`; use the current snapshot task as the edit base; update state only after server ACK; retain conflicts until successful resolution.
- [ ] **Step 4: Run Web verification.** Run `cd web && npm run typecheck && npm test -- --run && npm run build`.
- [ ] **Step 5: Commit** with `git add web/src web/test && git commit -m "feat: complete Web task views and conflicts"`.

### Task 9: End-to-End Acceptance, Documentation and APK Release

**Files:**
- Modify: `backend/tests/e2e/test_cloud_protocol.py`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`
- Modify: `web/test/app.test.ts`
- Modify: `docs/05-development-status.md`
- Modify: `docs/operations/release-checklist.md`
- Create: `docs/operations/task-workflow.md`

**Interfaces:**
- Consumes all task APIs and client flows from Tasks 1-8.
- Produces a repeatable two-user PostgreSQL acceptance script and a documented Android/Web release artifact tied to a source commit.

- [ ] **Step 1: Add failing end-to-end acceptance coverage** for User A creating a task, User B seeing it after cursor sync, concurrent field edits, one conflict resolution, a status transition, a comment, a delay, soft delete and restore.
- [ ] **Step 2: Run the focused E2E test against a disposable PostgreSQL database and verify red.** Set `TEST_DATABASE_URL` to a disposable PostgreSQL URL, then run `python -m pytest -q backend/tests/e2e/test_cloud_protocol.py -k task` in the backend test environment.
- [ ] **Step 3: Implement only the missing integration wiring and test fixtures.** Keep production API and client boundaries unchanged; do not seed or mutate the production database.
- [ ] **Step 4: Run the complete verification matrix.** With `TEST_DATABASE_URL` set to the disposable PostgreSQL URL, execute:
  `make backend-test`,
  `make client-test`,
  `cd web && npm ci && npm run typecheck && npm test -- --run && npm run build`,
  `make boundary-check`, and `make check-deployment`.
- [ ] **Step 5: Build and identify the Android artifact.** Run `API_BASE_URL=https://muyu.bkverse.space make client-build`, then `commit_id=$(git rev-parse --short HEAD)`, `cp client/build/app/outputs/flutter-apk/app-debug.apk client/build/app/outputs/flutter-apk/Muyu-${commit_id}.apk`, and `sha256sum client/build/app/outputs/flutter-apk/Muyu-${commit_id}.apk`.
- [ ] **Step 6: Run manual acceptance when an Android device is connected.** Set `apk_path=client/build/app/outputs/flutter-apk/Muyu-${commit_id}.apk` and install with `adb install -r "$apk_path"`; verify task creation, Web QR login, shared visibility, conflict display and no offline-success claim. If `adb devices` has no device, record that fact as pending rather than claiming success.
- [ ] **Step 7: Document actual evidence and commit.** Update `docs/operations/task-workflow.md`, `docs/05-development-status.md` and `docs/operations/release-checklist.md` with only observed results, then run `git diff --check` and commit with `git add docs && git commit -m "docs: record task workflow acceptance"`.

## Final Acceptance Matrix

| Area | Evidence | Required result |
| --- | --- | --- |
| Task data | PostgreSQL model/service tests | Current task state and append-only history remain consistent |
| Creation/editing | HTTP contract tests | `201` create, validated PATCH, stable `409` conflicts, idempotent retry |
| State/lifecycle | Domain + HTTP tests | Allowed transitions succeed; invalid/deleted actions are rejected |
| Comments/delays | Timeline tests | Append-only records, due-date update and activity/cursor are atomic |
| Synchronization | Backend E2E + Android/Web sync tests | Snapshot and after-cursor converge both clients; notifications contain no business data |
| Android | Flutter tests + APK build | Create/detail/actions work only after Workspace is ready; no offline write queue |
| Web | Vitest/typecheck/build | Same task contract and conflict semantics; QR remains the only login path |
| Deployment | Boundary/deployment checks | No iOS/P2P/legacy runtime or secret leakage introduced |
| Real interoperability | Android device + `https://muyu.bkverse.space` | A created Workspace permits QR login; missing membership remains rejected |

## Self-Review

- Spec coverage: tasks 1-5 cover the complete server fact model, transactions, lifecycle, comments, delays, conflicts and cursor rules; tasks 6-8 cover both clients; task 9 covers integration and release evidence.
- Scope: no new service, database technology, encryption layer, offline queue, iOS target or project-management hierarchy is introduced.
- Type consistency: backend request fields use `request_id`, `base_field_versions`, `base_status_version`, `target_status`; Dart/TypeScript adapters translate only their local naming to these exact snake_case fields.
- Placeholder scan: commands use the existing `TEST_DATABASE_URL`, `commit_id` and `apk_path` shell variables; no undefined code symbols or unassigned implementation placeholders are required.
- Acceptance honesty: real-device results are recorded only when `adb devices` exposes a connected device and the listed flows are actually performed.
