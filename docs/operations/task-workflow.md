# Lightweight Task Workflow

This document describes the task workflow delivered by the current Android and
Web clients. PostgreSQL is the only source of truth for task state, append-only
operations, conflicts, comments, delays, and workspace cursors.

## Scope

- A Workspace has exactly two active members. A task has one
  `current_handler_id`, which is its task负责人; there is no task participant
  or assignee collection.
- Public statuses are `TODO`, `IN_PROGRESS`, `BLOCKED`, `REVIEW`, `DONE`, and
  `CANCELLED`. A `BLOCKED` transition requires a reason and a valid
  `resume_handler_id`; `REVIEW` is accepted or returned by the other member.
- The entry form creates a task only after a title, one required quadrant
  (`Q1`-`Q4`), and exactly one approved workspace classification are selected.
  Description, dates, estimate, and handler changes are edited from the task
  detail view.
- The wire/storage field remains named `labels` for compatibility, but a new
  task may contain exactly one classification. Classification names are
  approved workspace records and are limited to five characters. Empty legacy
  arrays may be read during development migration, but all new create, patch,
  and approval writes reject zero or multiple classifications.
- Deletion is soft deletion (`deleted_at`). Restore creates a new operation;
  comments and delays remain append-only facts.
- Android and Web submit writes only while connected and treat a committed
  server response as success. There is no offline write queue.

## Classification contract

Classifications are workspace-level records, not free-form task labels. Every
Workspace receives the system classification “默认” during bootstrap; it is
immediately selectable and does not create an approval request. For every
other name, a member opens Android “我的 → 分类管理” and submits a
`CLASSIFICATION_CREATE` approval request; the other member must approve it
before the name appears in the selectable list. Names are trimmed, compared
case-insensitively, and limited to five Unicode characters. Duplicate approved
names and duplicate pending requests are rejected.

Every task stores the selected name in the compatibility-shaped field
`labels: ["分类名"]`. The server canonicalizes its display spelling from the
approved workspace record and validates membership on create, direct patch,
and approved patch. A request containing two or more names returns
`422 invalid_request`; clients use a single-choice control and never expose a
multi-select editor.

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

- task title, description, status, handler transfer, restore and delete;
- quadrant changes (`Q1` through `Q4`);
- classification changes (the complete one-value `labels` field); and
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

### Client refresh strategy

The client exposes one refresh model for all task destinations (`清单`,
`四象限`, and `日程`): pull down from the top edge of the list. The lists use
`AlwaysScrollableScrollPhysics`, so the gesture is available even when the
current result set is shorter than the viewport. Refresh is an explicit
authoritative snapshot request; it is not a local cache merge.

The sync controller is the single entry point for both manual refresh and
background synchronization:

- `start()` performs one snapshot, then listens for WebSocket cursor hints.
- A newer hint calls `pull()`, which requests ordered changes after the local
  cursor. A missing/duplicated cursor or an expired change window falls back to
  `refresh()`.
- Concurrent calls to `refresh()` share the same in-flight snapshot request;
  concurrent hint pulls share one changes request. This prevents a swipe, a
  hint, and a post-write reconciliation from racing each other.
- A successful snapshot/change response replaces the local state and cache and
  clears the stale marker. A failed request keeps the last snapshot visible,
  marks it stale, and surfaces the error so the user can pull again.
- Accepted writes still reconcile through `pull()` after the server response;
  the response itself never becomes an alternative source of truth.

There is no periodic timer and no task refresh action in the overflow menu.
This keeps network traffic predictable while still allowing near-real-time
updates from server hints and an immediate user-initiated refresh.

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

Android exposes four bottom destinations after the Workspace is ready:
`清单`, `四象限`, `日程`, and `我的`. The list groups tasks as not started,
in progress, and completed/failed; the quadrant view always has exactly Q1-Q4;
the schedule groups by local due date and puts missing dates under `未安排`;
the profile view shows the account and Android devices. The old Android board
tab is not part of the client.

Android and Web open a detail view with task number, handler, status, quadrant,
classification, dates, and progress metadata. The task负责人 can edit the
quadrant and one approved classification directly. The other member receives
the same two-person approval flow and the task stays unchanged until approval.
Both clients refresh from the server after every accepted write and retain the
user's draft when a write fails.
