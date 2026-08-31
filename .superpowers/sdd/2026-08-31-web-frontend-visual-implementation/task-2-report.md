# Task 2 Implementation Report

## Scope

Task 2 establishes the visual token layer and the first reusable Web UI primitives while preserving the Task 1 React-to-legacy runtime bridge. The old runtime remains mounted by `web/src/app/App.tsx`; this task does not replace or migrate it.

## Files Changed

- `web/src/styles/tokens.css`
  - Adds the light visual baseline: page and surface colors, deep green brand colors, coral attention colors, border and error colors, system font stack, 4px spacing values, radii, content width, motion timing, and disabled opacity.
- `web/src/styles/global.css`
  - Adds box sizing, page defaults, the fixed system font stack, zero letter spacing, inherited control typography, visible `:focus-visible` rings, responsive `.app-content` width rules, primitive styles, and `prefers-reduced-motion` handling.
  - Uses token variables for theme values and contains no gradients.
- `web/src/main.tsx`
  - Keeps the existing `./styles.css` legacy stylesheet import and adds `tokens.css` plus `global.css` before rendering the unchanged React bridge.
- `web/src/components/ui/Button.tsx`
  - Provides a semantic native button with a default `type="button"`, explicit `type="submit"` support, four tones (`primary`, `neutral`, `quiet`, `danger`), native disabled behavior, and stable `ui-button` modifier classes.
- `web/src/components/ui/IconButton.tsx`
  - Provides a fixed-size semantic icon-only button with `aria-label`, matching `title` tooltip text, native disabled behavior, and a stable `ui-icon-button` class. The icon slot accepts a `ReactNode` so callers can provide Lucide icons without hand-drawn SVG inside the primitive.
- `web/src/components/ui/StatusBadge.tsx`
  - Renders status text, a `data-status` value, and stable `ui-status-badge` plus sanitized status modifier classes. Common waiting, error, completed, and success modifiers use the centralized visual tokens.
- `web/src/components/ui/SectionHeading.tsx`
  - Renders an actual `h2`, `h3`, or `h4`, preserves heading attributes such as `id`, and applies the stable `ui-section-heading` class for section association.
- `web/test/ui-primitives.test.tsx`
  - Adds eight focused React Testing Library tests covering button types, disabled click behavior, tone classes, icon button naming and tooltip behavior, status text/classes, and associated section headings.

## Behavior

- Primary controls use deep green, secondary controls use a white surface and border, quiet actions remain text-oriented, and danger actions use the coral relationship from the visual specification.
- All icon-only controls expose both an accessible name and a native hover tooltip through the supplied label.
- Primitive dimensions are stable: buttons have a 36px minimum height and icon buttons are 36px by 36px.
- Focus remains visibly outlined in interactive green, and motion is reduced for users who request reduced motion.
- The legacy `styles.css` import and Task 1 `App` bridge are unchanged apart from loading the new global layers.

## Test-First Evidence

The new primitive test was run before production modules existed and failed with the expected unresolved imports for `Button`, `IconButton`, `StatusBadge`, and `SectionHeading`. After implementation, the same focused suite passed.

## Verification

Commands were run from `web/` unless stated otherwise.

| Command | Result |
| --- | --- |
| `npm test -- --run test/ui-primitives.test.tsx` | PASS: 1 file, 8 tests |
| `npm test -- --run test/ui-primitives.test.tsx test/app-shell.test.tsx` | PASS: 2 files, 10 tests |
| `npm run typecheck` | PASS: TypeScript completed with exit code 0 |
| `npm run build` | PASS: Vite transformed 59 modules and produced the production bundle |
| `git diff --check` | PASS: no whitespace errors |
| `npm test -- --run` | Existing baseline issue: 1 file failed, 11 passed; 2 tests failed, 79 passed |

## Concerns

- The full Web suite has two unrelated pre-existing failures in `web/test/workspace-actions.test.ts`: task creation does not call the mocked `createTask`, and the create button does not become disabled during a loading rerender. The same failures were present before Task 2 changes and are outside this task's file boundary.
- The initial round exposed a `lucide-react@0.468.0` / React 19 type mismatch; Fix Round 1 resolves it by upgrading to `lucide-react@0.475.0` and adding a direct-import typecheck fixture.

## Fix Round 1

The reviewer-required fixes were implemented without migrating any business UI:

- Updated `web/package.json` and `web/package-lock.json` from `lucide-react@^0.468.0` to `lucide-react@^0.475.0`, the first compatible release selected for the existing React 19 setup. Added `web/test/lucide-import.typecheck.tsx`, a direct `Menu` import fixture included by `tsconfig.json`, so `npm run typecheck` verifies real Lucide imports.
- Added the `muyu-react-root` host marker in `web/src/main.tsx`. Removed document-wide body, control, link, focus, box-sizing, and motion selectors from `global.css`; React defaults now apply only below non-legacy direct children of `[data-testid="muyu-app"]`. The existing `[data-testid="legacy-app-root"]` subtree remains outside those defaults, and the legacy `styles.css` import and runtime bridge are preserved.
- Darkened `--color-coral` to `#91412F`, added the `approval` status modifier to the coral status group, and added `web/test/visual-foundation.test.ts`. The test checks the React/legacy selector boundary and computes the coral foreground/surface contrast ratio using the WCAG relative-luminance formula; the resulting pair is 5.45:1.

### Fix Round 1 Verification

| Command | Result |
| --- | --- |
| `npm test -- --run test/visual-foundation.test.ts` | PASS: 1 file, 2 tests |
| `npm test -- --run test/ui-primitives.test.tsx test/visual-foundation.test.ts test/app-shell.test.tsx` | PASS: 3 files, 12 tests |
| `npm run typecheck` | PASS: direct Lucide import fixture and project TypeScript completed with exit code 0 |
| `npm run build` | PASS: Vite transformed 59 modules and produced the production bundle |
| `npm test -- --run` | 12 files and 81 tests passed; the same 2 pre-existing `workspace-actions` tests failed |
| `git diff --check` | PASS: no whitespace errors |
