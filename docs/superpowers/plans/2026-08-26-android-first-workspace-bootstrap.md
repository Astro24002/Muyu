# Android 首个共享空间引导实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让已通过短信认证、但尚未加入任何 Workspace 的 Android 用户显式创建自己的首个共享空间；创建成功后才能进入任务页和授权 Web 扫码登录。

**Architecture:** 后端现有的 `GET /api/v1/workspaces/current` 和 `POST /api/v1/workspaces` 已经是首空间流程的唯一事实源，Android 不新增本地 Workspace、离线写入或数据库直连。Flutter 在登录成功和 `CloudWorkspaceScreen` 之间加入一个只读查询门控：服务端返回 `null` 时呈现一次明确的创建动作；返回 ACTIVE Workspace 时才加载同步与二维码扫描器。二维码服务的 ACTIVE 成员校验保持不变。

**Tech Stack:** Python 3.12、FastAPI、SQLAlchemy 2、PostgreSQL、pytest；Flutter 3.47、Dart 3.13、`flutter_test`、`http`。

**Spec:** [云端协调双人协作架构规格](../specs/2026-08-24-cloud-coordinated-collaboration-design.md)；[Android 与独立 Web 客户端边界设计](../specs/2026-08-25-android-web-client-boundary-design.md)。

## Global Constraints

- 首个空间只能由已认证、ACTIVE Android 设备的当前用户显式创建；不得在登录、扫码或页面刷新时静默创建。
- 一个用户最多一个 ACTIVE Workspace、一个 Workspace 最多两名 ACTIVE 成员的 PostgreSQL 约束保持不变；不新增迁移、表、索引或手工生产数据库写入。
- Web 继续只有受已认证 Android 设备批准的扫码登录，没有手机号、密码或其他浏览器独立身份入口。
- `WebLoginService.scan` 必须继续拒绝没有 ACTIVE `WorkspaceMembership` 的设备；本计划修复的是 Android 缺少创建入口，不是放宽该安全检查。
- Flutter 只构建 Android APK/AAB；不重新引入 Flutter Web、Chrome integration test、P2P、离线写入队列或本地事实源。
- 首版界面不增加项目、团队、Workspace 切换、空间命名表单、邀请表单或成员审批新流程；创建按钮只发送空的 `{}` 请求体，服务端 Workspace 名称保持 `null`。
- 所有网络请求走现有 `ApiClient`、带 Bearer 会话并把服务端错误转为稳定的本地错误类型；界面不显示 token、原始 HTTP 响应或内部异常堆栈。
- `workspace_limit_reached` 可能来自同一账户另一台设备的并发创建。客户端必须重新查询当前空间，若已存在则进入该空间，而不是把它当作不可恢复错误。
- 每项实现遵守 TDD：先写目标行为测试，运行确认当前缺口，再做最小实现、运行专项检查并进行小提交。后端已有正确行为时，先加入的测试是契约回归测试，预期直接通过且不应改动生产服务代码。

---

## 问题定位与边界

当前生产数据中已有 ACTIVE 用户和 ACTIVE Android 设备，但没有 `Workspace` 或 ACTIVE `WorkspaceMembership`。这正是 `/api/v1/web-login/challenges/{id}/scan` 返回 `workspace_access_denied / workspace membership required` 的原因。该拒绝是规格要求的安全行为。

本计划产生的用户路径是：

```text
短信登录成功
    |
GET /workspaces/current
    |
    +-- 200 + Workspace --> 任务页 / 已可扫码授权 Web
    |
    +-- 200 + null ------> 创建共享空间
                               |
                         POST /workspaces {}
                               |
                               +--> 201 --> 任务页 / 已可扫码授权 Web
                               +--> 409 workspace_limit_reached --> 再次 GET /current
                               +--> 网络或其他错误 --> 保留创建页并允许重试
```

创建首个空间后，另一名成员的邀请、接受和由对方 ACTIVE Android 设备批准流程继续复用现有服务端接口；它不在本次 Android UI 范围内。不得为方便扫码而直接向生产 PostgreSQL 插入 membership，也不得让没有 membership 的设备通过扫码授权。

## 文件地图

