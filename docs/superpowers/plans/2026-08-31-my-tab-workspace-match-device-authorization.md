# “我的”页双人匹配与设备授权实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将共享空间双人匹配关系、设备验证请求和审批入口接入 Android “我的”页，并让未验证设备在不阻塞读取的前提下自动发起幂等验证请求。

**Architecture:** FastAPI 在现有 workspace bootstrap 响应中增加双人成员最小投影，在现有 device authorization 资源上增加请求列表、幂等创建和拒绝动作。Flutter 通过既有 bootstrap/device repository 加载匹配关系和设备状态，在“我的”页使用下拉刷新展示请求并复用现有签名审批流程；CloudWorkspaceScreen 在未验证设备进入共享空间时自动触发一次请求创建。

**Tech Stack:** Python 3.12、FastAPI、SQLAlchemy、Pydantic、PostgreSQL、Flutter/Dart、Flutter widget tests、pytest。

**Spec:** `docs/superpowers/specs/2026-08-31-my-tab-workspace-match-device-authorization-design.md`

## Global Constraints

- 一个 workspace 最多两个有效 membership，成员状态只在同一 workspace 内投影。
- 设备状态继续使用 `UNVERIFIED`、`VERIFIED`、`REVOKED`，未验证设备只能读。
- 当前设备不能撤销自己；设备列表不包含 Web 临时 session。
- 设备验证必须由另一位用户的已验证 Android 设备签名批准。
- 服务端只返回脱敏手机号、设备标签和状态，不返回私钥、公钥或 OTP。
- 同一 pending device 只能有一条有效的 pending authorization request。
- 现有 API 与 Flutter 测试必须保持通过。
- 用户已经授权直接在当前 `main` 分支施工，本计划不创建 worktree。

---

### Task 1: 增加 workspace 双人成员投影

**Files:**
- Modify: `backend/app/workspaces/bootstrap_schemas.py`
- Modify: `backend/app/workspaces/bootstrap_service.py`
- Test: `backend/tests/httpapi/test_workspace_bootstrap_flow.py`
- Test: `backend/tests/httpapi/test_workspace_bootstrap.py`

**Interfaces:**
- Produces `BootstrapMember(user_id, display_name, phone_masked, member_slot, membership_status, is_current)`。
- Extends `BootstrapWorkspace` with `match_status` (`waiting_partner`, `matched`, `error`) and `members`。
- Keeps `WorkspaceBootstrapService.get_state()` and all HTTP paths unchanged。

- [ ] **Step 1: Write the failing API test**

在 `test_workspace_bootstrap_flow.py` 增加测试，创建一位 owner 和一位 partner，分别请求 bootstrap，断言：

```python
body = client.get("/api/v1/workspaces/bootstrap", headers=_headers(owner)).json()
assert body["workspace"]["match_status"] == "matched"
assert body["workspace"]["member_count"] == 2
assert [item["member_slot"] for item in body["workspace"]["members"]] == [1, 2]
assert body["workspace"]["members"][0]["is_current"] is True
assert body["workspace"]["members"][1]["phone_masked"].endswith("0169")
```

在一位成员的 bootstrap 测试中断言 `match_status == "waiting_partner"`、`len(members) == 1`。

- [ ] **Step 2: Run tests and verify the expected failure**

Run:

```bash
cd backend && pytest -q tests/httpapi/test_workspace_bootstrap_flow.py tests/httpapi/test_workspace_bootstrap.py
```

Expected: FAIL because `BootstrapWorkspace` does not yet expose `match_status` or `members`。

- [ ] **Step 3: Implement the projection**

在 `bootstrap_schemas.py` 新增 `BootstrapMember`，并为 `BootstrapWorkspace` 增加：

```python
match_status: Literal["waiting_partner", "matched", "error"]
members: list[BootstrapMember]
```

在 `WorkspaceBootstrapService._workspace_payload(workspace, viewer_user_id)` 中按 `member_slot` 查询 active memberships，再查询对应 `User`，使用已有 `_mask_phone` 构造成员投影。成员数小于 2 时返回 `waiting_partner`，等于 2 时返回 `matched`，超过 2 时返回 `error`。更新 `_state_for_user()` 的所有调用点传入当前用户 ID。

- [ ] **Step 4: Run the focused tests**

Run the command from Step 2. Expected: PASS，包括旧 bootstrap 测试和新成员投影测试。

- [ ] **Step 5: Commit**

```bash
git add backend/app/workspaces/bootstrap_schemas.py backend/app/workspaces/bootstrap_service.py backend/tests/httpapi/test_workspace_bootstrap_flow.py backend/tests/httpapi/test_workspace_bootstrap.py
git commit -m "feat: expose workspace member matching state"
```

