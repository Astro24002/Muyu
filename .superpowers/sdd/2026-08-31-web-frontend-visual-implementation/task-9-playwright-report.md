# Task 9 Playwright Slice Report

## Scope

- Added `web/playwright.config.ts` with deterministic desktop and mobile projects.
- Added `web/e2e/fixtures.ts` with in-browser API fixtures for QR login, workspace snapshot, tasks, approvals, activity, conflicts, comments, and Web sessions.
- Added `web/e2e/visual.spec.ts` covering migrated workbench workflows and responsive contracts.
- Scoped Vitest discovery in `web/vite.config.ts` to the project `test/` tree so Playwright specs are not executed by Vitest.
- Kept all credentials, cookies, browser proof values, and session tokens out of the fixture data and assertions.

## Verification coverage

- QR login page and canvas rendering.
- Today page with and without a focus task.
- All Tasks status filtering and linear list layout.
- Incoming/outgoing approvals and pending count.
- Workspace activity aggregation.
- Task detail drawer/bottom sheet, conflict actions, and activity.
- Migrated route accessibility smoke checks, UserMenu dialog semantics, Escape, and focus restoration.
- No horizontal overflow, legacy root, `.task-board`, or fixed dark sidebar on migrated routes.
- `<1024px` detail panel uses bottom-sheet mode; `<640px` detail fields and inline form stack.

## TDD/debug evidence

1. The initial browser run rendered a blank page because the API route glob also intercepted `/src/api/client.ts`.
2. The fixture route was narrowed from `**/api/**` to `**/api/v1/**` so source modules are never treated as API responses.
3. The next run exposed only strict locator assumptions; selectors were tightened to exact semantic names and native tab-index behavior.
4. The final run passed all configured projects.

## Final verification

- `npm run typecheck`: passed.
- `npm test -- --run --reporter=dot`: 214/221 tests passed; the seven failures are the documented legacy `app-lifecycle` logout assertions and `workspace-actions` old DOM assertions. No Playwright suite is included in this Vitest run.
- `npx playwright test e2e/visual.spec.ts --project=desktop-1280 --workers=1`: 8/8 passed.
- `npx playwright test e2e/visual.spec.ts --workers=1`: 40/40 passed across 1280x720, 1440x900, 1920x1080, 900x900, and 390x844.
- Temporary `web/playwright-report` and `web/test-results` output is generated-only and must not be committed.