- `backend/app/workspaces/routes.py`：已有的首空间 HTTP 契约，预计不修改。
- `backend/app/workspaces/service.py`：已有的唯一性、成员 slot 和 cursor 事务逻辑，预计不修改。
- `backend/app/web_login/service.py`：已有的扫码成员校验，预计不修改。
- `backend/tests/httpapi/test_workspace_bootstrap.py`：首空间 API 的 HTTP 回归契约。
- `backend/tests/web_login/test_qr_login.py`：无成员时扫码必须拒绝的安全回归测试。
- `client/lib/workspace/workspace_bootstrap_repository.dart`：Android 对当前 Workspace 和创建 Workspace 的最小 API 边界。
- `client/lib/workspace/workspace_bootstrap_controller.dart`：可测试的加载、创建、并发恢复和错误状态机。
- `client/lib/screens/workspace_bootstrap_screen.dart`：无 Workspace 时的单一创建动作和可重试错误 UI。
- `client/lib/screens/workspace_gate.dart`：登录后门控；只有 ACTIVE Workspace 才创建 `CloudWorkspaceScreen`。
- `client/lib/app.dart`：将签入分支从直接任务页改为 `WorkspaceGate`。
- `client/lib/main.dart`：一次性构造并注入 `HttpWorkspaceBootstrapRepository`。
- `client/test/workspace/workspace_bootstrap_repository_test.dart`：HTTP 路径、认证和 JSON 解析测试。
- `client/test/workspace/workspace_bootstrap_controller_test.dart`：状态机和并发创建恢复测试。
- `client/test/screens/workspace_gate_test.dart`：Widget 路由门控、创建和重试测试。
- `docs/operations/first-workspace-setup.md`：运维和真实设备首空间/扫码验收步骤。
- `docs/README.md`、`docs/operations/release-checklist.md`、`docs/05-development-status.md`：文档索引、发布检查和实际证据记录。

## 固定 API 契约

Android 只依赖下列已存在的受保护路由。请求一律由 `ApiClient` 使用 `authenticated: true` 发出：

```http
GET /api/v1/workspaces/current
Authorization: Bearer <mobile access token>

200 null

200 {
  "id": "workspace UUID",
  "name": null,
  "status": "ACTIVE",
  "members": [{"user_id": "user UUID", "member_slot": 1}]
}
```

```http
POST /api/v1/workspaces
Authorization: Bearer <mobile access token>
Content-Type: application/json

{}

201 {"id": "workspace UUID", "name": null, "status": "ACTIVE"}
409 {"code": "workspace_limit_reached", "message": "..."}
```

`POST` 成功后服务端必须在同一事务中创建 `Workspace`、slot 1 ACTIVE `WorkspaceMembership` 与 `WorkspaceCursor`。客户端不接收或保存成员授权密钥、Web Cookie、二维码 proof 或数据库连接信息。

---

### Task 1: 冻结首空间 API 与扫码安全契约

**Files:**
- Create: `backend/tests/httpapi/test_workspace_bootstrap.py`
- Modify: `backend/tests/web_login/test_qr_login.py`
- Verify only: `backend/app/workspaces/routes.py`
- Verify only: `backend/app/workspaces/service.py`
- Verify only: `backend/app/web_login/service.py`

**Interfaces:**
- `GET /api/v1/workspaces/current` returns `None` for an authenticated ACTIVE device with no ACTIVE membership, not 403 and not an invented local workspace.
- `POST /api/v1/workspaces` creates exactly one owner membership and returns `201`; a second request returns `409 workspace_limit_reached`.
- `WebLoginService.scan(challenge_id, scan_nonce, user_id, device_id)` raises `WebLoginConflict(code="workspace_access_denied", status_code=403)` when the active device user has no ACTIVE membership.

- [ ] **Step 1: 写 HTTP 首空间契约测试**

在 `backend/tests/httpapi/test_workspace_bootstrap.py` 复制现有测试中的最小 `FakeSmsProvider` helper（不要导入另一个测试模块），并使用 `TestClient(create_app())` 建立一台 ACTIVE Android 设备的 Bearer 会话。测试完整执行查询、创建、再查询和重复创建：

```python
class FakeSmsProvider:
    def __init__(self) -> None:
        self.codes: dict[str, str] = {}

    def send_otp(self, phone: str, code: str) -> None:
        self.codes[phone] = code

    def last_code_for(self, phone: str) -> str:
        return self.codes[phone]


def _headers_for_first_device(client: TestClient, app) -> dict[str, str]:
    phone = "+8613800138001"
    assert client.post("/api/v1/auth/sms/send", json={"phone": phone}).status_code == 202
    code = app.state.sms_provider.last_code_for(phone)
    verified = client.post(
        "/api/v1/auth/sms/verify",
        json={
            "phone": phone,
            "code": code,
            "device": {"public_key_der": "AQID", "label": "Bootstrap Pixel"},
        },
    )
    assert verified.status_code == 201
    return {"Authorization": f"Bearer {verified.json()['access_token']}"}


def test_first_active_device_can_create_exactly_one_workspace(db_engine) -> None:
    app = create_app()
    app.state.engine = db_engine
    app.state.ready = True
    app.state.sms_provider = FakeSmsProvider()
    client = TestClient(app)
    headers = _headers_for_first_device(client, app)

    assert client.get("/api/v1/workspaces/current", headers=headers).json() is None

    created = client.post("/api/v1/workspaces", headers=headers, json={})
    assert created.status_code == 201
    assert created.json()["status"] == "ACTIVE"

    current = client.get("/api/v1/workspaces/current", headers=headers)
    assert current.status_code == 200
    assert current.json()["id"] == created.json()["id"]
    assert current.json()["members"] and current.json()["members"][0]["member_slot"] == 1

    repeated = client.post("/api/v1/workspaces", headers=headers, json={})
    assert repeated.status_code == 409
    assert repeated.json()["code"] == "workspace_limit_reached"
```