### Task 2: 完成设备验证请求的列表、幂等创建与拒绝

**Files:**
- Modify: `backend/app/devices/routes.py`
- Modify: `backend/app/workspaces/service.py`
- Modify: `backend/app/devices/schemas.py`
- Test: `backend/tests/httpapi/test_device_management.py`
- Test: `backend/tests/httpapi/test_device_readonly_permissions.py`

**Interfaces:**
- `GET /api/v1/devices/authorization-requests` accepts a mobile principal; pending devices only see their own outgoing requests, active devices see same-workspace incoming/outgoing requests。
- Request items include `candidate_device_id`, `candidate_device_label`, `candidate_platform`, `candidate_user_id`, `candidate_phone_masked`, `requester_user_id`, `requester_phone_masked`, `is_incoming`, `status`, `created_at`, `expires_at`。
- `POST /api/v1/devices/authorization-requests` returns the existing pending request for the same pending device instead of inserting a duplicate。
- Adds `POST /api/v1/devices/authorization-requests/{request_id}/reject` for the other active workspace member。

- [ ] **Step 1: Write failing backend tests**

在 `test_device_management.py` 增加：

```python
def test_authorization_request_is_idempotent_and_visible_to_both_members(db_engine):
    client = _client(db_engine)
    owner, partner = _ready_workspace(client)
    pending = _login(client, "+8615028180169", "BwgJ")
    first = client.post("/api/v1/devices/authorization-requests", headers=_headers(pending), json={"public_key": "BwgJ", "label": "Pixel 9"})
    second = client.post("/api/v1/devices/authorization-requests", headers=_headers(pending), json={"public_key": "BwgJ", "label": "Pixel 9"})
    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    incoming = client.get("/api/v1/devices/authorization-requests", headers=_headers(owner))
    outgoing = client.get("/api/v1/devices/authorization-requests", headers=_headers(pending))
    assert incoming.json()[0]["is_incoming"] is True
    assert outgoing.json()[0]["is_incoming"] is False
    assert incoming.json()[0]["candidate_device_label"] == "Pixel 9"
```

增加测试验证 active 设备可以拒绝另一位用户的 pending request，拒绝后请求状态为 `REJECTED`，候选设备仍为 `PENDING`；pending 设备不能读取他人的 incoming 请求。

- [ ] **Step 2: Run the tests and verify they fail for missing behavior**

```bash
cd backend && pytest -q tests/httpapi/test_device_management.py tests/httpapi/test_device_readonly_permissions.py
```

Expected: FAIL because duplicate requests are inserted, request metadata is absent, and the reject route does not exist。

- [ ] **Step 3: Implement request projection and idempotency**

新增 Pydantic response schema或等价的明确构造函数，统一生成请求字典。列表接口改用 `require_mobile_principal`：

- 有 workspace 且 principal device 为 pending 时，仅查询 `candidate_device_id == principal.device_id`。
- active principal 查询该 workspace 的全部请求，并通过候选设备用户 ID计算 `is_incoming`。
- 查询候选设备和用户以返回标签、平台、脱敏手机号。
- pending 请求过期时在投影中返回 `EXPIRED`，不修改历史记录。

创建接口在生成新 request 前锁定并查询同一 candidate device 的有效 pending request；找到时复用它并返回原 ID。首次创建继续返回 6 位安全码，服务端只持久化摘要。

- [ ] **Step 4: Implement reject authorization**

在 `WorkspaceService` 新增 `reject(request_id, approving_device_id)`：复用 pending request 校验，要求审批设备为 active、候选设备用户与审批用户不同且双方均为该 workspace active member；将 request 状态设为 `REJECTED`。在 routes 增加 reject 路由和错误映射，候选设备保持 `PENDING`、membership 保持当前状态。

- [ ] **Step 5: Run focused and regression tests**

```bash
cd backend && pytest -q tests/httpapi/test_device_management.py tests/httpapi/test_device_readonly_permissions.py tests/httpapi/test_workspace_bootstrap_flow.py tests/workspaces/test_onboarding.py
```

Expected: PASS，既有设备撤销、自审批拒绝、邀请审批和只读权限测试全部通过。

- [ ] **Step 6: Commit**

```bash
git add backend/app/devices/routes.py backend/app/devices/schemas.py backend/app/workspaces/service.py backend/tests/httpapi/test_device_management.py backend/tests/httpapi/test_device_readonly_permissions.py
git commit -m "feat: expose and control device authorization requests"
```

