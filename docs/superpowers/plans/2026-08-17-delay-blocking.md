# Phase 3 Delay And Blocking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add immutable task delay history and a complete WAITING/block/unblock workflow to the FastAPI and Flutter task experience.

**Architecture:** Extend the existing `task` domain rather than adding a parallel subsystem. A new `DelayRecord` model and repository queries provide immutable delay facts and aggregates; `TaskService` remains the single transaction boundary for task, history, and activity writes. Flutter extends the current repository/controller and delegates action forms to focused dialog widgets.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2.0, Alembic, PostgreSQL/SQLite, pytest, Flutter 3.47/Dart 3.13.

**Spec:** `docs/superpowers/specs/2026-08-17-delay-blocking-design.md`

## Global Constraints

- Delay reasons are `NO_TIME`, `TOO_LARGE`, `NOT_WILLING`, `FORGOT`, `WAITING_PARTNER`, `INTERRUPTED`, and `OTHER`.
- `OTHER` requires a nonblank note; every delay requires an existing due date and a new due date at least one minute later.
- Delay records are append-only and are never updated or deleted through application code.
- Blocking is allowed only from `TODO` or `IN_PROGRESS`; unblocking is allowed only from `WAITING` and restores `IN_PROGRESS`.
- A resume handler must be a task assignee. An optional waiting user must be one of the two fixed users.
- All absolute timestamps are stored in UTC and rendered in the client local timezone.
- Every write atomically updates task state/version and appends the required history and activity event.
- Phase 4 conflicts and Phase 7 home/timeline behavior remain out of scope.

---

### Task 1: Delay Schema, Model, And Repository Queries

**Files:**
- Create: `backend/alembic/versions/0003_delay_blocking.py`
- Modify: `backend/app/task/models.py`
- Modify: `backend/app/task/repository.py`
- Modify: `backend/tests/conftest.py`
- Modify: `backend/tests/db/test_migrations.py`
- Modify: `backend/tests/task/test_service.py`

**Interfaces:**
- Produces `DelayRecord` with all fields from the Phase 3 spec.
- Produces `TaskRepository.list_delays(task_id)`, `delay_count(task_id)`, and `total_delay_minutes(task_id)`.

- [x] **Step 1: Write failing migration/model tests** for the `delay_records` columns, foreign keys, index, UTC timestamps, and test cleanup order.
- [x] **Step 2: Run focused migration tests and confirm failure is caused by the missing table/model.**
- [x] **Step 3: Add migration `0003_delay_blocking`, the ORM model, relationship, and repository read/aggregate methods.**
- [x] **Step 4: Run focused and complete backend tests.**
- [x] **Step 5: Commit with `feat: add task delay records`.**

### Task 2: Delay And Blocking Domain Rules

**Files:**
- Modify: `backend/app/task/service.py`
- Modify: `backend/tests/task/test_service.py`

**Interfaces:**
- Produces `DelayCreate(new_due_at, reason, note)`.
- Produces `TaskService.delay`, `list_delays`, `delay_summary`, `block`, and `unblock`.
- Existing `complete` and `cancel` accept `WAITING` and clear stale blocking metadata.

- [ ] **Step 1: Write failing delay tests** for three records, original/new due dates, aggregate minutes, immutable history, fixed reasons, `OTHER`, missing due date, and invalid time.
- [ ] **Step 2: Implement delay validation and one-transaction record/task/activity updates.**
- [ ] **Step 3: Write failing blocking tests** for required reason, assignee resume handler, fixed waiting user, valid transitions, automatic handler restore, histories, event payloads, and clearing fields on complete/cancel.
- [ ] **Step 4: Implement block/unblock and integrate WAITING cleanup into status changes.**
- [ ] **Step 5: Run task tests and the complete backend suite, then commit with `feat: implement task delay and blocking workflow`.**

### Task 3: Authenticated Delay And Blocking HTTP API

**Files:**
- Modify: `backend/app/task/routes.py`
- Modify: `backend/tests/httpapi/test_task_routes.py`

**Interfaces:**
- Adds `DelayRequest`, `BlockRequest`, and `DelayRecordResponse`.
- Adds `POST /api/tasks/{task_id}/delay`, `GET /api/tasks/{task_id}/delays`, `POST /api/tasks/{task_id}/block`, and `POST /api/tasks/{task_id}/unblock`.
- Extends `TaskResponse` with blocking fields, `delay_count`, and `total_delay_minutes`.