- [ ] **Step 2: 写无成员扫码拒绝回归测试**

在 `backend/tests/web_login/test_qr_login.py` 新增测试，构造 ACTIVE `User` 与 ACTIVE `AndroidDevice`，但不插入 `WorkspaceMembership`。创建 challenge 后调用 `scan` 并断言安全拒绝：

```python
def test_qr_scan_rejects_active_device_without_workspace_membership(db_engine) -> None:
    with Session(db_engine) as session:
        user = User(phone="+14155552673")
        session.add(user)
        session.flush()
        private = ec.generate_private_key(ec.SECP256R1())
        device = AndroidDevice(
            user_id=user.id,
            public_key_der=private.public_key().public_bytes(
                serialization.Encoding.DER,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            ),
            fingerprint="unpaired-device",
            status=DeviceStatus.ACTIVE,
        )
        session.add(device)
        session.flush()
        service = WebLoginService(session, safety_cache={}, nonce_cache={})
        challenge = service.create_challenge(
            "https://app.example.test", hashlib.sha256(b"proof").hexdigest()
        )
        payload = json.loads(challenge.qr_payload)

        with pytest.raises(WebLoginConflict) as caught:
            service.scan(challenge.challenge_id, payload["scan_nonce"], user.id, device.id)

        assert caught.value.code == "workspace_access_denied"
        assert caught.value.status_code == 403
```

在文件顶部补 `import json`。该测试不能以创建一个假的 membership 或捕获后忽略异常来通过。

- [ ] **Step 3: 运行契约测试，确认后端不需要产品改动**

运行：

```bash
TEST_DATABASE_URL="${TEST_DATABASE_URL:?set a disposable PostgreSQL URL}" \
  make backend-test
```

预期：新增测试和既有后端测试全部通过。这里的正确结果是**不修改** `WorkspaceService`、路由或 `WebLoginService`；现有事务和扫码检查正是所需的安全边界。若测试失败，只能恢复上方“固定 API 契约”列出的精确行为，不得让扫码接受无成员设备。

- [ ] **Step 4: 提交后端契约回归测试**

```bash
git add backend/tests/httpapi/test_workspace_bootstrap.py backend/tests/web_login/test_qr_login.py
git commit -m "test: cover first workspace bootstrap contract"
```

---

### Task 2: 建立 Android Workspace Bootstrap API 边界

**Files:**
- Create: `client/lib/workspace/workspace_bootstrap_repository.dart`
- Create: `client/test/workspace/workspace_bootstrap_repository_test.dart`

**Interfaces:**

```dart
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.status,
  });

  final String id;
  final String? name;
  final String status;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json);
}

class WorkspaceBootstrapFailure implements Exception {
  const WorkspaceBootstrapFailure({
    required this.code,
    required this.statusCode,
  });

  final String code;
  final int statusCode;
}

abstract interface class WorkspaceBootstrapRepository {
  Future<WorkspaceSummary?> currentWorkspace();
  Future<WorkspaceSummary> createWorkspace();
}
```

`HttpWorkspaceBootstrapRepository` is the sole production implementation. It receives `ApiClient` in its constructor and never reaches into `MobileSessionStore` or `DeviceSigningKey`.

- [ ] **Step 1: 写 repository 失败测试**

在 `client/test/workspace/workspace_bootstrap_repository_test.dart` 使用 `http/testing.dart` 的 `MockClient` 和真实 `ApiClient` 写三个独立测试：

