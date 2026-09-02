# My Tab Approval, Profile, and Device Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move task approvals to the Android “我的” AppBar, simplify the profile/workspace presentation, add editable user names, and make every successful SMS-login device trusted while retaining safe self-account device revocation.

**Architecture:** Task approvals remain `TaskApprovalRequest` records and are exposed through one Android approval-center entry on the “我的” tab. Device authorization records and their cryptographic challenge flow remain dormant future security design; this release migrates non-revoked devices to `ACTIVE`, creates new SMS-login devices as `ACTIVE`, and exposes only account-owned device revocation. The profile screen is split into personal profile, workspace match, user overview, and a compact device-management route; no avatar upload or new avatar storage is introduced.

**Tech Stack:** FastAPI, SQLAlchemy 2, Alembic, PostgreSQL, pytest; Flutter/Dart and Material 3; existing task approval, mobile session, workspace bootstrap, and device management APIs.

**Spec:** `docs/superpowers/specs/2026-09-02-my-tab-approval-device-profile-design.md`

## Global Constraints

- The Workspace has exactly two active members at most; task approval remains one requester and the opposite member as approver.
- The approval center is the only Android approval entry; the task-list “更多” menu must not contain task approval.
- SMS verification creates or restores an `ACTIVE` Android device; no device approval request is created in this release.
- A user may revoke only another device under the same account; the current device cannot be revoked and every revoke requires client confirmation.
- Existing default `CircleAvatar` remains the only avatar; no cat assets, random avatar generation, image upload, or object storage.
- Profile editing is limited to `display_name`; phone identity and device ownership are not editable.
- Web personal-profile editing is out of scope; task, Web login, sync, and participant-removal contracts must remain unchanged.
- Preserve soft revoke and audit rows; do not hard-delete device history or mobile sessions without recording revocation.
- Every task begins with a failing or contract-tightening test, runs focused tests red, implements the smallest change, runs focused tests green, then commits.

---

### Task 1: Lock Cross-Layer Contracts With Failing Tests

**Files:**
- Modify: `backend/tests/auth/test_mobile_sessions.py`
- Modify: `backend/tests/auth/test_mobile_sessions.py`
- Modify: `backend/tests/httpapi/test_device_management.py`
- Add: `backend/tests/httpapi/test_profile_routes.py`
- Add/modify: `backend/tests/db/test_trust_all_devices_migration.py`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`
- Modify: `client/test/screens/my_profile_screen_test.dart`
- Modify: `client/test/screens/my_profile_workspace_match_test.dart`
- Modify: `client/test/devices/device_management_test.dart`
- Add: `client/test/profile/profile_repository_test.dart`
- Add: `client/test/screens/profile_edit_screen_test.dart`

**Interfaces:**
- Backend tests define `PATCH /api/v1/me` accepting only `display_name`, SMS verification returning `device_status=VERIFIED` for first and subsequent devices, and migration behavior for legacy `PENDING` devices.
- Flutter tests define stable keys `profile-approval-center`, `profile-web-qr-login`, `profile-device-management`, `profile-edit-name`, `profile-workspace-match`, and `profile-partner-avatar`.

- [ ] **Step 1: Add red backend contract tests.** Assert that a second distinct device verified by SMS is `VERIFIED` and `can_write=true`; assert `PATCH /api/v1/me` updates and returns the trimmed display name, rejects unknown fields with the normal validation envelope, and rejects an overlong name.
- [ ] **Step 2: Add red device safety tests.** Assert current-device revoke returns the existing `approval_not_allowed`/`device_not_active` error, another same-account device is revocable, another-user device is rejected, and active sessions for the revoked device are revoked.
- [ ] **Step 3: Add red migration tests.** Seed `PENDING`, `ACTIVE`, `REVOKED` devices and pending authorization requests; assert upgrade converts only non-revoked pending devices to active, expires old pending authorization requests, and preserves revoked devices and audit rows.
- [ ] **Step 4: Add red Flutter widget tests.** Assert the list “更多” popup has no “任务审批”, the “我的” AppBar exposes approval and Web QR actions, profile content has a compact device-management entry rather than the full device list, unmatched workspaces render a placeholder avatar with “匹配中”, matched workspaces render the partner avatar, and the profile edit action submits a name.
- [ ] **Step 5: Run focused tests red.** Use the repository PostgreSQL test target, `flutter test` for the added/modified files, and record expected failures before production edits.
- [ ] **Step 6: Commit the contract tests.**

```bash
git add backend/tests client/test
git commit -m "test: define profile and trusted-device contracts"
```

### Task 2: Make SMS-Login Devices Trusted and Migrate Existing Devices

**Files:**
- Modify: `backend/app/auth/service.py`
- Modify: `backend/app/workspaces/bootstrap_schemas.py`
- Add: `backend/alembic/versions/0006_trust_sms_devices.py`
- Modify: `backend/tests/auth/test_mobile_sessions.py`
- Add/modify: `backend/tests/db/test_trust_all_devices_migration.py`

**Interfaces:**
- `SmsAuthService.verify_otp(...)` must create a new `AndroidDevice` with `DeviceStatus.ACTIVE`, set `enrolled_at`, and return `can_write=True`.
- `device_status_for_device_count` must return `DeviceStatus.ACTIVE` for every non-negative device count; update its existing domain test accordingly.
- Alembic head becomes `0006_trust_sms_devices`, with `down_revision = "0005_remove_task_assignees"`.

- [ ] **Step 1: Change the SMS enrollment test expectation.** Add a second-device verification fixture and assert both devices are `ACTIVE`; run it to confirm the current count-based implementation fails.
- [ ] **Step 2: Replace count-based status selection.** Set newly created SMS devices to `DeviceStatus.ACTIVE`, set `enrolled_at=now`, and keep revoked-device replay rejection unchanged.
- [ ] **Step 3: Implement the migration.** Within one transaction, update non-revoked `PENDING` devices to `ACTIVE`, set missing enrollment timestamps, and mark `PENDING` device authorization requests as `EXPIRED` with an expiration timestamp no later than `now`. Leave `REVOKED` devices, sessions, and audit data intact.
- [ ] **Step 4: Run focused backend tests.**

```bash
docker run --rm --network container:muyu-task1-postgres \
  -e TEST_DATABASE_URL=postgresql+psycopg://muyu:muyu-task1-password@localhost:5432/muyu_task1 \
  -e PYPI_INDEX_URL=http://mirrors.aliyun.com/pypi/simple/ \
  -v "$PWD/backend:/src" -w /src \
  m.daocloud.io/docker.io/library/python:3.12-slim \
  sh -c 'pip install --disable-pip-version-check -i "$PYPI_INDEX_URL" --trusted-host mirrors.aliyun.com -e ".[dev]" && python -m pytest -q tests/auth/test_mobile_sessions.py tests/db/test_trust_all_devices_migration.py'
