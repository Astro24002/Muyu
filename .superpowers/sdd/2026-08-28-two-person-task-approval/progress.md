# SDD ledger — plan: docs/superpowers/plans/2026-08-28-two-person-task-approval.md

## Preflight scan

| Scope | Shared file/interface or internal consistency check | Result / ruling |
|---|---|---|
| Task 1 ↔ Task 2 | `db/enums.py`, `db/models.py`, `Task` fields and migration outputs consumed by `TaskService` | Compatible. Task 1 owns schema/enums; Task 2 consumes the exact fields and must keep migration/model names aligned. |
| Task 1 ↔ Task 3 | `TaskApprovalRequest` model and request/status enum names | Compatible. Task 1 is the persistence source; Task 3 must import those exact types and not duplicate enums. |
| Task 1 ↔ Task 5 | `TaskComment` tombstone fields and `WorkspaceChangeLog.resource_type` | Compatible. Task 1 adds columns; Task 5 serializes them and uses resource types `approval_request`/`comment`. |
| Task 2 ↔ Task 3 | `TaskService` owner guard, snapshot fields, task mutation methods | **Ruling:** keep public `TaskService.patch/transition/lifecycle/restore` owner-protected. Approval service executes an approved mutation using the derived `approver_id` as the actor, which is the task owner for task requests or the comment author for comment deletion; no permission-bypass API is added. |
| Task 2 ↔ Task 4 | `tasks/routes.py`, owner/non-owner dispatch and HTTP response types | Compatible. Task 4 checks owner before calling TaskService; non-owner routes create approval requests and return HTTP 202 without mutating the task. |
| Task 2 ↔ Task 5 | `TaskService.snapshot` fields consumed by sync | Compatible. Task 5 must serialize the expanded snapshot without changing existing public status names. |
| Task 2 ↔ Task 6 | Task number/quadrant/progress JSON consumed by Dart `TaskItem` | Compatible. Wire names are `task_number`, `quadrant`, `progress`; existing fields remain backward-compatible. |
| Task 2 ↔ Task 8 | Task number/quadrant/progress JSON consumed by Web `TaskItem` | Compatible. Web uses the same snake_case wire contract. |
| Task 3 ↔ Task 4 | `approval_schemas.py`, service methods and route response unions | Compatible. Task 4 exposes Task 3's typed request/result serialization and maps `approval_required` to 202. |
| Task 3 ↔ Task 5 | Approval lifecycle cursor/audit events and sync serialization | Compatible. Task 3 allocates one cursor per lifecycle mutation; Task 5 publishes resources after commit. |
| Task 3 ↔ Task 6 | Approval request JSON and repository/controller methods | Compatible. Flutter mirrors the server contract and treats 202 as a pending request, never as an applied task. |
| Task 3 ↔ Task 8 | Approval request JSON and Web API/sync/UI | Compatible. Web mirrors the same request/status strings and action endpoints. |
| Task 4 ↔ Task 5 | Router registration and snapshot/current-workspace routes | Compatible. Task 4 adds approval routes; Task 5 extends existing sync responses without changing authentication. |
| Task 4 ↔ Task 6 | HTTP 202 response shape and Flutter repository result union | Compatible. Both use `{approval_request, pending: true}` for non-owner writes. |
| Task 4 ↔ Task 8 | HTTP 202 response shape and Web repository result union | Compatible. Both clients must preserve request IDs and display PENDING state. |
| Task 5 ↔ Task 6 | Snapshot/change resource types and Dart sync application | Compatible. Dart applies `task`, `approval_request`, and `comment` resources by cursor. |
| Task 5 ↔ Task 8 | Snapshot/change resource types and Web sync application | Compatible. Web applies the same three resource types and falls back to snapshot on cursor gaps. |
| Task 6 ↔ Task 7 | Dart models/controller APIs consumed by Android screens | Compatible. Task 7 uses only Task 6's typed controller/repository interfaces. |
| Task 8 ↔ Task 9 | Web build and acceptance smoke checks | Compatible. Task 9 validates the final Vite bundle and public HTTP behavior. |
| Task 1 self-check | Schema tests vs model/migration files | Consistent; empty production DB is the supported reset path and existing rows are populated deterministically if present. |
| Task 2 self-check | Allocator, task fields, owner guard and comment tombstone tests | Consistent; `DONE` is public while `COMPLETED` remains the persisted enum. |
| Task 3 self-check | Approval lifecycle, stale versions, idempotency and actor derivation | Consistent; exactly one other ACTIVE member is the approver. |
| Task 4 self-check | HTTP paths, response status codes and route registration | Consistent; owner writes remain normal task responses and non-owner writes are 202 pending responses. |
| Task 5 self-check | Snapshot/changes resources and cursor allocation | Consistent; resource serialization is workspace-scoped and post-commit hints only. |
| Task 6 self-check | Dart JSON models, repository methods and controller state | Consistent; no speculative local task mutation for pending approvals. |
| Task 7 self-check | Android controls and read-only/device-owner behavior | Consistent; screen delegates all writes to controller and hides progress outside IN_PROGRESS. |
| Task 8 self-check | TypeScript API, sync, detail and approval UI | Consistent; no approver selector and no optimistic task mutation for 202. |
| Task 9 self-check | E2E flow and verification commands | Consistent; Flutter Web integration tests are excluded because the platform does not support them. |

