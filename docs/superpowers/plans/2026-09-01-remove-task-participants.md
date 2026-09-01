# Remove Task Participants and Add Account Overview Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the obsolete task-participant model from the database, FastAPI, Flutter, and TypeScript contracts; make `current_handler_id` the sole task owner; preserve the existing two-person approval rules; and add the Android “我的” account overview and partner entry without expanding the product into an analytics subsystem.

**Architecture:** Tasks remain append-only business resources in the existing PostgreSQL/FastAPI snapshot and incremental-sync model. Every active Workspace member can read every non-deleted task and subtask. A task is directly writable by its `current_handler_id`; the other member uses the existing one-request/one-approver approval flow. The Android profile derives compact statistics from the already-synced snapshot and receives the current user’s and partner’s totals from the same source. No new owner column, participant table, analytics API, statistics table, or multi-user approval model is introduced.

**Tech Stack:** FastAPI, SQLAlchemy 2, Alembic, PostgreSQL, pytest; Flutter/Dart; TypeScript + Vite; existing Workspace snapshot/incremental sync and Android `CloudWorkspaceScreen`.

**Spec:** `docs/superpowers/specs/2026-09-01-remove-task-participants-design.md` is the authoritative behavior contract. The implementation must not retain an `assignee_ids` compatibility field.

## Global Constraints

- Preserve `tasks.current_handler_id`, `resume_handler_id`, task status, labels, quadrant, comments, delays, blocking, activity history, device authorization, and Web session behavior.
- Do not add `owner_user_id`, `participants`, `assignees`, role hierarchy, admin approval, group approval, or cross-Workspace access.
- A Workspace has at most two active members. Both members can read all non-deleted tasks, including subtasks. “我的任务” means `current_handler_id == current_user_id` only.
- A task created without an explicit handler continues to default to its creator. Handler transfer and blocking recovery continue to validate an ACTIVE member in the same Workspace.
- The API must reject a request containing `assignee_ids` through the existing strict Pydantic request models and must never emit that field in task, snapshot, change, or approval payloads.
- Development data loss is allowed only through the explicit migration/reset steps below. Do not silently rewrite an invalid task owner.
- Keep the repository’s existing formatting, API error envelope, cursor semantics, soft-delete rules, and test naming conventions.
- Every implementation task starts with a failing or contract-tightening test, runs that test red, applies the smallest change, then runs it green before moving on.

## Task 1: Lock the new contract with failing tests

**Files:**

- Modify `backend/tests/tasks/test_lightweight_contract.py`, `backend/tests/tasks/test_cloud_mutations.py`, `backend/tests/tasks/test_two_person_task_domain.py`, `backend/tests/tasks/test_task_approvals.py`, `backend/tests/httpapi/test_lightweight_routes.py`, `backend/tests/httpapi/test_task_contract_regressions.py`, `backend/tests/e2e/test_cloud_protocol.py`, `backend/tests/e2e/test_two_person_task_approval.py`, and `backend/tests/db/test_task_approval_schema.py`.
- Modify `client/test/models/task_test.dart`, `client/test/models/task_view_test.dart`, `client/test/task/cloud_task_repository_test.dart`, `client/test/sync/workspace_sync_controller_test.dart`, `client/test/sync/task_approval_sync_test.dart`, `client/test/screens/task_detail_screen_test.dart`, `client/test/screens/cloud_workspace_screen_test.dart`, and `client/test/models/task_approval_request_test.dart`.
- Modify `web/test/task-view-model.test.ts`, `web/test/task-detail-view.test.ts`, `web/test/workspace-actions.test.ts`, `web/test/workspace-sync.test.ts`, and `web/test/approval-view.test.ts`.

