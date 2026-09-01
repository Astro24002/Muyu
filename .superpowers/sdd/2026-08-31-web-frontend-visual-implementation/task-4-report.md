# Task 4 Report: Action-Oriented App Shell and QR Login

Date: 2026-08-31
Scope: Top navigation, authenticated app shell, shared sync/error status, and React QR-login rendering.

## Implementation

- Added `AppShell` as a single authenticated page frame with a 58px white top bar and a centered 960px content container. The shell does not render a `main` landmark, so the legacy workspace view can continue to provide its own page landmark during the incremental migration.
- Added `TopNav` with exactly four primary routes: Today, All Tasks, Approvals, and Activity. The active route exposes `aria-current="page"`, an explicit active-indicator data contract, and a CSS bottom rule. Task detail routes keep All Tasks active.
- Added `UserMenu` with an accessible icon trigger, keyboard/outside-click dismissal, and an actionable logout button. Search opens a focused, labelled searchbox dialog with a close control and Escape handling. New Task invokes the App callback, which focuses the existing legacy task-title input while Task 5 remains out of scope.
- Added `SyncStatus` for normal, loading, stale-snapshot, and error states. Normal sync uses the low-weight green dot and `刚刚同步`; stale snapshots use `内容可能不是最新`; errors receive an assertive alert treatment. `InlineError` keeps messages beside their trigger and optionally supplies a local retry action without replacing inputs.
- Added `QrLoginPage`, which subscribes to the existing `QrLoginController` state and preserves its public state machine: signed out, creating, waiting for approval, exchanging, signed in, expired, and failure. Waiting/exchanging states render a labelled canvas through `QRCode.toCanvas`, the safety code, current origin, expiry time, manual poll action, and regenerate behavior. The page never reads, stores, or renders the controller's private raw proof.
- Updated `App` to render the React QR page whenever unauthenticated, while retaining the legacy `WorkspaceView` compatibility bridge for authenticated workspace behavior. Existing generation guards, socket cleanup, auth-required recovery, logout ordering, and controller disposal remain in the App lifecycle. Authenticated content is wrapped in the new shell and receives the pending approver count and sync status.
- Added only the Task 4 style rules and the missing centralized sync color token. The visual rules keep the deep-green/coral relationship, stable navigation height, compact desktop-first layout, visible focus handling from the existing foundation, and responsive tightening below the desktop breakpoint.

## TDD and Verification

The new focused tests were written before the Task 4 production modules existed. The first run failed with unresolved imports for `AppShell`, `TopNav`, and `QrLoginPage`, confirming the tests were exercising the new surface. After implementation, the focused suite passed:

```text
npm test -- --run test/top-nav.test.tsx test/qr-login-page.test.tsx
2 test files passed, 4 tests passed
```

Additional compatibility verification passed:

```text
npm test -- --run test/app-shell.test.tsx test/app-lifecycle.test.tsx test/app-session-isolation.test.ts test/qr-login.test.ts
4 test files passed, 34 tests passed

npm run typecheck
passed (tsc --noEmit)

npm run build
passed (Vite 8.2.2, 1,629 modules transformed)

git diff --check
passed
```

The full Web suite was not rerun for this task. The baseline recorded by Task 3 remains two failures in `test/workspace-actions.test.ts`: the create-task test observes zero calls to its mocked `createTask`, and the loading-rerender test observes an enabled create control. No Task 4 test or production failure was observed in the focused or compatibility runs.

## Compatibility and Residual Risk

- The workspace pages are still rendered by the legacy DOM views until Task 10. The new top-bar New Task action therefore focuses the bridge's existing title input instead of introducing a second task-creation flow.
- The four top-level routes now update the hash and active navigation state, but route-specific React pages remain future Task 5+ work. The current legacy workspace view remains visible while those routes are selected.
- QR canvas rendering errors are contained to the canvas effect; the controller's existing poll, expiry, exchange, generation, and raw-proof cleanup semantics remain authoritative.
- Visual verification was limited to CSS/build validation and jsdom behavior in this task; Playwright screenshot coverage belongs to the later visual acceptance work.

## Fix Round 1

Date: 2026-09-01

- Hardened `global.css` so every non-root React selector, including base, responsive, and reduced-motion rules, excludes `data-testid="legacy-app-root"` and all descendants. Added a static selector-boundary regression assertion.
- Updated `QrLoginPage` to render QR codes through the supported detached-canvas overload and copy only from the current render generation into a still-connected visible canvas. Added a deferred-render regression for removed canvases.
- Added `aria-modal="true"` to the search dialog and restored focus to its trigger after Escape, close-button, and toggle dismissal. `IconButton` now forwards button refs; focus behavior is covered by TopNav tests.
- Preserved the legacy runtime bridge and Task 5+ scope. The documented `workspace-actions` baseline remains two failures: zero mocked `createTask` calls and an enabled create control during loading.

### Fix Round 1 Verification

```text
npm test -- --run test/visual-foundation.test.ts test/top-nav.test.tsx test/qr-login-page.test.tsx
3 test files passed, 12 tests passed

npm test -- --run test/app-shell.test.tsx test/app-lifecycle.test.tsx test/app-session-isolation.test.ts test/qr-login.test.ts
4 test files passed, 34 tests passed

npm run typecheck
passed (tsc --noEmit)

npm run build
passed (Vite 8.2.2, 1,629 modules transformed)

npm test -- --run test/workspace-actions.test.ts
2 documented baseline failures, 3 tests passed

git diff --check
passed
```

## Files

- `web/src/components/layout/AppShell.tsx`
- `web/src/components/layout/TopNav.tsx`
- `web/src/components/layout/UserMenu.tsx`
- `web/src/components/status/SyncStatus.tsx`
- `web/src/components/status/InlineError.tsx`
- `web/src/pages/QrLoginPage.tsx`
- `web/src/app/App.tsx`
- `web/src/styles/global.css`
- `web/src/styles/tokens.css`
- `web/test/top-nav.test.tsx`
- `web/test/qr-login-page.test.tsx`
