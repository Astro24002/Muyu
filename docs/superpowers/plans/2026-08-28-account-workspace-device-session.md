# 账号、双人 Workspace 与设备会话 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将首次登录双人绑定、首台设备自动验证、后续设备只读审批和独立 Web 临时会话落地到 FastAPI、Flutter Android 与 Web 客户端。

**Architecture:** 两个手机号对应两个独立 `User`，通过最多两个成员槽位绑定到一个 Workspace。AndroidDevice 是持久设备并负责读写能力，WebSession 是最长 18 小时的临时访问会话，两者不共享设备注册或撤销数据。读取使用允许未验证设备的主体依赖，写入继续使用已验证设备主体依赖。

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy, Alembic, PostgreSQL, Flutter/Dart Android, TypeScript + Vite, Vitest, pytest。

**Spec:** `docs/superpowers/specs/2026-08-28-account-workspace-device-session-design.md`

## Global Constraints

- 首版只实现 Android、Web 和 FastAPI；不添加 iOS、Flutter Web 或账号密码登录。
- 用户手机号数据库统一使用 E.164；11 位中国大陆号码在 API 边界补全 `+86`。
- Workspace 最多两个成员；每个用户最多属于一个未归档 Workspace。
- Android 首台设备自动 `ACTIVE`；后续设备 `PENDING`，未验证设备只读。
- Web 不创建 AndroidDevice，只创建最长 18 小时的 WebSession。
- 当前 Android 设备不能删除或撤销自己；后端必须强制拒绝。
- 所有写接口保留 request_id 幂等和服务端权限校验；不能依赖客户端按钮禁用。
- 不把 OTP、token、Cookie、browser proof、设备签名或手机号明文写入日志。

---

### Task 1: 锁定领域契约与数据库清理策略

**Files:**
- Create: `backend/app/workspaces/bootstrap_schemas.py`
- Modify: `backend/app/db/enums.py`
- Modify: `backend/app/db/models.py`
- Create: `backend/alembic/versions/0002_workspace_device_session_indexes.py`
- Test: `backend/tests/domain/test_workspace_device_session_contract.py`

**Interfaces:**
- Produces `BootstrapState` values `NEEDS_PARTNER`, `WAITING_FOR_PARTNER`, `INVITED`, `READY`.
- Produces public device status mapping `PENDING -> UNVERIFIED`, `ACTIVE -> VERIFIED`, `REVOKED -> REVOKED`.
- Keeps persisted `DeviceStatus` and `WebSessionStatus` compatible with existing rows.

- [x] **Step 1: Write failing contract tests**

测试必须断言：首台设备状态为 `ACTIVE`；第二台设备状态为 `PENDING`；公开响应使用 `UNVERIFIED/VERIFIED`；WebSession 不出现在设备列表；当前设备撤销返回固定错误码。

- [x] **Step 2: Run tests to verify the contract fails**

Run: `cd backend && pytest -q tests/domain/test_workspace_device_session_contract.py`

Expected: FAIL because bootstrap states/public mapping and current-device revoke contract are not yet exposed.

- [x] **Step 3: Implement schemas and minimal database support**

在独立 schema 文件中定义 Pydantic 响应模型和设备状态映射。只在确有需要时为 `web_sessions(status, expires_at)`、`web_login_challenges(status, expires_at)` 增加复合索引；不新增 WebDevice 表，不修改现有主键或 Workspace 槽位约束。

- [x] **Step 4: Run focused tests and migration checks**

Run: `cd backend && pytest -q tests/domain/test_workspace_device_session_contract.py && python -m compileall -q app`

Expected: PASS; Alembic upgrade/downgrade 在临时 PostgreSQL 上成功。

- [x] **Step 5: Commit**

```bash
git add backend/app/db backend/app/workspaces/bootstrap_schemas.py backend/alembic/versions backend/tests/domain/test_workspace_device_session_contract.py
git commit -m "feat: define workspace device and web session contracts"
```

### Task 2: 实现首次登录 Workspace bootstrap 与伙伴绑定

