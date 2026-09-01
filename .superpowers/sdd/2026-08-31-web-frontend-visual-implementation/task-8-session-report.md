# Task 8 Web Session Slice

## Scope

- Added `WebSessionPanel` as a React surface backed by the existing `WebSessionViewApi` contract.
- Extended `UserMenu` with optional `sessionApi`, `onAuthRequired`, and `now` props.
- Kept the legacy menu behavior for Escape, outside click, focus restoration, and logout.
- Did not modify `App.tsx`, `AppShell`, `TopNav`, activity files, global styles, backend, or other shared files.

## Behavior

- Lists only `ACTIVE` sessions whose `expires_at` is later than the injected clock.
- Provides loading, empty, failure, and busy states.
- Removes a session from the rendered list only after a successful revoke.
- Keeps the session visible and shows a local safe error after revoke failures.
- Clears the list only after successful revoke-all.
- Calls `onAuthRequired` for HTTP 401 responses from list, revoke, and revoke-all.
- Renders origin and timestamps only; token, cookie, proof, and digest values never enter the DOM.
- Omits the session panel entirely when `UserMenu` has no session API.

## Verification

- `npm test -- --run test/web-session-panel.test.tsx test/web-session-view.test.ts`: 17/17 passed.
- `npm run typecheck`: passed.
- `git diff --check`: passed.

## Residual risk

The parent integration that supplies the optional session API to the top-level navigation remains outside this slice by design.