- [ ] Replace test fixtures that currently require `assignee_ids` with a task containing only `current_handler_id`; keep at least one fixture with a distinct current handler to prove the “mine” filter is owner-only.
- [ ] Add backend API assertions that task create/update, task detail, snapshot, incremental task changes, and approval task payloads omit `assignee_ids`.
- [ ] Add a strict-request regression asserting `POST /tasks` rejects a top-level `assignee_ids` property and `PATCH /tasks/{id}` rejects `changes.assignee_ids`, both with HTTP 422 and the normal validation envelope.
- [ ] Add approval regressions asserting `ASSIGNEE_UPDATE` is not an accepted request type and that the remaining `TASK_UPDATE`, `QUADRANT_UPDATE`, `HANDLER_TRANSFER`, status, comment, and delete flows remain valid.
- [ ] Add Flutter model/repository tests asserting `TaskItem.fromJson` accepts the new payload without `assignee_ids`, `toJson` omits it, and create/update request bodies do not contain it.
- [ ] Add Flutter and Web view-model tests asserting a task assigned to the other member is absent from “我的任务” even when it used to be listed as a participant.
- [ ] Add a red Android profile test fixture with a parent task, a child task, completed/open tasks, and delay totals; assert the future overview contract includes both parent and child.
- [ ] Run the focused suites and record the expected failures before implementation:

  ```bash
  cd backend && python -m pytest -q tests/tasks/test_lightweight_contract.py tests/tasks/test_cloud_mutations.py tests/tasks/test_two_person_task_domain.py tests/tasks/test_task_approvals.py tests/httpapi/test_lightweight_routes.py tests/httpapi/test_task_contract_regressions.py tests/e2e/test_cloud_protocol.py tests/e2e/test_two_person_task_approval.py tests/db/test_task_approval_schema.py
  cd ../client && flutter test test/models/task_test.dart test/models/task_view_test.dart test/task/cloud_task_repository_test.dart test/sync/workspace_sync_controller_test.dart test/sync/task_approval_sync_test.dart test/screens/task_detail_screen_test.dart test/screens/cloud_workspace_screen_test.dart test/models/task_approval_request_test.dart
  cd ../web && npm test -- --run test/task-view-model.test.ts test/task-detail-view.test.ts test/workspace-actions.test.ts test/workspace-sync.test.ts test/approval-view.test.ts
  ```

## Task 2: Remove participants from the FastAPI domain and wire contracts

**Files:**

- Modify `backend/app/db/models.py` and `backend/app/tasks/models.py`.
- Modify `backend/app/tasks/schemas.py`, `backend/app/tasks/service.py`, and `backend/app/tasks/routes.py`.
- Modify `backend/app/db/enums.py`, `backend/app/tasks/approval_schemas.py`, and `backend/app/tasks/approvals.py`.
- Update the backend tests listed in Task 1 as each behavior is changed.

- [ ] Delete the `TaskAssignee` ORM class and its export. Remove every import, relationship, query, insert, delete, and membership-set validation that refers to it.
- [ ] Remove `assignee_ids` from `MUTABLE_FIELDS`, `CreateTaskRequest`, create method signatures, route forwarding, update parsing, field-version snapshots, fingerprints, conflict application, and task snapshots; add an explicit `PatchTaskRequest` validator that rejects `changes.assignee_ids` rather than silently ignoring it.
- [ ] Keep task creation defaulting `current_handler_id` to `actor_user_id`; validate that handler and `resume_handler_id` are ACTIVE members of the same Workspace through the existing `_validated_member` path.
- [ ] Change task reads/listing to authorize by Workspace membership only. Do not add a participant filter; retain soft-deleted exclusion and existing cursor behavior.
- [ ] Remove the `ASSIGNEE_UPDATE` route inference branch. The remaining change-set inference must route handler changes to `HANDLER_TRANSFER`, quadrant changes to `QUADRANT_UPDATE`, and other mutable fields to `TASK_UPDATE` according to the existing rules.
- [ ] Remove the `ASSIGNEE_UPDATE` enum member and all approval-schema validation, decode, apply, and error branches. Ensure approval application still handles handler transfer and blocking recovery without consulting a participant set.
- [ ] Keep `TASK_UPDATE_FIELDS` limited to fields still directly/indirectly supported by the spec; explicitly exclude `quadrant` and `current_handler_id` because their specialized approval paths remain.
- [ ] Update the task snapshot serializer and all API response assertions so the public task shape contains `current_handler_id` but no participant collection.
- [ ] Run the backend focused tests with the repository target `make backend-test PYPI_INDEX_URL=http://mirrors.aliyun.com/pypi/simple/`; the suite must pass before starting the migration task.

