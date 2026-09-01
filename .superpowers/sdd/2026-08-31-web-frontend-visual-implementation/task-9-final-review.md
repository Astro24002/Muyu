# Task 9 Final Review

Date: 2026-09-01
Review range: `a5c0564..4f56837`
Review mode: read-only; no product files were modified.

## Verdict

**CLEAN**

No critical (P0/P1) findings were identified. The P2/P3 items below are non-critical hardening and coverage gaps retained for follow-up.

## Findings

### P2: The global WebSocket stub breaks the Vite dev client

Location: `web/e2e/fixtures.ts:39-79`, `web/playwright.config.ts:48-54`

The fixture replaces `window.WebSocket` while the suite runs the Vite development server. The replacement exposes `onopen`/`onclose` properties, but does not implement the standard instance `OPEN` constant or `addEventListener`/`removeEventListener`. Vite's injected HMR client uses those APIs, so every browser page can produce an unhandled HMR connection error while the test still passes because page errors and console errors are never asserted. Use a compatible `EventTarget`-based stub, disable HMR for the test server, or avoid replacing the global constructor.

### P2: Screenshots are artifacts, not visual regression assertions

Location: `web/e2e/visual.spec.ts:233-235`

`capture()` only writes `page.screenshot({ path })`; there are no `toHaveScreenshot` baselines or pixel/geometry snapshots. CSS changes can therefore pass all 40 cases while changing the established visual direction. The report's “visual verification” claim is limited to manual artifacts, not an automated visual guard.

### P2: Mobile breakpoint checks do not prove the CSS layout contract

Location: `web/playwright.config.ts:40-45`, `web/e2e/visual.spec.ts:99-115`

The projects cover 900px and 390px, but not the 1023px/640px boundaries. The sheet assertion checks `data-panel-mode`, which is derived from `window.innerWidth`, rather than the panel's computed `position`, inset, width, and max-height. The stacked assertion also relies on a loose bounding-box heuristic and does not validate the 900px sheet layout. A breakpoint or CSS rule can regress while these assertions remain green.

### P2: The API fixture is a permissive catch-all and can hide endpoint regressions

Location: `web/e2e/fixtures.ts:81`, `web/e2e/fixtures.ts:304-554`

The narrowed `**/api/v1/**` glob no longer intercepts `/src/api/*`, which is correct, but every unrecognized API request is still fulfilled with a synthetic 404 at line 554. There is no request ledger or fail-fast assertion for unexpected routes, and the tests do not exercise most write paths. A typo, missing endpoint, or wrong workspace/ID can consequently degrade into an empty/error UI without failing the intended workflow. Unknown requests should fail the test explicitly or be allowed through, with the expected request set asserted.

### P3: Sensitive-data checks only scan visible literal names

Location: `web/e2e/visual.spec.ts:5-16`, `web/e2e/fixtures.ts:213-224`

The fixture contains dummy challenge/session identifiers and a safety code, and the test only checks that the rendered body lacks the literal strings `browser_proof` and `session_token`. It does not inspect cookies, local/session storage, URLs, request payloads, or screenshot contents, and it would not detect an actual secret value rendered under another field name. No real credential was found in this commit, but the reported “does not expose credentials” guarantee is not enforced by the test.

### P3: Test configuration is dependent on the caller's working directory

Location: `web/vite.config.ts:12-17`, `web/playwright.config.ts:6-16,48-52`

The relative test paths and `cwd: process.cwd()` work when commands are run from `web`, as documented, but fail or target the wrong directory when the nested configs are invoked from the repository root. For example, running `web/node_modules/.bin/vitest --config web/vite.config.ts --run` from the repository root reports “No test files found”. Resolve paths from the config directory or make the required working directory an explicit project command.

## Verification

- Exact commit temporary copy: `npm run typecheck` passed.
- Exact commit temporary copy: full Vitest `214/221` passed; the seven failures are the existing `app-lifecycle` and `workspace-actions` migration tests. The Task9 report records them, but they remain unresolved rather than a green suite.
- Exact commit temporary copy: one full Playwright run was `39/40`; the mobile-stacked Activity case rendered a blank page. Repeating that case five times passed, so this is not classified as a separate deterministic product failure, but it should be investigated before claiming stable browser verification.
- `git diff --check` reports only a trailing blank line in `web/playwright.config.ts`.

## Scope Notes

The worktree contained concurrent uncommitted Task10 changes during verification. They were not reviewed, reverted, or modified; conclusions above are based on the commit objects in the requested range.