```dart
class StaticTokenStore implements TokenStore {
  @override
  Future<String?> readAccessToken() async => 'mobile-access';

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> write({required String accessToken, required String refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

test('current workspace returns null for a new authenticated user', () async {
  late http.Request request;
  final repository = HttpWorkspaceBootstrapRepository(ApiClient(
    baseUrl: 'https://api.example',
    httpClient: MockClient((incoming) async {
      request = incoming;
      return http.Response('null', 200);
    }),
    tokenStore: StaticTokenStore(),
  ));

  expect(await repository.currentWorkspace(), isNull);
  expect(request.method, 'GET');
  expect(request.url.path, '/api/v1/workspaces/current');
  expect(request.headers['authorization'], 'Bearer mobile-access');
});

test('create workspace posts an empty object and parses the authoritative result', () async {
  late http.Request request;
  final repository = HttpWorkspaceBootstrapRepository(ApiClient(
    baseUrl: 'https://api.example',
    httpClient: MockClient((incoming) async {
      request = incoming;
      return http.Response('{"id":"workspace-1","name":null,"status":"ACTIVE"}', 201);
    }),
    tokenStore: StaticTokenStore(),
  ));

  final workspace = await repository.createWorkspace();
  expect(request.method, 'POST');
  expect(request.url.path, '/api/v1/workspaces');
  expect(jsonDecode(request.body), <String, dynamic>{});
  expect(workspace.id, 'workspace-1');
  expect(workspace.name, isNull);
});

test('workspace limit error remains distinguishable for race recovery', () async {
  final repository = HttpWorkspaceBootstrapRepository(ApiClient(
    baseUrl: 'https://api.example',
    httpClient: MockClient((_) async => http.Response(
      '{"code":"workspace_limit_reached","message":"already joined"}', 409,
    )),
  ));

  await expectLater(
    repository.createWorkspace(),
    throwsA(isA<WorkspaceBootstrapFailure>().having(
      (error) => error.code, 'code', 'workspace_limit_reached',
    )),
  );
});
```

运行：

```bash
cd client
flutter test test/workspace/workspace_bootstrap_repository_test.dart
```

预期：失败，因为 repository、模型和错误类型尚不存在。

- [ ] **Step 2: 实现最小 HTTP repository**

创建 `workspace_bootstrap_repository.dart`。实现必须精确使用以下结构；`ApiClient` 负责 Authorization header、JSON 编码和网络异常转换：

```dart
class HttpWorkspaceBootstrapRepository implements WorkspaceBootstrapRepository {
  HttpWorkspaceBootstrapRepository(this._api);

  final ApiClient _api;

  @override
  Future<WorkspaceSummary?> currentWorkspace() async {
    try {
      final value = await _api.request(
        'GET',
        '/api/v1/workspaces/current',
        authenticated: true,
      );
      return value == null
          ? null
          : WorkspaceSummary.fromJson(value as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }

  @override
  Future<WorkspaceSummary> createWorkspace() async {
    try {
      final value = await _api.request(
        'POST',
        '/api/v1/workspaces',
        body: const <String, Object?>{},
        authenticated: true,
      );
      return WorkspaceSummary.fromJson(value as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw WorkspaceBootstrapFailure(
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }
}
```

`WorkspaceSummary.fromJson` accepts exactly the documented `id` and `status` strings and nullable `name`; it does not infer a Workspace from a user id or fabricate a fallback value.

- [ ] **Step 3: 运行 repository 专项测试和静态检查**

```bash
cd client
dart format --output=none --set-exit-if-changed lib/workspace/workspace_bootstrap_repository.dart test/workspace/workspace_bootstrap_repository_test.dart
flutter analyze
flutter test test/workspace/workspace_bootstrap_repository_test.dart
```

预期：格式无变更、analyze 无问题、三个 repository 测试通过。

- [ ] **Step 4: 提交 API 边界**

```bash
git add client/lib/workspace/workspace_bootstrap_repository.dart client/test/workspace/workspace_bootstrap_repository_test.dart
git commit -m "feat: add Android workspace bootstrap repository"
```

---

### Task 3: 实现可恢复的首空间状态机

**Files:**
- Create: `client/lib/workspace/workspace_bootstrap_controller.dart`
- Create: `client/test/workspace/workspace_bootstrap_controller_test.dart`

**Interfaces:**

```dart
enum WorkspaceBootstrapStatus {
  loading,
  needsWorkspace,
  creatingWorkspace,
  ready,
  failure,
}

class WorkspaceBootstrapState {
  const WorkspaceBootstrapState({
    required this.status,
    this.workspace,
    this.errorMessage,
  });

  final WorkspaceBootstrapStatus status;
  final WorkspaceSummary? workspace;
  final String? errorMessage;
}

class WorkspaceBootstrapController extends ChangeNotifier {
  WorkspaceBootstrapController(WorkspaceBootstrapRepository repository);

  WorkspaceBootstrapState state;
  Future<void> load();
  Future<void> createWorkspace();
}
```

The controller owns all state transitions; the screen only renders `state` and invokes the two public methods. It uses a private generation counter and disposed flag so an old async request cannot repaint a removed login session.

- [ ] **Step 1: 写 controller 失败测试**