- [ ] **Step 1: Write failing authenticated HTTP tests** for delay/list/aggregates, block/unblock, both-user consistency, unauthorized access, validation, and stable business error codes.
- [ ] **Step 2: Run focused tests and confirm route/response contract failures.**
- [ ] **Step 3: Implement typed request/response models and route-to-domain error mapping.**
- [ ] **Step 4: Run focused and complete backend tests.**
- [ ] **Step 5: Commit with `feat: expose delay and blocking API`.**

### Task 4: Flutter Delay And Blocking Data Layer

**Files:**
- Modify: `client/lib/models/task.dart`
- Modify: `client/lib/task/task_repository.dart`
- Modify: `client/lib/task/task_controller.dart`
- Modify: `client/test/models/task_test.dart`
- Modify: `client/test/task/task_repository_test.dart`
- Modify: `client/test/task/task_controller_test.dart`
- Modify: `client/test/support/fake_task_repository.dart`

**Interfaces:**
- Extends `TaskItem` with blocking fields and delay aggregates.
- Produces immutable `TaskDelayRecord` and the delay reason label map.
- Extends `TaskRepository`/`HttpTaskRepository` with `delay`, `delays`, `block`, and `unblock`.
- Extends `TaskController` with matching actions that retain API errors.

- [ ] **Step 1: Write failing model/repository tests** for Phase 3 task JSON, delay records, request bodies, routes, and error mapping.
- [ ] **Step 2: Implement models and repository methods, then run focused tests.**
- [ ] **Step 3: Write failing controller tests** for delay, block, unblock, task replacement, and retained errors.
- [ ] **Step 4: Implement controller and fake repository support.**
- [ ] **Step 5: Run Dart formatting, Flutter analyze, and all client tests; commit with `feat: add Flutter delay and blocking data layer`.**

### Task 5: Flutter Task Detail Actions And History

**Files:**
- Create: `client/lib/screens/task_action_dialogs.dart`
- Modify: `client/lib/screens/task_detail_screen.dart`
- Modify: `client/lib/screens/task_list_screen.dart`
- Modify: `client/test/widget/task_workspace_test.dart`

**Interfaces:**
- Produces `showTaskDelayDialog` and `showTaskBlockDialog` with typed results.
- Task detail owns loading and rendering immutable delay history.

- [ ] **Step 1: Write failing widget tests** for WAITING labels/details, conditional actions, block validation, `OTHER` note validation, delay submission, unblock, history rendering, and input retention after API failure.
- [ ] **Step 2: Implement focused action dialogs using Material date/time, dropdown, text, and user controls.**
- [ ] **Step 3: Integrate task detail actions, blocking metadata, delay aggregates/history, and WAITING list styling.**
- [ ] **Step 4: Run focused widget tests, all client tests, analyze, and format.**
- [ ] **Step 5: Build Web and Android debug artifacts and commit with `feat: add task delay and blocking experience`.**

### Task 6: PostgreSQL Acceptance And Progress Documentation

**Files:**
- Create: `scripts/smoke-delay-blocking.sh`
- Modify: `Makefile`
- Modify: `docs/05-development-status.md`
- Modify: `docs/README.md`
- Modify: `docs/superpowers/plans/2026-08-17-delay-blocking.md`

**Interfaces:**
- `make smoke-delay-blocking` verifies the Phase 3 two-user workflow without printing passwords or tokens.

- [ ] **Step 1: Write the smoke script** covering create-with-due-date, three delays, aggregate/history checks, block, second-user read, unblock/handler restore, event sequence, and temporary credential cleanup.
- [ ] **Step 2: Run `make test`, shell syntax, Compose config, and diff checks.**
- [ ] **Step 3: Run a clean isolated PostgreSQL Compose project and `make smoke-delay-blocking`.**
- [ ] **Step 4: Restart the API and verify migration `0003_delay_blocking`, delay rows, task state, and events persist without duplication.**
- [ ] **Step 5: Upgrade the user-facing API/Web processes without resetting fixed-user data and run desktop/mobile visual checks.**
- [ ] **Step 6: Record exact evidence in the development status and commit with `feat: complete phase 3 delay and blocking`.**