```

- [ ] **Step 5: Commit trusted-device behavior.**

```bash
git add backend/app backend/alembic backend/tests
git commit -m "feat: trust devices verified by SMS"
```

### Task 3: Add the Current-User Display-Name API

**Files:**
- Modify: `backend/app/auth/schemas.py`
- Modify: `backend/app/auth/routes.py`
- Add: `backend/app/auth/profile.py`
- Do not modify: `backend/app/db/models.py`; the existing `users.display_name` column is sufficient
- Add/modify: `backend/tests/httpapi/test_profile_routes.py`

**Interfaces:**
- Add `ProfileUpdateRequest` with `ConfigDict(extra="forbid")` and `display_name: str | None` limited to the selected server maximum (120 characters to match `users.display_name`).
- Add `PATCH /api/v1/me` protected by `require_active_mobile_principal`; trim the value, persist it on the authenticated `User`, and return `MobileUserResponse`.
- Add `ProfileService.update_display_name(session: Session, user_id: UUID, display_name: str | None) -> User` in `backend/app/auth/profile.py`; it locks the user row, stores the trimmed value, and returns the updated user.
- Do not accept `phone`, `avatar_key`, `user_id`, or arbitrary profile fields.

- [ ] **Step 1: Add API tests.** Cover trimmed names, clearing a name, maximum length, unknown fields, unauthenticated access, and a revoked-device principal.
- [ ] **Step 2: Run the profile tests red.**
- [ ] **Step 3: Implement the schema, service mutation, route, and response wiring.** Commit updates to `display_name` using the existing SQLAlchemy session and API error envelope; do not touch phone identity or avatar storage.
- [ ] **Step 4: Run auth/profile tests green and verify login/refresh responses still serialize.**
- [ ] **Step 5: Commit the API.**

```bash
git add backend/app/auth backend/tests/httpapi/test_profile_routes.py
git commit -m "feat: allow users to edit display names"
```

### Task 4: Wire Flutter Profile Repository and Session Updates

**Files:**
- Modify: `client/lib/auth/mobile_auth_repository.dart`
- Modify: `client/lib/auth/mobile_session_store.dart`
- Modify: `client/lib/models/user.dart`
- Add: `client/lib/profile/profile_repository.dart`
- Add/modify: `client/test/profile/profile_repository_test.dart`

**Interfaces:**
- Add `ProfileRepository.updateDisplayName(String? displayName): Future<User>`.
- `HttpProfileRepository` sends `PATCH /api/v1/me` with `{ "display_name": value }` and parses `User`.
- `MobileSessionStore.replaceUser(User user): Future<void>` replaces only `MobileSession.user`; it preserves access token, refresh token, device ID, and expiry.

- [ ] **Step 1: Add repository and session-store tests.** Assert exact method/path/body, error propagation, and token/device preservation after replacing the user.
- [ ] **Step 2: Run focused Flutter tests red.**
- [ ] **Step 3: Implement the repository and a session replacement method.** Keep `User.nickname` as the client display alias while mapping the wire `display_name` field; retain the existing default avatar fallback.
- [ ] **Step 4: Run format and focused tests.**

```bash
cd client
dart format --output=none --set-exit-if-changed lib test
flutter test test/profile/profile_repository_test.dart test/auth/mobile_login_controller_test.dart
```

- [ ] **Step 5: Commit the Flutter profile data layer.**

```bash
git add client/lib client/test
git commit -m "feat: add mobile profile name repository"
```

### Task 5: Rebuild the Android “我的” Page Information Architecture

**Files:**
- Modify: `client/lib/screens/my_profile_screen.dart`
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Add: `client/lib/screens/profile_edit_screen.dart`
- Modify: `client/lib/screens/device_management_screen.dart`
- Do not modify: `client/lib/screens/task_approval_screen.dart`; preserve its existing task-approval behavior and navigate to it from the My-tab AppBar callback.
- Modify: `client/test/screens/my_profile_screen_test.dart`
- Modify: `client/test/screens/my_profile_workspace_match_test.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`
- Add/modify: `client/test/screens/profile_edit_screen_test.dart`
- Modify: `client/test/devices/device_management_test.dart`

**Interfaces:**
- `MyProfileScreen` receives `ProfileRepository`, existing `DeviceManagementRepository`, `WorkspaceSyncController`, and callbacks for approval/Web QR navigation.
- `CloudWorkspaceScreen` exposes approval and Web QR actions only while `_selectedDestination == 3`; it removes `_TaskListMenuAction.approvals` and its popup item.
- `DeviceManagementScreen` remains a dedicated route and accepts the current-device ID through the repository’s server-derived `is_current` flag.

- [ ] **Step 1: Implement the list-menu regression.** Remove the approval enum branch, popup item, and handler; remove the existing top-level task approval action from 清单、四象限和日程, so the only visible entry is the “我的” AppBar action.
- [ ] **Step 2: Implement the new profile sections.** Split the current large account card into personal profile, workspace match, overview, and a compact `设备管理` ListTile with device count/status.
- [ ] **Step 3: Implement profile editing.** Add a name edit dialog/screen using `ProfileRepository`; on success update `MobileSessionStore` and rebuild the profile. Keep the current default `CircleAvatar` for both current and placeholder partner avatars.
- [ ] **Step 4: Implement matching states.** Always render the second avatar slot; show default placeholder plus “匹配中” when `member_count < 2`; show the actual partner only for the other ACTIVE member; disable placeholder taps.
- [ ] **Step 5: Route device management.** Remove full device tiles and device authorization sections from the profile body; navigate to the dedicated device screen. Keep current-device protection and the existing confirmation dialog.
- [ ] **Step 6: Wire My AppBar actions.** Show approval-center and Web QR buttons side-by-side with stable keys `profile-approval-center` and `profile-web-qr-login`; use the task approval pending count for the badge.
- [ ] **Step 7: Run focused widget tests green.**

```bash
cd client
dart format --output=none --set-exit-if-changed lib test
flutter test test/screens/cloud_workspace_screen_test.dart \
  test/screens/my_profile_screen_test.dart \
  test/screens/my_profile_workspace_match_test.dart \
  test/screens/profile_edit_screen_test.dart \
  test/devices/device_management_test.dart