在 `client/test/workspace/workspace_bootstrap_controller_test.dart` 写一个只实现 `WorkspaceBootstrapRepository` 的 fake。它应具备 `currentResult`、`createResult`、`currentCalls`、`createCalls` 和可选 `Completer`，以精确验证异步状态。覆盖下列行为：

```dart
test('no current workspace enters the explicit creation state', () async {
  final repository = FakeWorkspaceBootstrapRepository()..currentResult = null;
  final controller = WorkspaceBootstrapController(repository);

  await controller.load();

  expect(controller.state.status, WorkspaceBootstrapStatus.needsWorkspace);
  expect(controller.state.workspace, isNull);
});

test('create transitions to ready exactly once while request is pending', () async {
  final pending = Completer<WorkspaceSummary>();
  final repository = FakeWorkspaceBootstrapRepository()
    ..currentResult = null
    ..createFuture = pending.future;
  final controller = WorkspaceBootstrapController(repository);
  await controller.load();

  final first = controller.createWorkspace();
  final second = controller.createWorkspace();
  expect(repository.createCalls, 1);
  expect(controller.state.status, WorkspaceBootstrapStatus.creatingWorkspace);

  pending.complete(const WorkspaceSummary(id: 'w1', name: null, status: 'ACTIVE'));
  await Future.wait([first, second]);
  expect(controller.state.status, WorkspaceBootstrapStatus.ready);
  expect(controller.state.workspace!.id, 'w1');
});

test('workspace limit race reloads and enters the workspace created elsewhere', () async {
  final repository = FakeWorkspaceBootstrapRepository()
    ..currentResults = [null, const WorkspaceSummary(id: 'w2', name: null, status: 'ACTIVE')]
    ..createFailure = const WorkspaceBootstrapFailure(
      code: 'workspace_limit_reached', statusCode: 409,
    );
  final controller = WorkspaceBootstrapController(repository);
  await controller.load();
  await controller.createWorkspace();

  expect(repository.currentCalls, 2);
  expect(controller.state.status, WorkspaceBootstrapStatus.ready);
  expect(controller.state.workspace!.id, 'w2');
});
```

再增加两项断言：初始 `currentWorkspace()` 网络失败进入 `failure` 并展示稳定文本 `无法加载共享空间，请检查网络后重试`；普通创建失败回到 `needsWorkspace`、显示 `创建共享空间失败，请稍后重试`，且下一次点击仍可创建。

运行：

```bash
cd client
flutter test test/workspace/workspace_bootstrap_controller_test.dart
```

预期：失败，因为 controller 和状态类型尚不存在。

- [ ] **Step 2: 实现状态转换和并发恢复**

创建 controller，并以此状态图实现：

```text
loading -- current=null --> needsWorkspace
loading -- current=workspace --> ready
loading -- failure --> failure
needsWorkspace -- create --> creatingWorkspace
creatingWorkspace -- 201 --> ready
creatingWorkspace -- 409 workspace_limit_reached --> loading -> current query
creatingWorkspace -- other failure --> needsWorkspace (with create error)
failure -- load --> loading
```

实现要点：

```dart
Future<void> createWorkspace() async {
  if (state.status != WorkspaceBootstrapStatus.needsWorkspace) return;
  final generation = ++_generation;
  _publish(const WorkspaceBootstrapState(
    status: WorkspaceBootstrapStatus.creatingWorkspace,
  ));
  try {
    final workspace = await _repository.createWorkspace();
    if (_isObsolete(generation)) return;
    _publish(WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.ready,
      workspace: workspace,
    ));
  } on WorkspaceBootstrapFailure catch (error) {
    if (_isObsolete(generation)) return;
    if (error.code == 'workspace_limit_reached') {
      await load();
      return;
    }
    _publish(const WorkspaceBootstrapState(
      status: WorkspaceBootstrapStatus.needsWorkspace,
      errorMessage: '创建共享空间失败，请稍后重试',
    ));
  }
}
```

`load()` follows the same generation rule. It publishes `loading` first, publishes `ready` for a non-null response, `needsWorkspace` for `null`, and `failure` with `无法加载共享空间，请检查网络后重试` for `WorkspaceBootstrapFailure`. `dispose()` increments `_generation`, marks the instance disposed, and invokes `super.dispose()`; `_publish` must not call `notifyListeners()` after disposal.

- [ ] **Step 3: 运行状态机测试与格式检查**

```bash
cd client
dart format --output=none --set-exit-if-changed lib/workspace/workspace_bootstrap_controller.dart test/workspace/workspace_bootstrap_controller_test.dart
flutter analyze
flutter test test/workspace/workspace_bootstrap_controller_test.dart
```

