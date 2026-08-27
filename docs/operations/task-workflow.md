# Lightweight Task Workflow

This document describes the task workflow delivered by the current Android and
Web clients. PostgreSQL is the only source of truth for task state, append-only
operations, conflicts, comments, delays, and workspace cursors.

## Scope

- A Workspace has one or two active members. A task has one or two active
  assignees, and its current handler must be one of them.
- Public statuses are `TODO`, `IN_PROGRESS`, `WAITING`, `DONE`, and
  `CANCELLED`. A `WAITING` transition requires both `blocked_reason` and a
  valid `resume_handler_id`.
- The entry form creates a title-only task. Description, dates, estimate,
  assignees, and handler changes are edited from the task detail view.
- Deletion is soft deletion (`deleted_at`). Restore creates a new operation;
  comments and delays remain append-only facts.
- Android and Web submit writes only while connected and treat a committed
  server response as success. There is no offline write queue.

## Write and conflict rules

Every write sends a UUID `request_id`. Retrying the same request with the same
payload returns the original result and does not create a second operation or
cursor. A field edit sends the current `base_field_versions` for each changed
field. A stale field returns `409` with a conflict record containing the base,
current, and proposed values. The user can keep the current value or accept the
proposed value; resolution itself is versioned and allocates a cursor.

Status actions use `base_status_version`; deletion and restore use
`base_lifecycle_version`. Invalid transitions, edits to a deleted task, and
stale lifecycle/status versions are rejected without claiming success.

## Synchronization

1. The client reads `/api/v1/workspaces/current/snapshot` to establish the
   complete task set and authoritative cursor.
2. It reads `/api/v1/workspaces/current/changes?after_cursor=<cursor>` to catch
   up. Responses are ordered by cursor and include the current task resource.
3. A WebSocket message is only a newer-cursor hint. REST snapshot/change
   responses remain the correctness path.

The same contract is used by Android and Web. Web has no browser-local identity
or password login; QR authorization is the only Web login path.

## Acceptance command

The repeatable two-user acceptance uses a fresh schema in a disposable
PostgreSQL instance. Set `TEST_DATABASE_URL` to that disposable connection
string and run:

```sh
RUN_CLOUD_PROTOCOL=1 \
  TEST_DATABASE_URL="$TEST_DATABASE_URL" \
  python -m pytest -q tests/e2e/test_cloud_protocol.py \
  -k two_user_task_workflow_postgresql
```

The test authenticates two users, creates a Workspace, provisions the second
active membership in the disposable database, and verifies task creation,
cross-user snapshot/cursor visibility, a concurrent field conflict and
resolution, status transitions, a comment, a delay, soft deletion, and
restore. It never targets the production database or inserts production data.

## Client workflow

Android exposes task creation after the Workspace is ready and opens a detail
screen for editing and lifecycle actions. Web exposes the same actions in its
Vite SPA after QR login. Both clients refresh from the server after every
accepted write and retain the user's draft when a write fails.