**Files:**
- Create: `backend/app/workspaces/bootstrap_service.py`
- Modify: `backend/app/workspaces/routes.py`
- Modify: `backend/app/workspaces/schemas.py`
- Modify: `backend/app/auth/service.py`
- Test: `backend/tests/httpapi/test_workspace_bootstrap_flow.py`

**Interfaces:**
- `WorkspaceBootstrapService.get_state(principal) -> BootstrapPayload`
- `WorkspaceBootstrapService.bind_partner(actor_user_id, phone, request_id) -> BootstrapPayload`
- `WorkspaceBootstrapService.accept_invite(invite_id, user_id, device_id, request_id) -> BootstrapPayload`

- [x] **Step 1: Write failing HTTP tests**

覆盖以下场景：

```python
from uuid import uuid4

def test_first_login_requires_partner_phone(client, first_device_token):
    response = client.get("/api/v1/workspaces/bootstrap", headers=first_device_token)
    assert response.status_code == 200
    assert response.json()["state"] == "NEEDS_PARTNER"

def test_bind_partner_creates_one_owner_and_pending_invite(client, first_device_token):
    response = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=first_device_token,
        json={"phone": "15028180169", "request_id": str(uuid4())},
    )
    assert response.status_code == 201
    assert response.json()["state"] == "WAITING_FOR_PARTNER"
    assert response.json()["workspace"]["member_count"] == 1

def test_partner_first_device_accepts_invite_without_device_approval(
    client, partner_token_headers, partner_device_id, invite_id
):
    response = client.post(
        f"/api/v1/workspace-invites/{invite_id}/accept",
        headers=partner_token_headers,
        json={"device_id": str(partner_device_id), "request_id": str(uuid4())},
    )
    assert response.status_code == 200
    assert response.json()["state"] == "READY"

def test_self_phone_and_second_workspace_are_rejected(client, first_device_token):
    response = client.post(
        "/api/v1/workspaces/bind-partner",
        headers=first_device_token,
        json={"phone": "13800138000", "request_id": str(uuid4())},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "partner_phone_must_differ"
```

断言创建后只有一个 slot 1 成员、邀请手机号是 E.164、重复 request_id 返回同一结果。

- [x] **Step 2: Run the tests to verify they fail**

Run: `cd backend && pytest -q tests/httpapi/test_workspace_bootstrap_flow.py`

Expected: FAIL because `/workspaces/bootstrap` and `/workspaces/bind-partner` do not exist and current invitation acceptance仍会创建设备审批请求。

- [x] **Step 3: Implement atomic bootstrap and binding**

在事务内锁定 actor user 与 Workspace 相关记录：检查用户现有成员、检查自绑定和已占用手机号，创建 Workspace、slot 1 ACTIVE 成员、WorkspaceCursor 和唯一有效邀请。绑定接口接受 `request_id`，重复请求返回已保存响应。

调整 `SmsAuthService.verify_otp`：设备是否首台由该用户已有 AndroidDevice 数量决定，不再用“是否已有 Workspace”作为唯一依据。首台设备为 `ACTIVE`，后续设备为 `PENDING`。

- [x] **Step 4: Implement invitation acceptance split**

邀请用户的首台设备直接创建 ACTIVE slot 2 成员；邀请用户使用 PENDING 第二台设备时，只激活成员关系并创建设备授权请求。邀请接受必须锁定 Workspace，确保最多两个成员。

- [x] **Step 5: Run focused and existing workspace tests**

Run: `cd backend && pytest -q tests/httpapi/test_workspace_bootstrap_flow.py tests/httpapi/test_workspace_bootstrap.py tests/domain/test_workspace_service.py`

Expected: PASS with no regression in workspace capacity, invite expiration and idempotency tests。

- [x] **Step 6: Commit**

```bash
git add backend/app/auth/service.py backend/app/workspaces backend/tests/httpapi/test_workspace_bootstrap_flow.py
git commit -m "feat: bootstrap two-person workspace binding"
```

### Task 3: 打通未验证设备的只读会话与写权限

**Files:**
- Modify: `backend/app/auth/service.py`
- Modify: `backend/app/auth/dependencies.py`
- Modify: `backend/app/auth/routes.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/app/sync/routes.py`
- Modify: `backend/app/devices/routes.py`
- Test: `backend/tests/httpapi/test_device_readonly_permissions.py`