预期：所有加载、单击并发、409 race、网络失败和重试断言通过。

- [ ] **Step 4: 提交状态机**

```bash
git add client/lib/workspace/workspace_bootstrap_controller.dart client/test/workspace/workspace_bootstrap_controller_test.dart
git commit -m "feat: add Android workspace bootstrap state machine"
```

---

### Task 4: 在 Android 登录后接入 Workspace 门控界面

**Files:**
- Create: `client/lib/screens/workspace_bootstrap_screen.dart`
- Create: `client/lib/screens/workspace_gate.dart`
- Modify: `client/lib/app.dart`
- Modify: `client/lib/main.dart`
- Create: `client/test/screens/workspace_gate_test.dart`

**Interfaces:**

```dart
class WorkspaceBootstrapScreen extends StatelessWidget {
  const WorkspaceBootstrapScreen({
    super.key,
    required this.state,
    required this.onCreate,
    required this.onRetry,
  });

  final WorkspaceBootstrapState state;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRetry;
}

class WorkspaceGate extends StatefulWidget {
  const WorkspaceGate({
    super.key,
    required this.api,
    required this.signingKey,
    required this.repository,
  });

  final ApiClient api;
  final DeviceSigningKey signingKey;
  final WorkspaceBootstrapRepository repository;
}
```

`WorkspaceGate` constructs one `WorkspaceBootstrapController`, calls `load()` exactly once from `initState`, disposes it, and never creates `CloudWorkspaceScreen` until `state.status == WorkspaceBootstrapStatus.ready`.

- [ ] **Step 1: 写门控 Widget 失败测试**

在 `client/test/screens/workspace_gate_test.dart` 建立 fake bootstrap repository、fake signing key 和返回稳定空 snapshot 的 `MockClient` API。写以下两个 Widget 测试：

测试文件自行定义测试专用 fake，不能从另一个 `test/` 文件导入：`FakeWorkspaceBootstrapRepository` 实现两个 repository 方法并记录调用次数；`FakeDeviceSigningKey` 实现 `getOrCreatePublicKey()`、`sign(Uint8List)` 和 `deleteKey()`；`testApiClient()` 返回 `/api/v1/workspaces/current/snapshot` 的同步 JSON 响应。

```dart
testWidgets('new user sees create workspace and cannot reach the web scanner', (tester) async {
  final repository = FakeWorkspaceBootstrapRepository()..currentResult = null;
  await tester.pumpWidget(MaterialApp(
    home: WorkspaceGate(
      api: testApiClient(),
      signingKey: FakeDeviceSigningKey(),
      repository: repository,
    ),
  ));
  await tester.pumpAndSettle();

  expect(find.text('创建共享空间'), findsOneWidget);
  expect(find.byType(CloudWorkspaceScreen), findsNothing);
  expect(find.byTooltip('扫码登录 Web'), findsNothing);
});

testWidgets('create action opens the task workspace only after 201 result', (tester) async {
  final repository = FakeWorkspaceBootstrapRepository()
    ..currentResult = null
    ..createResult = const WorkspaceSummary(id: 'w1', name: null, status: 'ACTIVE');
  await tester.pumpWidget(MaterialApp(
    home: WorkspaceGate(
      api: testApiClient(),
      signingKey: FakeDeviceSigningKey(),
      repository: repository,
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('创建共享空间'));
  await tester.pumpAndSettle();

  expect(repository.createCalls, 1);
  expect(find.byType(CloudWorkspaceScreen), findsOneWidget);
});
```

添加第三个测试：初始加载失败时只出现 `重试`，点击后重新调用 `currentWorkspace()`；创建失败时仍显示 `创建共享空间` 且按钮重新可用。`testApiClient()` 的 `/snapshot` 响应必须含有 `workspace_id`、`cursor`、`tasks`、`members` 与 `conflicts`，避免以网络异常掩盖路由断言。

运行：

```bash
cd client
flutter test test/screens/workspace_gate_test.dart
```

预期：失败，因为门控和创建页尚不存在。

- [ ] **Step 2: 实现最小创建页和门控**

`WorkspaceBootstrapScreen` 使用单列 `Scaffold`：

- `needsWorkspace` 显示标题 `创建共享空间`、一个 `FilledButton`，按钮文字同为 `创建共享空间`；按下调用 `onCreate`。
- `creatingWorkspace` 显示不可点击的 `CircularProgressIndicator` 和禁用的 `FilledButton`，杜绝重复 HTTP 写入。
- `failure` 显示 controller 提供的稳定文本与 `OutlinedButton` `重试`；按下调用 `onRetry`。
- `needsWorkspace` 带 `errorMessage` 时在按钮上方显示该稳定文本。页面不含空间名称输入、成员手机号输入、二维码内容或技术说明。