## Rulings

- Ruling: preserve the existing persisted `TaskStatus.COMPLETED` enum and map it to public `DONE` — this avoids destructive enum renames while keeping the documented API contract; cost if wrong: a future migration would need to rename persisted enum values.
- Ruling: use the derived approver as the actor when applying an approved mutation — this lets existing owner-only TaskService methods enforce authorization without a hidden bypass; cost if wrong: audit actor attribution may need a later explicit requester/approver split.

Task 1 dispatch: implementer `/root/task1_persistence`, base `e9291cfd3ff620fe2c356811ac3c4c6592781c9b`.

Task 1: complete (commits e9291cf..e3a8355, review clean; container PostgreSQL schema suite 10 passed, isolation and migration backfill checks passed).
Task 1: minor (deferred): migration assumes any pre-existing non-null task numbers use the `YYMMNNNN` format when advancing sequences; development deployment may reset the database as authorized.
Task 2: complete (commit d5a1f86; focused domain and existing task regression suites passed in the PostgreSQL test container: 14 passed).
Task 2: verification note: allocator uses a PostgreSQL upsert for concurrent first-use month allocation; task progress field version advances when entering `IN_PROGRESS` with the default 20% value.
Task 3: complete (commit 8b6c84b; approval/domain/cloud mutation tests passed serially in the PostgreSQL test container: 25 passed combined).
Task 3: verification note: shared test database must be exercised serially because the legacy extension migration is not process-safe under concurrent schema setup.
Task 4: complete (commit 4c82dcf; focused approval HTTP tests plus existing lightweight/task/read-only route suites passed: 12 passed).
Task 4: implementation note: task and approval routes share the existing verified-device dependency; pending non-owner writes return 202 and never mutate the target task.
Task 5: complete (commit 71826b9; sync approval/comment tests and task/cloud/timeline/HTTP regression suite passed: 16 passed).
Task 5: implementation note: comment create/delete changes use `comment` resources; snapshots retain tombstones and include the authenticated `viewer_user_id` plus approval requests.
Task 5: follow-up security fix (commit ac90b8b): task idempotency is actor-bound, approval action replays verify the active approver/requester first, and task/comment locks use a consistent task-first order.
Task 6: complete (commit 62ee632; focused model/repository/sync tests and the existing models/task/sync suite passed: 22 tests; `flutter analyze` clean).
Task 6: implementation note: HTTP 202 is represented as `PendingApproval`; cursor changes normalize server action enums before applying task, approval and comment resources.
Task 7: complete (commit af58f8a; Android screen suite passed: 18 tests; `flutter analyze` clean).
Task 7: implementation note: task detail delegates all writes to `WorkspaceSyncController`; approval inbox actions are enabled only for verified devices and the derived incoming/outgoing actor.
Task 8: complete (commits cc5b6ed, 848053b; Web suite passed: 10 files, 65 tests; `npm run typecheck` and `npm run build` clean).
Task 8: implementation note: Vite Web mirrors the approval API, preserves HTTP 202 pending writes, applies task/approval/comment cursor resources, and exposes incoming/outgoing approval actions with task number, quadrant, progress and comment tombstones.
Task 9: acceptance implementation complete; final full verification passed (backend 124 passed/3 skipped, focused 40 passed, smoke 1 passed, Flutter 61 passed, Web 65 passed), release artifact build and GitHub Release publication remain the last gates for this run.
Task 9: final verification rerun on 2026-08-31 passed (backend 124 passed/3 skipped, focused 40 passed, two-person smoke 1 passed, Flutter 61 passed, Web 65 passed with typecheck/build); final APK `Muyu-v0.1.2.apk` built from `4180ce8` with SHA-256 `ae119c802e0d40f51b639eb5ac1f084a51d3d2c3f24e231705117128fca51f1e`. GitHub tag/release and Actions remain pending.
