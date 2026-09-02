# Android Visual System Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align the Android client with the approved Web visual language while preserving the four-tab Android information architecture and all existing task, sync, approval, profile, and device behavior.

**Architecture:** Add one application-level Material 3 theme with explicit Muyu color, spacing, shape, and state tokens. Keep task navigation in `CloudWorkspaceScreen`, but give 清单、四象限、日程 a shared task-system AppBar contract; keep 我的 as an independent account page with its existing right-side approval and Web QR actions. Refine the existing linear task rows and account sections in place instead of introducing a second navigation or business model.

**Tech Stack:** Flutter, Material 3, Dart widget tests, `flutter analyze`, local Android Debug APK build.

**Spec:** `docs/superpowers/specs/2026-08-31-android-visual-direction-design.md`

## Global Constraints

- Use the Web baseline colors: `#F8FAF9`, `#FFFFFF`, `#1D2D29`, `#25312E`, `#7C8783`, `#225F50`, `#2E7663`, `#E7F0ED`, `#B2573B`, `#F3DFD7`, `#DCE3E0`, `#A33B2E`, `#FBEAE7`, `#52A083`, `#A3AFAA`.
- Use Material 3 and keep the four bottom destinations exactly: 清单、四象限、日程、我的。
- 清单、四象限、日程 share one task-system AppBar contract; 我的 uses an independent account title and keeps approval/Web QR actions in the upper-right.
- Do not add a fifth tab, change task fields, change sync/API contracts, add a dark theme, or reintroduce a management sidebar/KPI dashboard.
- Use spacing values `4 / 8 / 12 / 16 / 24 / 32`, ordinary corner radius `6px`, panel/floating maximum `8px`, and zero elevation for ordinary rows/sections.
- Use `colorScheme.primary` for the create FAB; no old blue `#2F80ED` or scattered theme colors remain in business screens.
- Every production behavior change gets a focused failing test before implementation; all existing Flutter tests remain green.

---

### Task 1: Add the application theme tokens

**Files:**
- Create: `client/lib/theme/muyu_theme.dart`
- Modify: `client/lib/app.dart`
- Create: `client/test/theme/muyu_theme_test.dart`

**Interfaces:**
- `MuyuThemeExtension` exposes `focusSurface`, `coral`, `coralSurface`, `sync`, and `disabled` as immutable `Color` fields.
- `MuyuSpacing` exposes `xs`, `sm`, `md`, `lg`, `xl`, and `xxl` constants for `4/8/12/16/24/32`.
- `muyuLightTheme()` returns the complete light `ThemeData` consumed by `MuyuApp`.

- [ ] **Step 1: Write failing token tests.** Add tests that assert `muyuLightTheme()` maps the documented colors to `scaffoldBackgroundColor`, `colorScheme.surface`, `primary`, `secondary`, `outline`, `error`, and `errorContainer`; assert the extension state colors and spacing constants; assert the FAB theme uses `primary`.

- [ ] **Step 2: Run the focused test and confirm the expected failure.**

  Run: `cd client && flutter test test/theme/muyu_theme_test.dart`

  Expected: FAIL because the theme module and token values do not yet exist.

- [ ] **Step 3: Implement the theme module.** Define the constants and `ThemeExtension`, construct a non-seeded explicit `ColorScheme.light`, set `scaffoldBackgroundColor` to `#F8FAF9`, configure `TextTheme` with zero letter spacing and the documented title/body hierarchy, configure `CardTheme`, `AppBarTheme`, `NavigationBarTheme`, `InputDecorationTheme`, `FloatingActionButtonThemeData`, and `PopupMenuThemeData` with the shared surface/outline/shape values.

- [ ] **Step 4: Make `MuyuApp` consume `muyuLightTheme()`.** Remove the old `ColorScheme.fromSeed(seedColor: #087F73)`, old scaffold `#F7F8F6`, and old card border color. Keep `useMaterial3: true` and attach `MuyuThemeExtension` through `ThemeData.extensions`.

- [ ] **Step 5: Run the focused test and analyzer.**

  Run: `cd client && flutter test test/theme/muyu_theme_test.dart && flutter analyze lib/theme/muyu_theme.dart lib/app.dart`

  Expected: all token tests pass and analyzer reports no issues.

- [ ] **Step 6: Commit the isolated theme change.**

  Run: `git add client/lib/theme/muyu_theme.dart client/lib/app.dart client/test/theme/muyu_theme_test.dart && git commit -m "feat(client): add shared Muyu visual theme"`

### Task 2: Introduce the shared task-system AppBar

