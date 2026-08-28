# Task 3 Report

## Files changed

- `backend/app/tasks/approvals.py`: added the unified two-person approval service, typed result, stable approval errors, member-derived approvers, request/list lifecycle, owner-authorized application, stale conflict/cancellation handling, and activity/operation/cursor emission.
- `backend/app/tasks/approval_schemas.py`: added strict Pydantic create/action/read/result contracts and compatibility aliases for the later HTTP slice.
- `backend/tests/tasks/test_task_approvals.py`: added PostgreSQL integration coverage for request creation, two-member derivation, setup/workspace/permission rejection, idempotency, listing, approval/rejection/cancellation, stale handling, comment deletion, specialized task actions, audit cursors, and one-time application.

## RED

Command (exact brief command):

```text
docker run --rm --network container:muyu-task1-postgres -v /home/muyu/Muyu/backend:/src -w /src -e TEST_DATABASE_URL='postgresql+psycopg://muyu:muyu-task1-password@127.0.0.1:5432/muyu_task1' muyu-backend-test-deps:local python -m pytest tests/tasks/test_task_approvals.py -q
```

Output:

```text
ModuleNotFoundError: No module named 'app.tasks.approval_schemas'
```

The failure occurred during test collection before the service and schemas existed.

## GREEN

Focused approval suite:

```text
16 passed in 7.87s
```

Focused approval plus existing task suites:

```text
25 passed in 12.59s
```

The first combined attempt encountered the test environment's concurrent `pg_trgm` extension migration race while another schema migration was active. The approval suite and the combined suite both passed when rerun serially; compilation and `git diff --check` also passed.

## Design checks

- Approvers are derived from the only other ACTIVE workspace member; no approver selector, role, group, or voting path exists.
- Approved task mutations call the existing owner-guarded `TaskService` with the approval UUID as the applied request key. Comment deletion uses the comment author as the owner-authorized actor.
- Base versions and proposed changes are normalized and copied at request creation. Replays return the original request/cursor, while changed payloads use `approval_request_reused`.
- Pending stale field/version requests become `CONFLICTED`; deleted/restored/handler-changed requests are cancelled with a reason. Rejection and requester cancellation do not mutate target data.
- Persisted `TaskStatus.COMPLETED` and public `DONE` mapping remain unchanged. No HTTP routes or client code were edited.

Commit: `feat: add unified two-person task approvals`