## Task 3: Add the PostgreSQL migration and invalidate old snapshots

**Files:**

- Add `backend/alembic/versions/0005_remove_task_assignees.py` with `down_revision = "0004_task_labels_quadrant"`.
- Modify `backend/tests/db/test_cloud_schema.py`, `backend/tests/db/test_task_approval_schema.py`, and add `backend/tests/db/test_remove_task_participants_migration.py`.
- Modify `client/lib/sync/workspace_cache.dart` and its cache tests.

- [ ] In the migration, first fail with a clear exception if any non-deleted task has a null `current_handler_id` or a handler that is not an ACTIVE member of its Workspace; never silently select a replacement owner.
- [ ] Delete development-only `task_approval_requests` rows whose `request_type = 'ASSIGNEE_UPDATE'` before replacing the PostgreSQL enum, because those requests are no longer meaningful and development data may be discarded.
- [ ] Rebuild `task_approval_request_type` with exactly `TASK_UPDATE`, `QUADRANT_UPDATE`, `STATUS_UPDATE`, `TASK_DELETE`, `TASK_RESTORE`, `COMMENT_DELETE`, and `HANDLER_TRANSFER`; alter `task_approval_requests.request_type` through a text cast, drop the old enum, and rename the replacement. Preserve the status enum and all other approval rows.
- [ ] Drop `task_assignees` with its foreign keys and indexes using an idempotent `DROP TABLE IF EXISTS task_assignees CASCADE`; do not alter `tasks.current_handler_id` or historical task/event/comment/delay rows.
- [ ] Provide a downgrade that recreates the table and enum label only for migration tooling; it must not fabricate historical participant rows. Document that downgrade restores schema shape, not deleted participant data.
- [ ] Add schema tests that run upgrade from the current head and assert the table is absent, the enum labels match the new set, and task owner/history tables remain present.
- [ ] Bump the Flutter snapshot cache namespace from `muyu.workspace.snapshot.$workspaceId` to the exact key `muyu.workspace.snapshot.v2.$workspaceId` and update cache tests to prove an old payload cannot be read as a current snapshot. Keep the existing last-known-good behavior for refresh failures.
- [ ] Apply the migration against the development database with `alembic upgrade head`, then run the migration/schema tests.

## Task 4: Remove the participant field from Flutter models, sync, and task detail

**Files:**

- Modify `client/lib/models/task.dart`, `client/lib/models/task_view.dart`.
- Modify `client/lib/task/cloud_task_repository.dart`, `client/lib/sync/workspace_sync_repository.dart`, and `client/lib/sync/workspace_sync_controller.dart`.
- Modify `client/lib/screens/task_detail_screen.dart` and any task-create form that forwards `assigneeIds`.
- Update the Flutter tests listed in Task 1 and all compile errors from `rg -n "assigneeIds|assignee_ids|TaskAssignee" client/lib client/test`.

- [ ] Remove the `TaskItem.assigneeIds` constructor parameter, field, JSON parse, copy behavior, and JSON serialization. Keep the constructor strict for all required current task fields, including quadrant.
- [ ] Change `TaskView.mine` to filter only `task.currentHandlerId == userId`; leave list, quadrant, schedule, label, status, and subtask grouping behavior unchanged.
- [ ] Remove optional `assigneeIds` arguments and body keys from the cloud repository, sync repository, and sync controller create/update paths. Preserve request IDs, optimistic replacement, cursor handling, and approval results.
- [ ] Delete participant selection and participant-derived fallback handler options from task detail. The resume-handler and current-handler controls must be populated only from active Workspace members and must continue to show the current handler.
- [ ] Ensure non-owner edits still submit the same protected-field approval request and no longer produce an assignee-specific request type.
- [ ] Update every Dart task fixture and fake repository method to the new signatures. Run `dart format` on changed Dart files.
- [ ] Run `flutter test` over the full client test suite and `flutter analyze`; no `assigneeIds`, `assignee_ids`, or `TaskAssignee` reference may remain under `client/lib`.