```

- [ ] **Step 8: Commit the Android information architecture.**

```bash
git add client/lib client/test
git commit -m "feat: simplify My tab and centralize approvals"
```

### Task 6: Update Bootstrap/Auth Fixtures and API Documentation

**Files:**
- Modify: `backend/app/workspaces/bootstrap_service.py` for matching-status payload coverage
- Modify: `backend/app/workspaces/bootstrap_schemas.py` for matching-status contract coverage
- Modify: `client/lib/workspace/workspace_bootstrap_repository.dart` for a stable placeholder/match helper
- Modify: `docs/01-product.md`, `docs/03-roadmap.md`, `docs/05-development-status.md`
- Add: `docs/superpowers/superseded/2026-09-02-device-approval-task-design-note.md` recording the deferred taskized device-approval design

**Interfaces:**
- Bootstrap continues to return `match_status`, active member count, member names, masked phones, and current-member flags.
- No avatar field is required in the current wire contract; clients use the existing default avatar fallback.

- [ ] **Step 1: Add/adjust bootstrap contract tests.** Verify zero/one member renders `waiting_partner`, two active members renders `matched`, and no phantom partner identity is emitted.
- [ ] **Step 2: Update active documentation.** Record the My-tab-only approval entry, trusted-by-SMS device rule, device revoke confirmation, profile-name-only editing, and the dormant future device-approval design.
- [ ] **Step 3: Run documentation consistency searches.** Ensure no active document says SMS-added devices require approval or that the task-list menu owns approvals.
- [ ] **Step 4: Commit documentation and fixture updates.**

```bash
git add backend/app/workspaces client/lib/workspace docs
git commit -m "docs: record trusted-device profile boundaries"
```

### Task 7: Full Verification, Migration Smoke Test, and Commit-Named APK

**Files:**
- No planned production changes; only verification output and ignored build artifacts.
- Update: `.superpowers/sdd/2026-09-02-my-tab-approval-device-profile/progress.md` as the execution ledger.

- [ ] **Step 1: Run backend full tests with the Aliyun mirror.**

```bash
make backend-test TEST_DOCKER_NETWORK=container:muyu-task1-postgres \
  TEST_DATABASE_URL=postgresql+psycopg://muyu:muyu-task1-password@localhost:5432/muyu_task1 \
  PYPI_INDEX_URL=http://mirrors.aliyun.com/pypi/simple/