**Interfaces:**
- `MobilePrincipal.device_status -> DeviceStatus`
- `MobilePrincipal.can_write -> bool`
- `require_mobile_principal` for bootstrap/read APIs。
- `require_active_mobile_principal` for every task mutation and approval API。

- [x] **Step 1: Write failing permission tests**

测试第二台 PENDING 设备可以刷新 token、GET bootstrap、GET snapshot 和 GET task，但 POST/PATCH/transition/comment/delay/resolve-conflict 返回 `403 device_not_verified`。测试已验证设备可写，REVOKED 设备不能刷新。

- [x] **Step 2: Run tests to verify failure**

Run: `cd backend && pytest -q tests/httpapi/test_device_readonly_permissions.py`

Expected: FAIL because refresh and current workspace still reject PENDING devices or return generic workspace errors。

- [x] **Step 3: Allow PENDING refresh and expose capability**

修改 refresh 只拒绝 `REVOKED`，返回当前 device status。`MobilePrincipal` 增加状态和能力字段；`/me`、bootstrap、snapshot 返回 `device.status` 与 `can_write`。

- [x] **Step 4: Apply service-level write guard**

保持所有写路由使用 `require_active_mobile_principal`，错误码固定为 `device_not_verified`。设备审批和 WebSession 撤销仍只允许 ACTIVE Android 设备。

- [x] **Step 5: Run full backend tests**

Run: `cd backend && pytest -q && python -m compileall -q app`

Expected: PASS；若默认数据库凭据不可用，使用项目规定的 disposable PostgreSQL URL 重跑并记录实际命令。

- [x] **Step 6: Commit**

```bash
git add backend/app/auth backend/app/tasks backend/app/sync backend/app/devices backend/tests/httpapi/test_device_readonly_permissions.py
git commit -m "feat: enforce verified-device write capability"
```

### Task 4: 设备列表、撤销和自我删除保护

**Files:**
- Modify: `backend/app/devices/routes.py`
- Modify: `backend/app/devices/service.py` (create if absent)
- Modify: `backend/app/db/models.py` only if audit relation is required
- Test: `backend/tests/httpapi/test_device_management.py`

**Interfaces:**
- `DeviceService.revoke(device_id, actor_user_id, actor_device_id) -> DeviceSummary`
- `DeviceService.list_for_user(user_id, current_device_id) -> list[DeviceSummary]`

- [x] **Step 1: Write failing tests**

覆盖：设备列表只包含 AndroidDevice；当前设备撤销返回 403；同账号其他设备可以撤销；撤销会使所有该设备 MobileSession 失效；重复撤销返回稳定 409；设备状态公开为两种主要状态。

- [x] **Step 2: Run tests to verify failure**

Run: `cd backend && pytest -q tests/httpapi/test_device_management.py`

Expected: FAIL because current routes没有撤销服务或无法区分 current device。

- [x] **Step 3: Implement revoke transaction**

服务层锁定目标设备，要求目标设备属于 actor_user_id 且 `target.id != actor_device_id`。更新为 `REVOKED`，设置 `revoked_at`，批量撤销目标设备的 MobileSession，并撤销其未完成授权请求。绝不物理删除 AndroidDevice。

- [x] **Step 4: Run focused tests and commit**

Run: `cd backend && pytest -q tests/httpapi/test_device_management.py tests/httpapi/test_device_readonly_permissions.py`

```bash
git add backend/app/devices backend/tests/httpapi/test_device_management.py
git commit -m "feat: add device revoke safeguards"
```

### Task 5: WebSession 独立管理与历史清理

**Files:**
- Modify: `backend/app/web_login/routes.py`
- Modify: `backend/app/web_login/service.py`
- Create: `backend/app/web_login/cleanup.py`
- Modify: `backend/app/devices/routes.py` to keep WebSession out of device list
- Test: `backend/tests/httpapi/test_web_session_management.py`
- Test: `backend/tests/domain/test_web_session_cleanup.py`