**Files:**
- Create: `client/lib/widgets/task_system_app_bar.dart`
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`

**Interfaces:**
- `TaskSystemAppBar({required String title, Widget? leading, List<Widget> actions, Widget? titleContent})` implements `PreferredSizeWidget` with one stable Material AppBar height and the theme surface/outline.
- `CloudWorkspaceScreen` uses this widget for 清单、四象限、日程; `_buildProfileAppBar` remains independent for 我的.

- [ ] **Step 1: Add failing AppBar consistency tests.** Extend the cloud workspace widget tests to navigate across 清单、四象限、日程 and assert each exposes `Key('task-system-app-bar')`, the same `preferredSize.height`, and a title/content key; assert 我的 exposes `Key('profile-account-app-bar')` and still exposes `profile-approval-center` and `profile-web-qr-login` only there.

- [ ] **Step 2: Run the focused tests and confirm failure.**

  Run: `cd client && flutter test test/screens/cloud_workspace_screen_test.dart`

  Expected: FAIL because the current task pages use separate AppBar implementations and the task pages have no shared key.

- [ ] **Step 3: Implement `TaskSystemAppBar`.** Use the theme surface, `titleLarge`/documented title text style, a stable `kToolbarHeight`, and a bottom `PreferredSize` border using `colorScheme.outline`. Keep title content flexible so 清单’s category selector does not overflow.

- [ ] **Step 4: Refactor `CloudWorkspaceScreen` AppBar selection.** Use one task-system builder for indices 0–2 with titles 清单、四象限、日程 and contextual actions; keep the task list hamburger/category/more actions in the same action slots. Use an independent profile AppBar key for index 3 and retain approval/QR actions in its right side. Replace the FAB’s hard-coded blue background/foreground with the theme FAB configuration.

- [ ] **Step 5: Run focused tests and analyzer.**

  Run: `cd client && flutter test test/screens/cloud_workspace_screen_test.dart && flutter analyze lib/widgets/task_system_app_bar.dart lib/screens/cloud_workspace_screen.dart`

  Expected: all cloud workspace tests pass with no analyzer errors.

- [ ] **Step 6: Commit the AppBar change.**

  Run: `git add client/lib/widgets/task_system_app_bar.dart client/lib/screens/cloud_workspace_screen.dart client/test/screens/cloud_workspace_screen_test.dart && git commit -m "feat(client): unify task system app bars"`

### Task 3: Align task rows and task views

**Files:**
- Modify: `client/lib/screens/task_list_view.dart`
- Modify: `client/lib/screens/task_quadrant_view.dart`
- Modify: `client/lib/screens/task_schedule_view.dart`
- Modify: `client/test/screens/task_navigation_labels_test.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`

**Interfaces:**
- Existing `TaskListRow` and `TaskSummaryCard` keys/classes remain available to avoid breaking navigation tests, but render as stable linear rows with zero elevation and theme separators.
- `TaskSummaryCard` continues to accept `TaskItem`, `WorkspaceSyncState`, and `onTap`; it displays title, status/quadrant/labels/due metadata and the mapped handler name.

- [ ] **Step 1: Add failing row visual behavior tests.** Assert a task row uses `colorScheme.surface`, has no `Card` elevation, displays the handler display name, and retains stable key/title/subtitle behavior in list, quadrant, and schedule views. Assert the task list empty/error state uses theme text colors and `RefreshIndicator` remains present.

- [ ] **Step 2: Run focused tests and confirm failure for the new assertions.**

  Run: `cd client && flutter test test/screens/task_navigation_labels_test.dart test/screens/cloud_workspace_screen_test.dart`

  Expected: failures for Card/elevation/theme assertions against the current implementations.

- [ ] **Step 3: Refactor `TaskListRow` to the tokenized linear row.** Replace raw colors and styles with `Theme.of(context).colorScheme` and `textTheme`; use fixed `minHeight`/padding, an outline divider, and explicit semantic status labels; preserve owner display, due date, progress, waiting, and subtask text.

- [ ] **Step 4: Refactor `TaskSummaryCard` internals.** Keep its public name/key contract but use a transparent `Material`/`ListTile` row, theme divider, compact title and metadata, no elevation, and no nested card. Reuse the handler-name helper and preserve tap behavior.

- [ ] **Step 5: Align quadrant and schedule grouping.** Use `titleMedium`/`titleSmall` from the theme, `MuyuSpacing` padding, concise empty-state text, and consistent label filter styling; do not change grouping or task filtering logic.

- [ ] **Step 6: Run task-view tests and analyzer.**

  Run: `cd client && flutter test test/screens/task_navigation_labels_test.dart test/screens/cloud_workspace_screen_test.dart && flutter analyze lib/screens/task_list_view.dart lib/screens/task_quadrant_view.dart lib/screens/task_schedule_view.dart`

  Expected: all focused tests pass and no analyzer issues.

- [ ] **Step 7: Commit the task-view change.**

  Run: `git add client/lib/screens/task_list_view.dart client/lib/screens/task_quadrant_view.dart client/lib/screens/task_schedule_view.dart client/test/screens/task_navigation_labels_test.dart client/test/screens/cloud_workspace_screen_test.dart && git commit -m "feat(client): align task views with Muyu rows"`

### Task 4: Align the independent 我的 page

**Files:**
- Modify: `client/lib/screens/my_profile_screen.dart`
- Modify: `client/lib/screens/profile_edit_screen.dart`
- Modify: `client/lib/screens/device_management_screen.dart`
- Modify: `client/test/screens/my_profile_screen_test.dart`
- Modify: `client/test/screens/my_profile_workspace_match_test.dart`

**Interfaces:**
- Existing profile, workspace match, overview, device management, approval, QR, and edit callbacks remain unchanged.
- `MyProfileScreen` uses the account page theme and does not consume task-system category/more controls.

- [ ] **Step 1: Add failing profile visual tests.** Assert profile sections use the shared page background/surface, compact account content, theme primary action colors, and no generic blue hard-coded colors or oversized device tiles; assert the independent AppBar actions remain in the upper-right.

- [ ] **Step 2: Run focused tests and confirm the expected failures.**

  Run: `cd client && flutter test test/screens/my_profile_screen_test.dart test/screens/my_profile_workspace_match_test.dart`

  Expected: failures for the new theme/shape/background assertions.

- [ ] **Step 3: Refactor profile sections.** Replace raw `Colors.black45`, hard-coded radii, and broad Card defaults with theme `onSurfaceVariant`, `surface`, `outline`, `MuyuSpacing`, and `MuyuThemeExtension` status colors. Keep the personal profile, workspace match, overview, and compact device-management entry as separate readable sections without introducing nested cards.

- [ ] **Step 4: Refactor edit/device surfaces.** Apply the same title text, input decoration, action button, confirmation dialog, and error styling to profile edit and device management while preserving their callbacks and current-device deletion guard.

- [ ] **Step 5: Run profile tests and analyzer.**

  Run: `cd client && flutter test test/screens/my_profile_screen_test.dart test/screens/my_profile_workspace_match_test.dart test/screens/profile_edit_screen_test.dart test/devices/device_management_test.dart && flutter analyze lib/screens/my_profile_screen.dart lib/screens/profile_edit_screen.dart lib/screens/device_management_screen.dart`

  Expected: all profile/device tests pass and analyzer reports no issues.

- [ ] **Step 6: Commit the profile change.**

  Run: `git add client/lib/screens/my_profile_screen.dart client/lib/screens/profile_edit_screen.dart client/lib/screens/device_management_screen.dart client/test/screens/my_profile_screen_test.dart client/test/screens/my_profile_workspace_match_test.dart && git commit -m "feat(client): align account surfaces with Muyu theme"`

### Task 5: Remove remaining old visual values and verify the full client

**Files:**
- Modify only Android Dart files that still contain old visual literals identified by the static scan.
- Modify: `client/test/theme/muyu_theme_test.dart` if a regression assertion is needed.
- Update: `docs/05-development-status.md` with verification facts only after all checks pass.

- [ ] **Step 1: Run the old-style scan.**

  Run: `rg -n "#087f73|#f7f8f6|#2f80ed|Color\\(0xff|Colors\\.(blue|black|white|grey)|Radius\\.circular\\((9|1[0-9]|[2-9][0-9])" client/lib -g '*.dart'`

  Expected: no business-screen theme literals remain; any permitted icon/status literal is either moved into `MuyuThemeExtension` or replaced with a documented semantic token.

- [ ] **Step 2: Add tests for any discovered regression and run them red.** For each remaining production literal that violates the spec, add one focused assertion to the relevant screen/theme test and confirm it fails before changing the production code.

- [ ] **Step 3: Replace the remaining literals with theme access.** Use `Theme.of(context).colorScheme`, `Theme.of(context).textTheme`, `MuyuSpacing`, and `MuyuThemeExtension`; keep behavior and keys unchanged.

- [ ] **Step 4: Run complete Android verification.**

  Run: `cd client && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`

  Expected: format check, analyzer, and the full Flutter test suite all exit 0.

- [ ] **Step 5: Build the local commit-named APK.**

  Run: `cd .. && API_BASE_URL=https://muyu.bkverse.space ./scripts/build-android-debug.sh`

  Expected: `client/build/app/outputs/flutter-apk/Muyu-<short-commit>.apk` exists. Verify it with `test -s`, `unzip -tq`, and `sha256sum`.

- [ ] **Step 6: Record the implementation and verification.** Add a dated entry to `docs/05-development-status.md` with the theme refactor scope, test counts, APK filename and SHA-256. Do not include phone numbers, OTPs, access tokens, database URLs, or private keys.

- [ ] **Step 7: Commit the final verification record.**

  Run: `git add client docs/05-development-status.md && git commit -m "feat(client): complete Android visual alignment"`

## Self-Review Checklist

- [ ] Web/Android colors and semantics match without copying the Web desktop layout.
- [ ] The task-system AppBar is shared by exactly 清单、四象限、日程.
- [ ] 我的 remains an independent account page with upper-right approval and Web QR actions.
- [ ] Four bottom destinations remain unchanged and no fifth destination exists.
- [ ] No task/sync/API/permission behavior was changed.
- [ ] No generic task card has an elevation or radius above the documented limit.
- [ ] Full Flutter verification and APK integrity checks are complete before reporting success.
