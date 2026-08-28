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

## Two-person approvals

Each Workspace is limited to exactly two active members. A task's
`current_handler_id` is its负责人 and is the only member who can apply a
direct task mutation. The other member may still submit a change, but the API
returns `202` with an `approval_request` and leaves the task unchanged. The
request is automatically addressed to the current handler; there is no
administrator, group, or multi-person voting path.

The same rule applies to the fields that need explicit agreement:

- task title, description, status, assignee/handler, restore and delete;
- quadrant changes (`Q1` through `Q4`); and
- deleting a comment written by the other member.

The request lifecycle is:

`PENDING` -> `APPROVED`, `REJECTED`, `CONFLICTED`, or `CANCELLED`.

Only the derived approver can approve or reject an incoming request. Only the
requester can cancel an outgoing pending request. Approval rechecks the
captured field/status/lifecycle versions in one transaction; if the task has
changed, the request becomes `CONFLICTED` and does not overwrite newer data.
Changing the task handler also cancels pending requests that targeted the old
owner. Repeating an action with the same request ID is idempotent and cannot
create another operation or cursor.

Comments are append-only facts with soft-delete tombstones. A comment author
can delete their own comment directly. The task负责人 can request deletion of
the other member's comment, and that request must be approved by the comment
author. Tombstones remain in snapshots and incremental changes so both clients
render the same history.

Android shows incoming requests in the approval inbox and outgoing requests in
the requests list. Web shows the same two boxes after QR authorization. Both
clients display pending changes as awaiting approval and never optimistically
rewrite the task. Unverified devices remain read-only and cannot create,
approve, reject, or cancel a request.

## Synchronization

1. The client reads `/api/v1/workspaces/current/snapshot` to establish the
   complete task set and authoritative cursor.
2. It reads `/api/v1/workspaces/current/changes?after_cursor=<cursor>` to catch
   up. Responses are ordered by cursor and include the current task resource.
3. A WebSocket message is only a newer-cursor hint. REST snapshot/change
   responses remain the correctness path.

The same contract is used by Android and Web. Web has no browser-local identity
or password login; QR authorization is the only Web login path.

## Two-user acceptance

Run the focused acceptance against a disposable PostgreSQL database (never the
production database):

```sh
TEST_DATABASE_URL="$TEST_DATABASE_URL" make test-task-approval
TEST_DATABASE_URL="$TEST_DATABASE_URL" make smoke-task-approval
```

The acceptance creates a task, submits and approves a partner edit, adds a
comment, approves its cross-author soft deletion, verifies a stale request is
conflicted, and verifies a handler transfer cancels old pending requests. The
smoke output contains only `task_number`, `request_id`, `approval_status`, and
`final_cursor`; it never prints access tokens, OTP values, or device key data.

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