**Interfaces:**
- `WebSessionService.list_active(workspace_id) -> list[WebSessionSummary]`
- `WebSessionService.revoke(session_id, workspace_id, actor_device_id) -> None`
- `WebSessionService.revoke_all(workspace_id, actor_device_id) -> int`
- `purge_expired_sessions(session, now, retention_days=30) -> int`

- [x] **Step 1: Write failing tests**

断言 Web 登录 exchange 只创建 WebSession，不创建 AndroidDevice；设备列表不包含 WebSession；ACTIVE Android 可撤销 WebSession；PENDING Android 和 WebSession 不能撤销；过期/撤销超过保留窗口的记录可清理，ACTIVE 记录不被删除。

- [x] **Step 2: Run tests to verify failure**

Run: `cd backend && pytest -q tests/httpapi/test_web_session_management.py tests/domain/test_web_session_cleanup.py`

Expected: FAIL because WebSession 管理接口和清理函数尚未提供。

- [x] **Step 3: Implement management and cleanup**

复用现有 `WebSession` 表和 18 小时 TTL。新增只读摘要接口与 revoke/revoke-all；校验 actor 是 Workspace 成员且设备为 ACTIVE。清理函数按 `status != ACTIVE AND updated_at < cutoff` 或 `expires_at < now` 删除历史，保证可重复执行并使用批量删除。

- [x] **Step 4: Add operational invocation**

为部署环境增加可重复的管理命令或定时任务入口，例如 `python -m app.web_login.cleanup`，默认只清理 30 天以前的挑战和会话。不得在请求路径中删除 ACTIVE 会话。

- [x] **Step 5: Run Web login regression suite and commit**

Run: `cd backend && pytest -q tests/httpapi/test_web_login.py tests/httpapi/test_web_session_management.py tests/domain/test_web_session_cleanup.py`

```bash
git add backend/app/web_login backend/app/devices/routes.py backend/tests/httpapi/test_web_session_management.py backend/tests/domain/test_web_session_cleanup.py
git commit -m "feat: manage and purge temporary web sessions"
```

### Task 6: Flutter Android bootstrap 与设备管理界面

**Files:**
- Modify: `client/lib/workspace/workspace_bootstrap_repository.dart`
- Modify: `client/lib/workspace/workspace_bootstrap_controller.dart`
- Modify: `client/lib/screens/workspace_bootstrap_screen.dart`
- Modify: `client/lib/screens/workspace_gate.dart`
- Create: `client/lib/devices/device_management_repository.dart`
- Create: `client/lib/screens/device_management_screen.dart`
- Test: `client/test/workspace/workspace_bootstrap_controller_test.dart`
- Test: `client/test/screens/workspace_bootstrap_screen_test.dart`
- Test: `client/test/devices/device_management_test.dart`

**Interfaces:**
- `WorkspaceBootstrapRepository.loadBootstrap() -> WorkspaceBootstrapPayload`
- `WorkspaceBootstrapRepository.bindPartner(String phone, String requestId) -> WorkspaceBootstrapPayload`
- `WorkspaceBootstrapRepository.acceptInvite(String inviteId, String requestId) -> WorkspaceBootstrapPayload`
- `DeviceManagementRepository.list()` / `revoke(deviceId)`

- [x] **Step 1: Write failing Flutter tests**

覆盖首登填写伙伴手机号、11 位自动补 `+86`、等待邀请、受邀加入、未验证设备只读提示、创建/写操作禁用、当前设备没有撤销按钮。

- [x] **Step 2: Run focused tests to verify failure**

Run: `cd client && flutter test test/workspace/workspace_bootstrap_controller_test.dart test/screens/workspace_bootstrap_screen_test.dart test/devices/device_management_test.dart`

Expected: FAIL because repository仍只返回 `WorkspaceSummary?`，UI 只有 needsWorkspace。

- [x] **Step 3: Implement repository and state machine**

将 bootstrap 响应解析为联合状态，保留 API 错误 code/details。控制器在 `needsPartner/waitingForPartner/invited/ready/readOnlyDevice/failure` 间转换，网络错误才显示重试。

- [x] **Step 4: Implement screens and write guards**

绑定页提供手机号输入；等待页显示掩码邀请手机号；只读设备进入 Workspace 但将创建、编辑、评论、延期、冲突操作全部禁用，并保留读取和刷新。设备管理页只展示 Android 设备，当前设备不渲染撤销按钮；其他设备提供撤销确认。