## Task 5: Remove the participant field from the TypeScript/Web contract

**Files:**

- Modify `web/src/api/types.ts`, `web/src/tasks/task-model.ts`, and `web/src/tasks/task-view-model.ts`.
- Modify `web/src/ui/task-detail-view.ts`, `web/src/ui/approval-view.ts`, `web/src/sync/workspace-sync.ts`, `web/src/ui/workspace-view.ts`, and `web/src/api/client.ts` wherever the removed property is forwarded or rendered.
- Update `web/test/task-view-model.test.ts`, `web/test/task-detail-view.test.ts`, `web/test/workspace-actions.test.ts`, `web/test/workspace-sync.test.ts`, and `web/test/approval-view.test.ts`.

- [ ] Remove `assignee_ids` from `TaskItem`, `EditableTaskChanges`, `TaskApprovalRequestType`, and all request/response helper types.
- [ ] Change `filterMyTasks` to the sole current-handler predicate. Keep all Workspace membership-based reads and current-handler display/transfer behavior.
- [ ] Remove participant controls, handler-option derivation from participant IDs, assignee-specific dirty-field handling, and assignee approval rendering from the detail and approval views.
- [ ] Ensure Web create/update payload builders omit the removed property and still send current handler, quadrant, labels, status, comments, and delay fields through their existing approval paths.
- [ ] Run `npm test -- --run`, `npm run typecheck`, `npm run build`, and a repository-wide Web search proving no source/test reference to `assignee_ids`, `ASSIGNEE_UPDATE`, or `assigneeIds` remains.

## Task 6: Add the Android account overview and partner entry

**Files:**

- Add `client/lib/models/task_overview.dart` with the immutable `TaskOverview.fromTasks(Iterable<TaskItem>, String userId)` value type.
- Modify `client/lib/screens/my_profile_screen.dart` and `client/lib/screens/cloud_workspace_screen.dart`.
- Modify `client/test/screens/my_profile_screen_test.dart`, `client/test/screens/my_profile_workspace_match_test.dart`, and `client/test/screens/cloud_workspace_screen_test.dart`; add `client/test/models/task_overview_test.dart` if the value type is a separate file.

- [ ] Define `TaskOverview` with `taskCount`, `unfinishedCount`, `completedCount`, `delayCount`, and `totalDelayMinutes`; derive only non-deleted tasks whose `currentHandlerId` equals the requested user, counting parents and children independently.
- [ ] Add formatting helpers for total delay as days/hours/minutes without losing the raw minute total. Zero values must render as `0` rather than an empty state.
- [ ] Pass the current `WorkspaceSyncController` snapshot into the profile screen (or pass equivalent derived values) so the overview updates when sync refreshes and remains unchanged when refresh fails.
- [ ] Merge the account and matched-workspace presentation into one compact account card. Show the current user nickname/masked phone, `已匹配` state, the partner avatar button, and the current user overview. Keep the existing two-member status and pending device-authorization sections below it.
- [ ] Move the Web QR login action to the profile AppBar’s top-right `IconButton` with stable key `profile-web-qr-login`; remove the large body ListTile so Web login is not duplicated in the page content.
- [ ] Make the partner avatar open a compact bottom sheet/dialog showing the partner’s display name/status and the partner overview. Resolve the partner as the other active Workspace member; do not introduce a participant or “task participant” label.
- [ ] Preserve the existing device list, revoke behavior, incoming/outgoing device authorization requests, and current-device deletion restriction.
- [ ] Add widget tests for: QR action placement and callback, matched account card, parent+child counts, delay aggregation, partner overview, and no QR ListTile in the body. Run `flutter test` for all profile/cloud-workspace tests and `flutter analyze`.

