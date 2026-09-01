# Task 6 Report: Today and All Tasks Pages

Date: 2026-09-01
Scope: React Today and All Tasks workbench pages, local task filters, task composer, inline approval notice, and route-specific App integration.

## Implementation

- Added `TodayPage` with the required top-to-bottom sequence: title/date/copy, low-weight sync status, optional focus task, next tasks, waiting tasks, inline approval notice, and quick record composer. The page omits the focus section when there is no eligible focus task and gives an empty workspace one direct explanation/action path. It does not render KPI content, dashboard cards, a board, or a sidebar.
- Added `AllTasksPage` as a linear `TaskList` view with locally owned status, quadrant, label, and only-my-tasks filters. Filtering creates a derived array and leaves the snapshot task array untouched. Both pages reuse `TaskRow` and guard completion with `sync.transitionTask(task.id, 'DONE')`.
- Added `TaskComposer` with a collapsed `记下一件事` entry and ordered expanded fields for title, next-step description, quadrant, labels, and one primary submit action. Title/quadrant validation is local; labels use `parseTaskLabelsInput`; writes go through the supplied create hook or the existing `sync.createTask` fallback. Draft fields remain visible after rejected requests or handled sync errors and clear only after a successful call.
- Added `TaskFilters` and `InlineApprovalNotice`. The notice exposes the count, natural-language explanation, and `去处理` navigation without introducing a dashboard card.
- Updated `App` so `today` and `tasks` routes render the React pages inside `AppShell`. App binds page creation to `sync.createTask`, task opening to the existing hash task route placeholder, and the shell New Task action to the current composer trigger. The legacy `WorkspaceView` bridge remains for routes outside this Task 6 surface; Task 7 detail and approval pages were not added.
- Added token-based, legacy-bridge-safe styles for both pages and the new task/approval controls. The styling keeps the 960px content frame, linear rows, stable spacing, light palette, and responsive narrowing without nested interactive elements.

## TDD and Verification

The three new test files were written before the Task 6 production modules existed. The first run failed at the expected unresolved-import boundary for `TodayPage`, `AllTasksPage`, and `TaskComposer`. After implementation and test-harness corrections, the requested focused run passed:

```text
npm test -- --run test/today-page.test.tsx test/all-tasks-page.test.tsx test/task-composer.test.tsx
3 test files passed, 10 tests passed
```

The bounded typecheck passed:

```text
npm run typecheck
passed (tsc --noEmit)
```

The scoped visual foundation regression also passed:

```text
npm test -- --run test/visual-foundation.test.ts
1 test file passed, 6 tests passed
```

The full suite was not rerun after this task because verification was intentionally kept bounded. Earlier workspace runs recorded two baseline failures in `test/workspace-actions.test.ts`; those legacy failures were not changed by Task 6.

## Residual Risk

- Browser-level Playwright screenshots and full route lifecycle coverage remain for the later visual acceptance work.
- The task route still uses the existing compatibility/placeholder path until Task 7 supplies React task detail and approval surfaces.
- The composer treats a successful existing sync-controller call as the ACK boundary; the controller remains the sole owner of API errors, reconciliation, and authoritative workspace state.

## Files

- `web/src/app/App.tsx`
- `web/src/pages/TodayPage.tsx`
- `web/src/pages/AllTasksPage.tsx`
- `web/src/components/tasks/TaskComposer.tsx`
- `web/src/components/tasks/TaskFilters.tsx`
- `web/src/components/approvals/InlineApprovalNotice.tsx`
- `web/src/styles/global.css`
- `web/test/today-page.test.tsx`
- `web/test/all-tasks-page.test.tsx`
- `web/test/task-composer.test.tsx`

## Fix Round 1

- Passed `disabled={busy}` from `AllTasksPage` to `TaskFilters`, so loading, stale, and auth-required sync states disable all filter controls.
- Added a focused regression that updates the fake sync through each unavailable state and asserts the status, quadrant, label, and ownership controls are disabled.
- Verification: `npm test -- --run test/all-tasks-page.test.tsx` passed (1 file, 3 tests); `npm run typecheck` passed.