```

- [ ] **Step 2: Run Flutter verification.**

```bash
cd client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

- [ ] **Step 3: Run Web regression verification.**

```bash
cd ../web
npm run typecheck
npm test -- --run
npm run build
```

- [ ] **Step 4: Run repository boundary checks.**

```bash
cd ..
./scripts/assert-no-legacy-runtime.sh
./scripts/assert-client-boundary.sh
./scripts/check-deployment.sh
git diff --check
```

- [ ] **Step 5: Upgrade a clean PostgreSQL schema to head.** Assert Alembic reaches `0006_trust_sms_devices`, `task_assignees` remains absent, `task_approval_request_type` retains exactly the seven supported task values, non-revoked devices are active, and no non-deleted task has a null owner.
- [ ] **Step 6: Build the local APK using the final commit short SHA and online API.**

```bash
cd client
final_commit=$(git rev-parse --short HEAD)
API_BASE_URL=https://muyu.bkverse.space ./scripts/build-android-debug.sh
test -s "build/app/outputs/flutter-apk/Muyu-${final_commit}.apk"
unzip -tq "build/app/outputs/flutter-apk/Muyu-${final_commit}.apk"
```

- [ ] **Step 7: Verify APK contents and device availability.** Confirm the file is an Android package and contains `https://muyu.bkverse.space`; record SHA-256. Run install/launch/authenticated smoke checks when `adb devices` reports an attached device; otherwise record the physical-device verification gap explicitly.
- [ ] **Step 8: Review the final diff and commit history.** Confirm no avatar-upload code, device-approval runtime path, taskized device rows, or unrelated Web changes were introduced.
- [ ] **Step 9: Record final verification and stop before release.** Do not push, tag, or publish unless separately instructed.

## Acceptance Checklist

- [ ] Only “我的” AppBar exposes the approval center and Web QR actions.
- [ ] Clean-list “更多” contains no task approval item.
- [ ] SMS verification makes first and subsequent devices `ACTIVE` and writable.
- [ ] Existing non-revoked pending devices migrate to `ACTIVE`; old pending authorization requests expire.
- [ ] Device management is compact on “我的”; other devices require confirmation before revoke; current device cannot be revoked.
- [ ] Personal profile edits only the display name and preserves the existing default avatar.
- [ ] Unmatched workspace shows a default placeholder avatar and “匹配中”; matched workspace shows the other active member.
- [ ] Task approvals, task ownership, Web QR login, task statistics, and participant-free contracts remain passing.
- [ ] Full backend, Flutter, Web, migration, boundary, and APK verification passes; any missing physical-device run is explicitly disclosed.