- [x] **Step 5: Run Flutter verification and commit**

Run: `cd client && dart format --set-exit-if-changed lib test && flutter analyze && flutter test`

```bash
git add client/lib client/test
git commit -m "feat: add partner bootstrap and device management UI"
```

### Task 7: Web 临时会话管理界面与状态隔离

**Files:**
- Modify: `web/src/api/client.ts`
- Modify: `web/src/app.ts`
- Create: `web/src/ui/web-session-view.ts`
- Modify: `web/src/ui/workspace-view.ts`
- Test: `web/test/web-session-view.test.ts`
- Test: `web/test/app-session-isolation.test.ts`

**Interfaces:**
- `ApiClient.listWebSessions()`
- `ApiClient.revokeWebSession(id)`
- `ApiClient.revokeAllWebSessions()`

- [x] **Step 1: Write failing Vitest tests**

测试 Web 不调用 Android 设备注册接口；会话列表只显示有效会话；撤销成功后从列表移除；401 后回到 QR 登录；Workspace 切换或登出不会渲染旧会话数据。

- [x] **Step 2: Run tests to verify failure**

Run: `cd web && npm test -- --run test/web-session-view.test.ts test/app-session-isolation.test.ts`

Expected: FAIL because API client 和会话 UI 尚未提供。

- [x] **Step 3: Implement WebSession client and view**

使用现有 `credentials: include` API client。会话页只显示 origin、创建时间、过期时间和撤销操作，不显示 digest/token。任何写操作期间保持详情视图和错误状态，避免旧 Workspace 内容回填。

- [x] **Step 4: Run Web checks and commit**

Run: `cd web && npm run typecheck && npm test -- --run && npm run build`

```bash
git add web/src web/test
git commit -m "feat: manage temporary web sessions"
```

### Task 8: 端到端验收、清理任务与发布检查

**Files:**
- Modify: `backend/tests/httpapi/test_end_to_end_workspace.py`
- Modify: `client/integration_test/` Android-only tests
- Modify: `web/test/` cross-client contract tests
- Modify: `deploy/compose.yml` or deployment scheduler configuration
- Modify: `docs/operations/first-workspace-setup.md`
- Modify: `docs/operations/build-artifacts.md`
- Create: `docs/operations/device-and-web-session.md`

**Interfaces:**
- 验收脚本必须能从数据库清理、API、Android 和 Web 三端重现完整流程。

- [x] **Step 1: Add cross-client contract tests**

覆盖完整顺序：A 首登 -> 绑定 B -> A 创建任务 -> B 首台设备加入 -> B 第二台设备登录只读 -> A 批准 B 第二台设备 -> B 获得写权限 -> Web 扫码登录 -> Web 创建任务 -> Android 看到任务 -> Android 撤销 WebSession -> Web 401 并回 QR。

- [x] **Step 2: Run backend and Web suites**

Run: `cd backend && pytest -q`; `cd web && npm run typecheck && npm test -- --run && npm run build`

Expected: 全部通过；pytest 缺失或数据库凭据不匹配时，先按项目 disposable PostgreSQL 流程启动测试数据库再运行，不能把未运行当作通过。

- [x] **Step 3: Run Android verification**

Run: `cd client && dart format --set-exit-if-changed lib test && flutter analyze && flutter test`; 在可用 Android emulator 上运行设备验证和扫码集成测试。

- [x] **Step 4: Verify cleanup and deployment**

执行清理命令两次，确认第二次为幂等；确认 WebSession 不出现在 `/devices`；确认 API、静态 Web 和 Android 构建均不包含敏感配置。

- [x] **Step 5: Update operations documentation**

记录首登绑定、邀请接受、未验证设备只读、当前设备不可撤销、Web 会话 18 小时过期和手动撤销流程。明确 Web 会话不是 Android 设备。

- [x] **Step 6: Final verification and commit**

Run: `git diff --check && git status --short`

```bash
git add backend/tests client/integration_test web/test deploy docs/operations
git commit -m "test: verify two-person device and web session lifecycle"
```
