# Task 5 Report: 任务模型派生和可复用任务行

## Scope

Task 5 adds the pure `TodayModel` projection and the reusable task workbench primitives. Page composition, routing, task detail behavior, API changes, and the old UI migration remain outside this task.

## Implementation

### Today model

`deriveTodayModel(tasks, approvals, viewerId, now)` now returns `focus`, `next`, `waiting`, and `pendingApprovals` without mutating either input array.

- Deleted tasks are excluded from every task group.
- A viewer task is one whose `current_handler_id` matches the viewer or whose `assignee_ids` contains the viewer, matching the existing `filterMyTasks` contract.
- `focus` is the latest `IN_PROGRESS` viewer task by parsed `updated_at`; malformed timestamps sort last, and equal timestamps use ascending task IDs.
- `next` excludes the selected focus, `WAITING`, `DONE`, and `CANCELLED` tasks; due dates sort ascending, missing or malformed dates sort last, equal dates use ascending IDs, and the result is capped at eight tasks.
- `waiting` preserves all live `WAITING` tasks in source order.
- `pendingApprovals` contains only `PENDING` requests where `approver_id` matches `viewerId`.
- `now` is part of the deterministic selector contract for date-aware callers; the current grouping rules do not need relative-time filtering.

### React primitives

- `TaskRow` exposes `data-task-row`, an accessible keyboard/click row, complete action isolation via `stopPropagation`, disabled busy/terminal completion, readable metadata/date/status text, and full title text.
- `TaskList` renders stable linear rows or the supplied empty message.
- `FocusTask` exposes one highlighted focus region with the pale-green surface, `4px` brand accent, task details, and the exact primary action text `继续处理`.
- `TaskStatusLabel` maps wire statuses to readable Chinese labels while preserving the raw status in `data-task-status`.
- `TaskMeta` renders handler, quadrant, labels, progress, due date, due state, and waiting reason. Dates use a deterministic UTC `YYYY-MM-DD` presentation.
- Scoped styles use the existing visual tokens. Ordinary rows have a `56px` minimum height, bottom dividers, no card border/shadow, and wrapping title text. Responsive rules preserve the linear layout at narrow widths.

## TDD Evidence

Tests were written before the production implementation. The initial run failed because `deriveTodayModel` and the five task components did not exist. After implementation and correction of two fixture expectations, the focused suite passed:

```text
test/today-view-model.test.ts  6 tests passed
test/task-row.test.tsx         8 tests passed
Total                          14 tests passed
```

## Verification

- `cd web && npm test -- --run test/today-view-model.test.ts test/task-row.test.tsx` passed: 14/14.
- `cd web && npm run typecheck` passed.
- `cd web && npm run build` passed.
- `cd web && npm test -- --run` passed 146/148 tests. The remaining two failures are the known baseline failures in `test/workspace-actions.test.ts`:
  - `creates a task from the workspace form and clears the draft after the ACK`
  - `keeps create disabled while a sync loading rerender is in flight`
- `git diff --check` passed.

## Residual Risk

Task primitives are intentionally not connected to a page until Task 6, so browser-level page screenshots and complete-action integration are not part of this change. Relative due-state labels in the components read the component render time; the pure today selector remains independent of the clock and receives `now` explicitly.
