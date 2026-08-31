# Task 3 Report: React App Lifecycle and Routing

Date: 2026-08-31
Scope: React lifecycle, hash routing, external-store subscriptions, and realtime ownership.

## Implementation

- Added `web/src/app/routes.ts` with the Task 3 route discriminated union, hash parsing, safe task-id decoding, fallback to Today, and hash-only navigation. `navigate` accepts the named route shorthand as well as task route objects for compatibility with the executable brief examples.
- Added `web/src/app/use-external-state.ts` using `useSyncExternalStore` for workspace and QR-login controller state. The hooks subscribe to controller notifications and return the controllers' existing snapshot objects without copying or mutating them.
- Added `web/src/app/use-workspace-realtime.ts` to own socket creation and cleanup, higher-cursor hint pulls, visible-page 10-second fallback pulls after socket failure, reconnect cancellation of the fallback, and timer/socket teardown.
- Reworked `web/src/app/App.tsx` so React effects own initial snapshot loading, login start/stop, logout cleanup, auth-required transitions, stale-session isolation, realtime teardown, and legacy-view mounting during the incremental migration. A narrow controller-capability fallback keeps the existing app-shell tests and legacy UI usable while Task 4+ visual migration is deferred.
- Preserved `web/src/main.tsx` exactly at the React root boundary, including the Task 2 global style import order and root class marker. No old DOM views or service modules were removed.

## TDD and Verification

The focused tests were first run before the new modules existed and failed on unresolved imports plus the expected lifecycle gaps. After implementation:

```text
npm test -- --run test/routes.test.ts test/use-external-state.test.tsx test/app-lifecycle.test.tsx
3 test files passed, 11 tests passed

npm run typecheck
passed (tsc --noEmit)
```

Previously run Task 3 verification also passed:

```text
npm run build
passed (Vite 8.2.2, 61 modules transformed)

npm test -- --run test/app-shell.test.tsx test/app.test.ts test/workspace-sync.test.ts test/qr-login.test.ts
4 test files passed, 38 tests passed
```

The full suite still has the same two baseline failures observed before Task 3, both in `test/workspace-actions.test.ts`:

1. The create-task test observes zero calls to its mocked `createTask`.
2. The loading-rerender test expects the create control to be disabled but observes `false`.

The full-suite result was 15 files passed, 1 failed, 94 tests passed, and 2 failed. These failures are outside the Task 3 file scope and were not changed.

## Concerns and Compatibility Notes

- The brief's prose route alias describes string route members, while its executable parse examples expect `{ kind: ... }` objects. The implementation follows the executable contract and accepts both forms for navigation.
- Legacy `QrLoginView` and `WorkspaceView` remain mounted through a direct compatibility bridge until later visual migration tasks replace them. The bridge is keyed by screen/workspace identity rather than every sync snapshot, so ordinary pulls do not remount the workspace and discard draft input.
- Realtime cleanup runs before logout is sent, and session generation checks prevent late snapshot, login, or pull results from reviving a stale session.

## Commit

Commit `d3b45f4` (`feat(web): add React app lifecycle and routing`) contains only the scoped Task 3 source/test changes. `web/src/main.tsx` was explicitly preserved and has no content change to commit.

## Fix Round 1

Date: 2026-08-31

### Review fixes

- Kept the App-level legacy sync bridge and invalidated it before legacy cleanup or sync clearing. After invalidation, legacy state reads expose an auth-required inactive state and controller method calls are no-ops, so a late create ACK cannot remount the old workspace into the active root.
- Added a mount-lifetime guard to `WorkspaceView` for late renders, logout callbacks, and task-opening handlers. This closes the direct `openTask` root mutation path that the proxy alone could not intercept.
- `recoverAuthRequired` now disposes the local workspace, clears sync, enters QR login, and starts the login flow before invoking `logoutWebSession` as best-effort cleanup. The hanging logout regression confirms QR recovery does not await that request.
- `App` initializes its route with an empty hash when `window` is unavailable. The server-render test covers this browser-only boundary; the hashchange listener remains client-side effect work.

### Verification

The stale-handler regression was first run against the partial bridge and failed because `.task-detail` was appended after logout; it passes after the `WorkspaceView` lifetime guard.

