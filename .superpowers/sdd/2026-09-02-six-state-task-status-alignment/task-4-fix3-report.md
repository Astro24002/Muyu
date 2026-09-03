# Task 4 Fix 3 Report

## Delivered

- Persisted conflict creation outcomes in task operations and reconstructs the original `409 field_conflict` response, including conflict details, current snapshots, and cursor, on cross-session request replay. Direct task-operation replay is selected before approval routing, including after a proposed handler transfer changes the current owner.
- Added status-conflict proposed resolution through the same transition path as normal status writes. BLOCKED and REVIEW return metadata, status/lifecycle versions, handler history, status history, activity payloads, operation IDs, and workspace cursors are updated exactly once.
- Hardened Flutter and Web change-envelope validation for workspace identity, canonical actions, exact contiguous cursors, envelope/last-row agreement, empty responses, resource IDs, and conflict/task workspace ownership. Invalid envelopes and malformed 409 projections recover from a snapshot without caching an advanced cursor.
- Unified action-first `task_conflict` handling: `DELETED` or null resources remove the conflict; only valid open projections are applied; resolved projections do not re-create conflicts. 409 projections merge into client snapshots and caches, then pull the committed cursor.
- Added HTTP, backend invariant, Web, and Flutter regressions for replay, proposed status resolution, handler-transfer replay, workspace boundaries, tombstones, malformed envelopes, cursor contiguity, exact-once activity/history/operation behavior, and cache convergence.

## Verification

- Backend Docker PostgreSQL focus: `33 passed, 1 deselected, 1 warning`.
- Web sync focus: `48 passed`; full Web suite: `224 passed` across 30 files; `npm run typecheck` passed.
- Flutter sync focus: `20 passed`; `flutter analyze` reported no issues.
- `git diff --check` passed for the repair changes.

The one deselected backend test is the existing legacy direct `TODO -> DONE` contract test; the six-state transition table intentionally requires the review path. No unrelated dirty files were reverted or staged.
