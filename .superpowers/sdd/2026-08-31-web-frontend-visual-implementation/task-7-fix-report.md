# Task 7 Fix Report

Date: 2026-09-01
Round: 1/5
Base: `814fd74`

## Findings

- Activity failures needed an explicit state boundary. Loading, a real empty response, permission failures (`401`/`403`), a missing resource (`404`), and recoverable service/network failures must not collapse into the same empty timeline.
- Activity requests needed both effect cleanup and a request sequence guard so an older task response cannot replace the current task's activity.
- Task edit dirty state needed to clear only after an applied write result with the current task `id` and a finite `cursor`. Pending approvals, rejected writes, and controller-caught `undefined` results must retain the draft.
- The save path also needed to preserve a field edited again while the original save was still pending. Clearing a field by name alone could erase that newer edit.
- The first new activity and approval assertions used ambiguous Testing Library queries: global sync status competed with the activity status, and two pending approval rows shared the same status label.

## Changes

- Kept the App activity request state explicit with loading, success, and error rendering; permission errors are non-retryable, while `404` and service/network failures expose retry.
- Preserved App activity request cleanup and sequence fencing across task changes and retries.
- Updated `TaskEditForm` to use the `AppliedTaskWriteResult` runtime shape (`id` plus finite `cursor`) and to clear only fields dirty at submission time whose values were not edited again before the applied result arrived.
- Applied the same applied/pending/unconfirmed handling to status transitions, including status, blocked reason, and resume handler draft fields.
- Added and corrected regression coverage for activity states, retries, request races, approval failure preservation, Escape/focus restoration, non-writable controls and conflicts, applied/pending/undefined saves and transitions, and edits made while a save is pending.

## Verification

- `npm test -- --run test/task-activity.test.tsx test/task-detail-panel.test.tsx test/approvals-page.test.tsx test/task-7-integration.test.tsx test/today-page.test.tsx test/all-tasks-page.test.tsx test/approval-view.test.ts test/task-detail-view.test.ts`: **8 files / 47 tests passed**
- `npm run typecheck`: **passed**
- `npm run build`: **passed**
- `git diff --check`: **passed**

## Residual risk

- The full Web test suite and browser-level visual/accessibility checks were not run in this fix round.
- Activity error rendering is covered with mocked API outcomes; real backend permission and network behavior remains an integration concern.
- Comment/delay controls still use their existing `Promise<void>` action contracts, so their success semantics remain owned by the sync controller and are outside this dirty-state fix.
