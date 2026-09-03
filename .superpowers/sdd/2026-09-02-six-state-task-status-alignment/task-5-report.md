# Task 5 Implementation Report

## Home Contract

- Added authenticated `GET /api/v1/home`.
- The response contains independent `current_tasks`, `blocked_tasks`, and
  `review_tasks` sections. Each section has `items` and `has_more`, plus a
  top-level incoming `pending_approval_count`.
- Task lists are limited on the server and serialized through
  `TaskService.snapshot`. They exclude deleted and foreign-workspace rows.
- Current tasks are limited to the actor's `TODO` and `IN_PROGRESS` tasks;
  blocked tasks to the actor's `BLOCKED` tasks; review tasks to the actor's
  `REVIEW` assignments. Incoming pending approvals are counted by approver.

## Web Flow

- Added `HomeResponse` types and `ApiClient.getHome()`.
- Snapshot loading reads the optional home endpoint when available. Older fake
  sync APIs remain compatible, and an unavailable or invalid home response
  falls back to the cached snapshot without surfacing partner ordinary tasks.
- `deriveTodayModel` uses a supplied home projection as authoritative. Its
  cache fallback enforces handler ownership for current/blocked items and
  reviewer identity for review items.
- The existing Today page presentation remains unchanged; it only receives
  the authoritative projection and uses its approval count.

## Judgement Calls

- Chose nested task sections (`{ items, has_more }`) so pagination state stays
  adjacent to the matching list rather than relying on positional metadata.
- Cleared a cached home projection after task or approval mutations so stale
  server selections cannot be rendered; the role-scoped cached fallback is
  used until a fresh snapshot/home load.

## Verification

- Focused backend HTTP tests: `5 passed`.
- Focused Web Vitest tests: `68 passed`.
- Web TypeScript typecheck: passed.
