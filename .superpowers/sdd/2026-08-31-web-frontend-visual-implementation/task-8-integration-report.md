# Task 8 Integration Report

Date: 2026-09-01

## Scope

Connected the activity and Web session React slices to the existing App shell. Activity is now a route-local surface; session controls flow through AppShell and TopNav into UserMenu, with 401 errors routed to the existing QR-login recovery lifecycle.

## Integration changes

- Added `activity` to the React workbench route set and render `ActivityPage` only for `#/activity`.
- Passed a stable `getTaskActivity` callback and workspace key to the lazy activity page; Today, All Tasks, Approvals, and task detail routes do not fan out activity requests.
- Passed the existing `WebSessionViewApi` contract and `recoverAuthRequired` callback through `AppShell` and `TopNav` into `UserMenu`.
- Added scoped activity and session styles to `global.css`, preserving the explicit legacy-root exclusions used by the rest of the React foundation.
- Added App integration coverage for lazy activity loading, task-title rendering, legacy-root isolation, and session-list 401 recovery.

## Verification

- `npm test -- --run test/activity-view-model.test.ts test/activity-page.test.tsx test/web-session-panel.test.tsx test/web-session-view.test.ts test/app-session-isolation.test.ts test/task-8-integration.test.tsx test/top-nav.test.tsx`: 34/34 passed.
- Additional `app-shell` compatibility run: 26/26 passed.
- `npm run typecheck`: passed.
- `npm run build`: passed; Vite transformed 1,651 modules.
- `git diff --check`: passed.

## Residual risk

- Full Web tests and browser-level visual/accessibility checks remain for Tasks 9-10.
- The legacy WebSessionView and old activity handling remain in place until Task 10; the React entry is isolated by route and scoped styles.