### Task 3: 扩展 Flutter bootstrap 与设备授权 repository

**Files:**
- Modify: `client/lib/workspace/workspace_bootstrap_repository.dart`
- Modify: `client/lib/workspace/device_authorization_repository.dart`
- Test: `client/test/workspace/workspace_bootstrap_repository_test.dart`
- Test: `client/test/screens/web_qr_scanner_screen_test.dart`

**Interfaces:**
- Adds `WorkspaceMemberSummary` and `WorkspaceMatchStatus` to `WorkspaceSummary`。
- `DeviceAuthorizationRequest` gains nullable request metadata and `createdAt` while preserving existing QR-login fields。
- `DeviceAuthorizationRepository` gains `Future<List<DeviceAuthorizationRequest>> listRequests()` and `Future<void> reject(String requestId)`。
- Existing `createDeviceRequest`, `beginApproval`, `approve`, `scanWebQr`, `approveWebLogin` signatures remain valid。

- [ ] **Step 1: Write failing parsing/repository tests**

在 bootstrap repository 测试中解析包含 `match_status`、`members` 的 JSON，并断言当前成员和对方脱敏手机号。在设备授权测试中用 `MockClient` 断言 GET 请求解析 `is_incoming` 和候选设备字段，并断言 reject 使用 POST 路径。

- [ ] **Step 2: Run focused Dart tests and verify failure**

```bash
cd client && flutter test test/workspace/workspace_bootstrap_repository_test.dart test/screens/web_qr_scanner_screen_test.dart
```

Expected: FAIL because the new fields and repository methods do not exist。

- [ ] **Step 3: Implement model parsing**

为新增字段提供默认值以兼容旧缓存和现有测试 fixture；未知匹配状态解析为 `error`，未知请求元数据保持 null。保持 `DeviceAuthorizationRequest.fromJson` 对 Web QR response 的兼容。

- [ ] **Step 4: Implement HTTP repository methods**

`listRequests()` 请求 `/api/v1/devices/authorization-requests`，校验数组并映射请求；`reject()` 请求 `/api/v1/devices/authorization-requests/{id}/reject`，将 `ApiException` 转成 `DeviceAuthorizationFailure`。

- [ ] **Step 5: Run focused tests**