```text
npm test -- --run test/routes.test.ts test/use-external-state.test.tsx test/app-lifecycle.test.tsx
3 files passed, 15 tests passed

npm test -- --run test/app-shell.test.tsx test/app-session-isolation.test.ts test/qr-login.test.ts
3 files passed, 21 tests passed

npm run typecheck
passed (tsc --noEmit)

npm run build
passed (Vite 8.2.2, 61 modules transformed)

npm test -- --run
15 files passed, 1 file failed; 99 tests passed, 2 tests failed
```

The full-suite failures are the same pre-existing `test/workspace-actions.test.ts` failures recorded above: the create-task test observes zero mocked `createTask` calls, and the loading-rerender test observes an enabled create control. No new failing file was introduced by Fix Round 1.

## Fix Round 2

Date: 2026-08-31

### Review fixes

- Made every approval/comment/task async response generation-safe, including response assignment, state merges, nested reconciliation pulls, cursor-expiry snapshot recovery, and error/finally handling. `clear()` and `dispose()` also release queued pull waiters so session teardown cannot leave a caller blocked.
- Added a controller-level pull queue. Pulls are serialized from the current cursor, duplicate and concurrent realtime hints are coalesced with the highest pending hint retained, and explicit write reconciliation pulls use the same queue without being dropped after an ACK advances the local cursor.
- Realtime hints now pass their cursor to the controller. A socket reconnect performs an immediate catch-up pull before fallback polling is stopped; fallback and reconnect pulls share the controller queue.
- Explicit logout now carries a request token. A new QR sign-in can load its workspace while the prior logout is pending, and a stale logout completion cannot clear the new session lifecycle. Auth-required recovery starts immediately even when an explicit logout is in flight.

### Verification

The new regressions were first run against `0010cf3` and failed on the expected missing guards, duplicate pulls, absent reconnect pull, and skipped new-session load. After the fixes:

```text
npm test -- --run test/routes.test.ts test/use-external-state.test.tsx test/app-lifecycle.test.tsx test/workspace-sync.test.ts test/app.test.ts test/qr-login.test.ts
6 files passed, 56 tests passed

npm run typecheck
passed (tsc --noEmit)
```

The relevant legacy compatibility tests also pass:

```text
npm test -- --run test/app-shell.test.tsx test/app-session-isolation.test.ts test/qr-login.test.ts
3 files passed, 21 tests passed
```

The full suite remains at 15 files passed, 1 file failed, 104 tests passed, and 2 tests failed. Both failures are the same pre-existing `test/workspace-actions.test.ts` failures documented in Fix Round 1; no new failing file was introduced by Fix Round 2.

## Fix Round 3

Date: 2026-08-31

### Review fixes

- Treats a changes envelope as valid only when its cursor is a safe non-negative integer matching the last returned change, or matching `after_cursor` for an empty response. Contiguous pages advance only to the last returned change; malformed and non-contiguous envelopes recover through a snapshot without trusting a cursor leap.
- Pull hints and write ACK cursors are reconciliation targets. The controller continues paginated requests from each newly applied cursor until the highest requested target is reached, while write ACK resources merge without advancing the applied cursor.
- Pull waiters are tracked for both queued and active requests. `clear()` and `dispose()` resolve all waiters, detach the old generation's drain, and generation/identity guards prevent a hanging old request or its cleanup from blocking or mutating a new session.
- Same-generation snapshot loads use a request sequence so stale refresh responses cannot overwrite newer state. Top-level loading uses a generation-scoped operation count and remains true until the current generation's active operations finish.
- Realtime fallback ticks use one active request plus one coalesced pending request, and pending fallback work is canceled when the socket reconnects or the effect stops.

### TDD and Verification

The Fix Round 3 regressions were first run against `c760857` and failed as expected: 7 failures across the sync and lifecycle files covering paginated hints, envelope cursor trust, ACK cursor leaps, active pull teardown, refresh ordering/loading, and fallback coalescing. After implementation:

```text
npm test -- --run test/routes.test.ts test/use-external-state.test.tsx test/app-lifecycle.test.tsx test/workspace-sync.test.ts
4 files passed, 37 tests passed

npm test -- --run test/app-shell.test.tsx test/app-session-isolation.test.ts test/app.test.ts test/qr-login.test.ts
4 files passed, 32 tests passed

npm run typecheck
passed (tsc --noEmit)

npm run build
passed (Vite 8.2.2, 61 modules transformed)
```

