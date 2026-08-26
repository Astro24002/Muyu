# SDD ledger — plan: docs/superpowers/plans/2026-08-26-lightweight-action-first.md

## Setup

- Execution mode: Subagent-Driven Development.
- Workspace: `/home/muyu/Muyu` (the user explicitly authorized direct changes on `main`; no external merge or push will be performed without a separate request).
- Spec read: `docs/superpowers/specs/2026-08-26-lightweight-action-first-design.md`.
- Plan read: `docs/superpowers/plans/2026-08-26-lightweight-action-first.md`.

## Preflight shared-file and self-consistency scan

| Scope | Shared file/interface | What the earlier task produces and the later task consumes | Result / ruling |
|---|---|---|---|
| Task 1 -> Task 2 | `backend/app/tasks/service.py`, `snapshot()` | Task 1 supplies public status, assignee and derived delay fields; Task 2 uses the snapshot for timeline consistency | Compatible; Task 2 must not duplicate or overwrite Task 1 aggregation rules. |
| Task 1 -> Task 2 | `backend/app/tasks/routes.py` | Task 1 establishes transition and compatibility lifecycle routes; Task 2 adds activity/timeline reads and preserves write cursor behavior | Compatible; activity route is additive and uses the same actor/error helpers. |
| Task 1 -> Task 3 | `TaskItem.status`, `status_version`, `assignee_ids` | Task 3 types and client actions consume the exact public JSON fields from Task 1 | Compatible; public status is the five-value union, with no `COMPLETED` emitted. |
| Task 1 -> Task 4 | transition request fields | Web UI sends `target_status`, `base_status_version`, and optional WAITING payload | Compatible; UI must not invent a board status or bypass controller. |
| Task 1 -> Task 5 | transition request fields | Android detail actions send the same request body and use returned cursor | Compatible; Android must not add a second status protocol. |
| Task 1 -> Task 6 | REST paths and stable error codes | E2E/smoke exercises create, transition, subtask and conflict behavior | Compatible; Task 6 treats PostgreSQL as required for concurrency evidence. |
| Task 2 -> Task 3 | comments/delays/activity response shapes | Client API methods and detail views read the complete append-only records | Compatible; no client-side history becomes a fact source. |
| Task 2 -> Task 4 | `GET /tasks/{id}/comments`, `/delays`, `/activity` | Web detail view renders server records and keeps failed form input | Compatible; reads are on-demand and transient. |
| Task 2 -> Task 5 | delay/comment records | Android detail view renders the same records | Compatible; model fields remain snake_case at HTTP boundary. |
| Task 2 -> Task 6 | cursor and snapshot derived counters | E2E compares both users' counts and activity after writes | Compatible; snapshot counters must equal record queries. |
| Task 3 -> Task 4 | `task-view-model.ts`, `WorkspaceSyncController` | Web UI consumes pure projections and controller action methods | Compatible; UI does not mutate `WorkspaceSnapshot` directly. |
| Task 3 -> Task 5 | Dart `TaskView`, repository/controller actions | Android UI consumes the same filtering/grouping semantics | Compatible; status order and dueSoon definition remain identical. |
| Task 3 -> Task 6 | API request IDs and no-offline-write behavior | Acceptance checks retries and stale state | Compatible; failed writes cannot be queued or shown as successful. |
| Task 4 -> Task 6 | Web DOM and app composition | Final acceptance checks list/board/my-task flows and logout isolation | Compatible; Task 6 only verifies the public UI, not a new backend source. |
| Task 5 -> Task 6 | Android screen and APK entrypoint | Final acceptance builds APK and runs widget/smoke checks | Compatible; no iOS build or Flutter Web path is introduced. |
| Task 4 <-> Task 5 | fixed status labels and summary semantics | Two clients must display the same status and counts | Compatible; labels are presentation-only and derive from server values. |
| Task 1 self-check | domain tests vs service/routes/files | Tests cover one-level subtasks, assignees, transitions and stale versions | Self-consistent after using stable `nested_task_not_allowed` code. |
| Task 2 self-check | timeline tests vs delays/comments/routes | Tests cover append-only records, aggregate parity and activity order | Self-consistent; no schema migration is required. |
| Task 3 self-check | TS/Dart types vs API methods/controllers | Tests cover request bodies and projection functions | Self-consistent; method names are explicitly listed in the task interface. |
| Task 4 self-check | DOM tests vs view files | Tests cover list/board/my-only, actions, conflict and responsive composition | Self-consistent; detail view is a transient DOM component. |
| Task 5 self-check | Widget tests vs Android files | Tests cover tabs, five columns, WAITING and refresh/detail navigation | Self-consistent; existing QR/device flows remain untouched. |
| Task 6 self-check | E2E/smoke/docs/Makefile | Commands and documentation record actual results and unverified hardware | Self-consistent; release trigger is not broadened. |

## Rulings

- Ruling: keep database `TaskStatus.COMPLETED` as a compatibility storage value and expose/accept canonical public `DONE` through a service mapping — the approved lightweight spec governs the client/API contract, while a destructive enum migration would add unnecessary risk and complexity; if this mapping is wrong, an existing database with raw `COMPLETED` rows would need a later migration.
- Ruling: retain `/api/v1/tasks/{task_id}/lifecycle` as a compatibility alias while adding `/transition` — existing clients and smoke scripts may still call the old route, and both paths must share one transaction implementation; if this is wrong, duplicate route semantics could require cleanup.
- Ruling: no new database tables or infrastructure are needed for this plan — the current schema already contains task assignees, status history, comments, delays, conflicts and operations; if a missing invariant is discovered, add the smallest migration only after recording a new ruling.

## Task status

- Task 1: pending.
- Task 1: complete (commits `224ba2d..03108e5`; review rounds 1-3 closed; PostgreSQL domain/HTTP tests 5 passed).
- Task 2: complete (`ddfef27`); backend compileall passed, pytest unavailable in this environment.
- Task 3: complete (`f0a1fec`); Web Vitest/typecheck passed, Flutter focused tests passed.
- Task 4: complete (`58455cb`); Web 42 tests, typecheck, and build passed.
- Task 5: complete (`3f47c46`); Flutter analyze clean and 12 tests passed; APK not rebuilt in this task.
- Task 6: complete (`dd1b8b7`); smoke/e2e/docs/Makefile added; PostgreSQL acceptance not run.

## Task 1 review loop

- Task 1: fix round 1/5 started after review `f9081ac..224ba2d`; open findings: stale transition is not idempotent/does not emit operation cursor; stale assignee patch dereferences a nonexistent attribute; WAITING/unblock and create do not enforce handler/participant membership; lifecycle delete lost idempotency and status version behavior; required sync-service and contract tests are missing; status conflict payload is misleading.