Run the command from Step 2. Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/workspace/workspace_bootstrap_repository.dart client/lib/workspace/device_authorization_repository.dart client/test/workspace/workspace_bootstrap_repository_test.dart client/test/screens/web_qr_scanner_screen_test.dart
git commit -m "feat: model workspace matching and authorization requests"
```

### Task 4: 重构 Android “我的”页并接通验证流程

**Files:**
- Modify: `client/lib/screens/my_profile_screen.dart`
- Modify: `client/lib/screens/cloud_workspace_screen.dart`
- Modify: `client/lib/screens/workspace_gate.dart`
- Modify: `client/lib/screens/device_approval_screen.dart`
- Modify: `client/test/screens/my_profile_screen_test.dart`
- Modify: `client/test/screens/cloud_workspace_screen_test.dart`
- Create: `client/test/screens/my_profile_workspace_match_test.dart`

**Interfaces:**
- `MyProfileScreen` accepts optional `WorkspaceBootstrapRepository`, `DeviceAuthorizationRepository`, and `DeviceSigningKey` dependencies; old constructor usages remain valid。
- `CloudWorkspaceScreen` accepts an optional workspace bootstrap repository and passes it to the profile page。
- An unverified cloud workspace screen invokes `createDeviceRequest(publicKey)` once per screen initialization; failures are retained as request state and do not block task reading。

- [ ] **Step 1: Write failing widget tests**

新增 widget test 注入 fake bootstrap、device、authorization repository，断言：

```dart
expect(find.text('共享空间'), findsOneWidget);
expect(find.text('已匹配 · 2/2 位成员'), findsOneWidget);
expect(find.text('+86******0169'), findsOneWidget);
expect(find.text('待处理的设备验证'), findsOneWidget);
expect(find.text('Pixel 9'), findsOneWidget);
expect(find.byKey(const Key('profile-approve-device-request')), findsOneWidget);
```

点击批准后断言 fake repository 收到 `beginApproval` 与 `approve`；点击拒绝后断言收到 `reject`。增加未验证 CloudWorkspaceScreen 测试，断言进入页面会调用一次 `createDeviceRequest`。

- [ ] **Step 2: Run widget tests and verify failure**

```bash
cd client && flutter test test/screens/my_profile_screen_test.dart test/screens/cloud_workspace_screen_test.dart test/screens/my_profile_workspace_match_test.dart
```

Expected: FAIL because the profile has no workspace/request sections or approval actions。

- [ ] **Step 3: Implement profile data loading and refresh**

将页面加载状态从单独的 `_devices` Future 改为 profile aggregate Future：并行加载设备、bootstrap 和 request list；可选依赖不存在时保持旧设备页行为。使用 `RefreshIndicator` 包裹列表，进入页面、AppBar refresh 和下拉刷新都重新加载。网络失败保留稳定错误文案，不清空账号或已有匹配展示。

- [ ] **Step 4: Implement matching and request UI**

在账号信息下方增加共享空间匹配卡片：显示 `waiting_partner`、`matched` 或 `error`，列出“我”和“对方”的成员投影。设备卡片展示“已验证 · 可读写”“未验证 · 只读”“已撤销”，当前设备继续只显示不可操作的 Chip。新增“我发起的设备验证”和“待处理的设备验证”卡片。

- [ ] **Step 5: Implement approve/reject actions**

批准动作调用 `beginApproval`，使用注入的 `DeviceSigningKey` 对返回的 `signaturePayload` 调用现有 `approve`；完成后刷新页面。拒绝动作调用新 `reject` 方法并刷新。未提供 signing key 时禁用批准按钮并显示明确提示，不崩溃。

- [ ] **Step 6: Wire dependencies and automatic request creation**

`WorkspaceGate` 将 `workspaceBootstrapRepository` 传给 `CloudWorkspaceScreen`。Cloud screen 构造 profile 时传入 `HttpDeviceAuthorizationRepository`、bootstrap repository 和 signing key。`initState` 在 `session != null && !canWrite` 时获取公钥并调用 `createDeviceRequest`；捕获 409/网络错误，不影响共享空间和只读任务页面。

- [ ] **Step 7: Run widget tests and static checks**

```bash
cd client && dart format lib/screens/my_profile_screen.dart lib/screens/cloud_workspace_screen.dart lib/screens/workspace_gate.dart lib/screens/device_approval_screen.dart test/screens/my_profile_screen_test.dart test/screens/cloud_workspace_screen_test.dart test/screens/my_profile_workspace_match_test.dart
flutter analyze
flutter test test/screens/my_profile_screen_test.dart test/screens/cloud_workspace_screen_test.dart test/screens/my_profile_workspace_match_test.dart test/screens/web_qr_scanner_screen_test.dart
```

Expected: format clean, analyzer 0 errors, focused widget tests PASS。

- [ ] **Step 8: Commit**

```bash
git add client/lib/screens/my_profile_screen.dart client/lib/screens/cloud_workspace_screen.dart client/lib/screens/workspace_gate.dart client/lib/screens/device_approval_screen.dart client/test/screens/my_profile_screen_test.dart client/test/screens/cloud_workspace_screen_test.dart client/test/screens/my_profile_workspace_match_test.dart
git commit -m "feat: show workspace matching in Android profile"
```

### Task 5: 集成验证、APK 构建与施工记录

**Files:**
- Modify: `docs/superpowers/specs/2026-08-31-my-tab-workspace-match-device-authorization-design.md` only if implementation deviations are discovered and approved by the code behavior。
- Modify: `docs/superpowers/plans/2026-08-31-my-tab-workspace-match-device-authorization.md` to mark completed steps。

- [ ] **Step 1: Run backend regression suite**

```bash
cd backend && pytest -q
```

Expected: exit code 0 and no failures。

- [ ] **Step 2: Run Flutter regression suite**

```bash
cd client && flutter test
```

Expected: exit code 0 and no failures。

- [ ] **Step 3: Run integration checks for the two-person flow**

Run the existing Android/backend flow tests that cover first login, invite acceptance, pending device read-only access, request approval and post-approval write access. Verify the new bootstrap member fields and request list metadata in the same flow.

- [ ] **Step 4: Build the local commit-named debug APK**

```bash
cd client
commit_id=$(git rev-parse --short HEAD)
flutter build apk --debug
cp build/app/outputs/flutter-apk/app-debug.apk "build/app/outputs/flutter-apk/Muyu-${commit_id}.apk"
```

Verify the copied artifact exists and is non-empty. CI release naming remains separate and is not changed by this task.

- [ ] **Step 5: Update the plan and commit the implementation record**

Mark every completed checkbox in this plan, record test commands and APK path in the final response, then commit only the documentation update:

```bash
git add docs/superpowers/plans/2026-08-31-my-tab-workspace-match-device-authorization.md
git commit -m "docs: record workspace matching implementation"
```
