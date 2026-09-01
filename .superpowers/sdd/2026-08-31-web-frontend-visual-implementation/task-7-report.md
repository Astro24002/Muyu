# Task 7 Report: Approvals and Task Detail Surfaces

Date: 2026-09-01

## Scope

Task 7 integrates the parallel approvals and task-detail/conflict React slices into the existing web shell. The integration keeps the Task 8 ActivityPage/session migration deferred and leaves the legacy DOM implementation files in place.

## Parallel slices integrated

- Approvals slice: `ApprovalsPage`, `ApprovalRequestRow`, approvals page tests, incoming/outgoing approval grouping, approve/reject/cancel actions, rejection-reason preservation, and pending-count presentation.
- Task detail/conflict slice: `TaskDetailPanel`, `TaskEditForm`, `TaskTimeline`, `ConflictPanel`, detail/conflict tests, comments, delay, transition, edit, conflict resolution, and approval details.
- Integration slice: App route selection, list-background preservation, task open/close navigation and focus restoration, sync action adapters, activity loading, shared type alignment, scoped global styles, and the route integration test.

## Integration changes

`web/src/app/App.tsx` now uses the React workbench for `approvals` and `task` routes in addition to Today and All Tasks. The approvals route renders `ApprovalsPage` with the existing `WorkspaceSyncController`. The task route keeps the originating Today/All Tasks page mounted underneath `TaskDetailPanel`, selects the task from the current sync snapshot, and wires the panel to the existing transition, patch, comment, delay, delete-comment, and conflict-resolution contracts.

Task opening records the originating list route and the focused task control. Closing returns to that list route and restores focus when the source control is still connected or can be found by task-row identity. Missing task ids show an inline error without changing legacy Activity handling. Legacy rendering remains active for Activity and all other routes, and the legacy root is not mounted for the React approvals/task routes.

The existing `GET /api/v1/tasks/:id/activity` endpoint is used for the timeline. `ActivityEvent` was added to `api/types.ts`, the client return type was narrowed to that shared type, and `TaskTimeline` now consumes the shared definition. No backend route or API behavior was added.

Approval and detail styles were added to `global.css` under the existing React-root scope. Legacy `styles.css` and legacy DOM files were not changed, preserving style isolation between the two rendering systems.

## Verification

All commands below were run from `web/`, where the frontend `package.json` lives.

- `npm test -- --run test/task-7-integration.test.tsx`: **passed**, 1 file / 3 tests.
- `npm test -- --run test/approvals-page.test.tsx test/task-detail-panel.test.tsx test/conflict-panel.test.tsx test/today-page.test.tsx test/all-tasks-page.test.tsx test/approval-view.test.ts test/task-detail-view.test.ts`: **passed**, 7 files / 26 tests.
- `npm run typecheck`: **passed**.
- `npm run build`: **passed**; Vite transformed 1,647 modules and emitted the production bundle.
- `git diff --check`: **passed**.

The integration test was first run against the pre-integration App and failed on all three route assertions, confirming the test exercised the missing route wiring. It passed after the App integration was applied. The requested bounded suite had no observed baseline failures. The repository-wide test suite was not run, so unrelated failures outside this scope remain unclassified.

## Residual risk

- Activity request failures are intentionally fail-soft because the current panel contract has no activity-error surface; the task detail still renders with an empty timeline.
- This verification covers the requested focused tests and production build, not browser-level visual inspection or the full repository test suite.
- Task deletion and other legacy Activity/session migration behavior remain outside Task 7 and are intentionally deferred to Task 8.