`WorkspaceGate` 用 `AnimatedBuilder` 监听 controller：

```dart
switch (_controller.state.status) {
  case WorkspaceBootstrapStatus.ready:
    return CloudWorkspaceScreen(
      key: ValueKey(_controller.state.workspace!.id),
      api: widget.api,
      signingKey: widget.signingKey,
    );
  case WorkspaceBootstrapStatus.loading:
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  case WorkspaceBootstrapStatus.needsWorkspace:
  case WorkspaceBootstrapStatus.creatingWorkspace:
  case WorkspaceBootstrapStatus.failure:
    return WorkspaceBootstrapScreen(
      state: _controller.state,
      onCreate: _controller.createWorkspace,
      onRetry: _controller.load,
    );
}
```

不得在 `build()` 调用 `load()`，也不得在此层捕获并吞掉 controller 状态。

- [ ] **Step 3: 注入 repository 并替换签入路由**

在 `main.dart`，与 `HttpMobileAuthRepository` 共用现有 `apiClient` 构造一次：

```dart
final workspaceBootstrapRepository = HttpWorkspaceBootstrapRepository(apiClient);
```

为 `MuyuApp` 增加必填 `WorkspaceBootstrapRepository workspaceBootstrapRepository` 字段，并传给 `_AndroidHome`。在 `app.dart` 的签入分支替换直接进入任务页的代码：

```dart
controller.status == MobileLoginStatus.signedIn
    ? WorkspaceGate(
        key: ValueKey(controller.currentSession!.user.id),
        api: apiClient,
        signingKey: signingKey,
        repository: workspaceBootstrapRepository,
      )
    : MobilePhoneLoginScreen(controller: controller)
```

保留 `CloudWorkspaceScreen`、`WebQrScannerScreen`、`MobileLoginController` 和 Android Keystore 的既有责任边界；不向 Web bundle 或浏览器传递 Android 身份材料。

- [ ] **Step 4: 运行 Android 专项测试和完整静态测试**

```bash
cd client
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/workspace/workspace_bootstrap_repository_test.dart \
  test/workspace/workspace_bootstrap_controller_test.dart \
  test/screens/workspace_gate_test.dart \
  test/auth/mobile_login_controller_test.dart \
  test/android_entrypoint_test.dart
flutter test
```

预期：新用户无法到达 scanner、创建成功后才出现 `CloudWorkspaceScreen`、重试和 race 恢复均通过；既有 Android-only 边界测试仍通过。

- [ ] **Step 5: 提交 Android 集成**

```bash
git add client/lib/app.dart client/lib/main.dart client/lib/workspace client/lib/screens/workspace_bootstrap_screen.dart client/lib/screens/workspace_gate.dart client/test/workspace client/test/screens/workspace_gate_test.dart
git commit -m "feat: guide Android users through first workspace creation"
```

---

### Task 5: 编写操作文档、构建 APK 并进行真实设备验收

**Files:**
- Create: `docs/operations/first-workspace-setup.md`
- Modify: `docs/README.md`
- Modify: `docs/operations/release-checklist.md`
- Modify: `docs/05-development-status.md`

**Interfaces:**
- 操作文档只引用公开 HTTPS API 入口、APK 路径和正常 UI，不提供 PostgreSQL shell、生产 token、短信验证码或绕过 membership 的操作。
- 发布记录必须写明源 commit、APK SHA-256、命令结果和真实设备验证结果；只记录已经发生的事实。

- [ ] **Step 1: 写首空间操作说明**

创建 `docs/operations/first-workspace-setup.md`，按下面的固定顺序写入：

1. 使用带 `API_BASE_URL=https://muyu.bkverse.space` 的 Android APK 登录手机号。
2. 已有 ACTIVE membership 的账户直接进入任务页；没有 membership 的账户看到 `创建共享空间`。
3. 点击一次 `创建共享空间` 并等待任务页出现。网络失败使用 `重试`，不要反复安装、清数据或手工插入数据库记录。
4. 在任务页点击扫描入口，扫描 `https://muyu.bkverse.space` 的 Web QR code，并在 Android 上明确批准。
5. 浏览器获得短期 Web session 后加载 Workspace；若仍显示 `workspace membership required`，停止扫码并先在 Android 完成上一步创建。
6. 添加第二位成员仍使用现有邀请、接受和对方设备批准协议；此文档不把短信验证或用户手机号当作自动成员授权。

在 `docs/README.md` 的关联资料中添加该文档链接，并在 `release-checklist.md` 的 After release 列表中加入“首个 Android 用户创建 Workspace 后可完成 Web QR 登录”的核对项。

- [ ] **Step 2: 运行后端、Android 和部署前检查**