## Task 7: Update active documentation and perform full verification

**Files:**

- Modify `docs/01-product.md`, `docs/03-roadmap.md`, and `docs/05-development-status.md`.
- Add a short superseded-decision note to historical specs that still describe participants: `docs/superpowers/specs/2026-08-17-task-core-design.md`, `docs/superpowers/specs/2026-08-17-delay-blocking-design.md`, `docs/superpowers/specs/2026-08-26-lightweight-action-first-design.md`, and `docs/superpowers/specs/2026-08-28-two-person-task-approval-design.md`. Do not rewrite historical decision bodies.
- Keep `docs/superpowers/specs/2026-09-01-remove-task-participants-design.md` as the current authority and link it from active documents.

- [ ] Replace active product/roadmap language that says a task has one or two participants with “one current handler”; describe Workspace-wide read access and the existing opposite-member approval rule.
- [ ] Document that the Android profile overview counts all owned tasks, including subtasks, and that the partner avatar exposes the same compact analysis.
- [ ] Record the migration and cache namespace change in development status, including the intentional removal of obsolete participant data in the development database.
- [ ] Run repository-wide searches:

  ```bash
  rg -n "assignee_ids|assigneeIds|TaskAssignee|task_assignees|ASSIGNEE_UPDATE" backend/app backend/tests client/lib client/test web/src web/test docs/01-product.md docs/03-roadmap.md docs/05-development-status.md
  ```

  The only allowed matches are the current design spec and explicit superseded-history notes.

- [ ] Run `make backend-test PYPI_INDEX_URL=http://mirrors.aliyun.com/pypi/simple/` with the configured PostgreSQL test database, then run `flutter test`, `flutter analyze`, `npm test -- --run`, `npm run typecheck`, and `npm run build`.
- [ ] Run `alembic upgrade head` against a clean development database and repeat the backend schema/API smoke tests. Verify with SQL that `to_regclass('task_assignees') IS NULL` and that `current_handler_id` remains populated for every non-deleted task.
- [ ] Build the local Android debug artifact with the current commit suffix, not the generic Gradle name:

  ```bash
  cd client
  commit_id=$(git rev-parse --short HEAD)
  flutter build apk --debug
  cp build/app/outputs/flutter-apk/app-debug.apk "build/app/outputs/flutter-apk/Muyu-${commit_id}.apk"
  test -s "build/app/outputs/flutter-apk/Muyu-${commit_id}.apk"
  ```

- [ ] Verify the APK embeds `https://muyu.bkverse.space`, install/launch it against the current API, log in with an approved Android device, create a task, verify the other member can read it, verify only the current handler can write directly, and verify the profile overview includes a subtask and delay totals.
- [ ] Commit implementation in logical commits, then create the final release commit/tag only after all tests and the APK artifact check pass. The CI workflow must remain release/tag-triggered as previously specified; do not reintroduce push-triggered APK jobs.

## Expected Final Contract

- PostgreSQL has no `task_assignees` table and the approval enum has no `ASSIGNEE_UPDATE` value.
- Task create, update, snapshot, change, and approval payloads contain `current_handler_id` but never `assignee_ids`.
- Both active Workspace members read all non-deleted parent and child tasks. “我的任务” is an exact current-handler filter.
- Direct writes, opposite-member approvals, handler transfer, blocking recovery, comments, delays, labels, quadrants, device authorization, and Web pairing retain their existing semantics.
- Android “我的” shows the current account overview, matched partner avatar, partner overview entry, and the Web QR login action only in the AppBar.
- The final verification record includes passing backend/Flutter/Web suites, migration checks, and a commit-suffixed local APK; no claim of completion is made without those outputs.