The full Web suite remains at 15 files passed, 1 file failed, 111 tests passed, and 2 tests failed. The failures are the same pre-existing `test/workspace-actions.test.ts` failures: the create-task mock observes zero calls, and the loading-rerender test observes an enabled create control. No new failing file was introduced by Fix Round 3.

## Fix Round 4

Date: 2026-08-31

### Review fixes

- Added a committed-snapshot identity fence to the pull drain. A pull captures the identity of the snapshot it starts against, and a same-generation refresh that commits a newer snapshot makes the old pull inert before it can validate, apply resources, or advance the cursor. Generation and intentional new-session guards remain unchanged.
- Changes envelopes now require the active snapshot workspace ID, complete change metadata, contiguous cursors, and shape-valid known resources before any resource is applied. Task, approval-request, and comment resources are validated defensively; null resources remain valid tombstones for legitimate deletion changes. Invalid envelopes recover through the existing snapshot path.
- Added regression coverage for refresh-versus-pull ordering, lower-cursor snapshots (including a workspace switch without a new generation), foreign-workspace envelopes, malformed task/approval/comment resources, and malformed change metadata.

### TDD and Verification

The four additional regressions were run against the existing partial round-4 worktree before the final tightening and failed as expected: the lower-cursor workspace switch was accepted, and negative approval/comment versions plus an unknown action were applied instead of recovering. After implementation:

```text
npm test -- --run test/workspace-sync.test.ts
1 file passed, 29 tests passed

npm test -- --run test/routes.test.ts test/use-external-state.test.tsx test/app-lifecycle.test.tsx test/workspace-sync.test.ts
4 files passed, 46 tests passed

npm test -- --run test/app-shell.test.tsx test/app-session-isolation.test.ts test/app.test.ts test/qr-login.test.ts
4 files passed, 32 tests passed

npm run typecheck
passed (tsc --noEmit)

npm run build
passed (Vite 8.2.2, 61 modules transformed)
```

The full Web suite remains at 15 files passed, 1 file failed, 120 tests passed, and 2 tests failed. Both are the same pre-existing `test/workspace-actions.test.ts` failures documented in earlier rounds: the create-task mock observes zero calls, and the loading-rerender test observes an enabled create control. No new failing file was introduced by Fix Round 4. The backend sync pytest command was not available in the environment (`pytest: command not found`); no backend files changed.

## Fix Round 5

Date: 2026-08-31

### Review fix

- Transient REST pull failures now retain the affected realtime hint and write-ACK waiters instead of resolving them at the unchanged cursor. The controller retries with bounded delays of 1, 2, and 5 seconds, preserves the highest reconciliation target, coalesces newer pulls without overlapping requests, and resolves the waiter after exhaustion with the existing stale/error state.
- Retry timers and retained requests are canceled and resolved by `clear()`/`dispose()` and are fenced by the current session generation, so an old session cannot restart work in a new login.
- Added regressions for healthy-socket retry, high realtime targets, write-ACK reconciliation, newer-hint coalescing, generation cancellation, and bounded retry exhaustion.

### TDD and Verification

```text
npm test -- --run test/workspace-sync.test.ts
1 file passed, 34 tests passed

npm run typecheck
passed (tsc --noEmit)

git diff --check
passed
```

The full Web suite was not rerun for this final round. Earlier full-suite runs had two pre-existing failures in `test/workspace-actions.test.ts`; no backend files changed.

## Fix Round 5

Date: 2026-08-31

### Review fixes

- Added a bounded, generation-safe retry schedule for transient REST pull failures with 1-second, 2-second, and 5-second delays. Retries stop after exhaustion and resolve the retained pull waiters.
- Retained the highest realtime hint and explicit write reconciliation target across a failed pull, keeping REST requests serialized and allowing the retry to continue pagination through the requested cursor.
- `clear()` and `dispose()` cancel pending retry timers, release queued and retained waiters, and invalidate the old generation so canceled retry callbacks cannot re-enter a new session.
- Added regression coverage for healthy realtime sockets during retries, newer hint coalescing, write ACK reconciliation, clear cancellation, and bounded retry exhaustion.

### Verification

Verification was attempted by the prior worker but timed out before completion; no completed verification result is available for Fix Round 5.