在具有可丢弃 PostgreSQL 测试库的环境中运行：

```bash
TEST_DATABASE_URL="${TEST_DATABASE_URL:?set a disposable PostgreSQL URL}" make backend-test
make client-test
make boundary-check
make check-deployment
API_BASE_URL=https://muyu.bkverse.space make client-build
sha256sum client/build/app/outputs/flutter-apk/app-debug.apk
git rev-parse HEAD
```

预期：所有命令退出码为 0，并生成 `client/build/app/outputs/flutter-apk/app-debug.apk`。本次不修改 FastAPI 生产代码或数据库 schema，因此不需要为了此功能重建或重启服务端容器；只分发经过验证的新 APK。

- [ ] **Step 3: 在真实 Android 与现有 HTTPS 站点验收**

在测试 Android 设备安装本次 APK，并按如下顺序执行，不使用直接数据库操作：

```bash
adb install -r client/build/app/outputs/flutter-apk/app-debug.apk
```

人工验收清单：

- 已登录但无空间的用户先看到 `创建共享空间`，看不到任务页的 `扫码登录 Web`。
- 点击一次创建后进入任务页；下拉刷新没有权限错误。
- 在浏览器打开 `https://muyu.bkverse.space`，页面生成 QR code；使用同一 Android 设备扫描并批准后，浏览器进入 Workspace。
- Android 扫码不再出现 `workspace membership required`；浏览器没有获得手机号密码、Android 私钥或长期移动 token。
- 重新打开 App 与浏览器时可读取同一 Workspace；创建过程不产生第二个 Workspace。
- Android 注销后重新登录已有成员账户时直接进入任务页，不再显示创建按钮。

如果测试账户已经有 membership，则使用新手机号测试账户完成首次创建路径；不要删除已有真实用户、Workspace 或历史数据来模拟新用户。

- [ ] **Step 4: 记录实际证据并提交文档**

在真实命令和设备验收完成后，向 `docs/05-development-status.md` 追加一个带当天日期的事实记录，包含：源 commit、APK SHA-256、`make backend-test`/`make client-test`/`make boundary-check`/`make check-deployment` 的退出结果、测试域名和上述人工验收每项的结果。不得写入手机号、短信验证码、Bearer token、Cookie、AppCode、数据库 URL 或私钥。

```bash
git add docs/operations/first-workspace-setup.md docs/README.md docs/operations/release-checklist.md docs/05-development-status.md
git commit -m "docs: add first workspace setup and release checks"
```

---

## 最终验收矩阵

| 范围 | 验收证据 | 必须结果 |
| --- | --- | --- |
| 后端首空间 | `test_workspace_bootstrap.py` | `null -> 201 -> current Workspace -> 409`，无 schema 或安全回归 |
| 后端二维码安全 | `test_qr_login.py` | 无 ACTIVE membership 的 ACTIVE device 仍得到 `workspace_access_denied` |
| Android API | repository tests | 使用 `/workspaces/current`、`/workspaces`、空 JSON body、可识别 409 race |
| Android 状态 | controller tests | 无空间、创建、重复点击、网络错误、重试、并发创建恢复均确定 |
| Android UI | gate Widget tests | 无空间无法看到 Web scanner；成功创建后才进入任务页 |
| 构建 | `make client-test` 与 `make client-build` | 仅 Android APK，无 Flutter Web 构建 |
| 真实互操作 | Android + `https://muyu.bkverse.space` | 创建首空间后 QR 允许；未创建时继续拒绝 |

## 自检

- **规格覆盖：** 本计划落实了架构规格 4.1 的“用户 A 登录并创建第一个 Workspace”前置步骤，并保留 6.2 的扫码 ACTIVE membership 验证。未引入 iOS、第三成员、独立 Web 登录、P2P、端到端加密或离线写入。
- **边界覆盖：** 只有 Android 客户端发生功能变更；Web SPA、FastAPI 的公开登录模型和 PostgreSQL schema 均不扩展。浏览器仍不能成为身份源。
- **并发与安全：** `workspace_limit_reached` 强制重新读取事实源；重复按钮在 controller 层忽略；旧 async 完成不能更新已销毁的 gate；没有通过放宽后端安全校验解决问题。
- **占位符扫描：** 本文不包含未定义的类型、待定接口或泛化的错误处理描述；每个新增类型、文件、请求和验证命令均在对应任务中给出。
- **类型一致性：** repository 的 `currentWorkspace()`/`createWorkspace()` 被 controller 使用；controller 的 `load()`/`createWorkspace()` 被 screen/gate 使用；`WorkspaceSummary` 贯穿 HTTP 解析、状态与 UI 门控，名称和返回类型一致。
