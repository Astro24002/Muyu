# Android 与独立 Web 客户端边界设计

## 1. 状态与范围

本规格确认客户端边界：Flutter 只负责 Android；Web 使用独立的 TypeScript + Vite 单页应用；FastAPI 只负责 JSON API、WebSocket 和认证协议，不渲染页面。

本规格补充并约束 `2026-08-24-cloud-coordinated-collaboration-design.md` 中的客户端与部署部分。云端明文任务事实源、PostgreSQL、双人 Workspace、短信登录、Android 设备审批、Web 二维码登录、18 小时 Web 会话和在线同步规则保持不变。

后端开发语言固定为 Python 3.12，API 框架继续使用 FastAPI；本次客户端拆分不触发后端改写为 TypeScript、Go、Rust 或其他语言。前后端类型通过 OpenAPI 合同衔接。

首版不实现 iOS，不恢复 Flutter Web，不引入 SSR，不把 Android 私钥或任务加密密钥发送到浏览器。

## 2. 目标拓扑

```text
Android Flutter App                 TypeScript + Vite Web SPA
        |                                      |
        +----------- HTTPS / WSS --------------+
                         |
                    Caddy / TLS
                  /               \
          static Web assets       /api/* and /api/v1/realtime
                  |                         |
                  +---------- FastAPI API -+
                                      |
                                  PostgreSQL
```

组件职责固定如下：

- `client/`：Flutter Android 应用，短信登录、Android Keystore 设备身份、设备授权、扫码批准 Web 登录、任务读写和同步。
- `web/`：TypeScript + Vite 浏览器应用，二维码登录展示、Web 会话管理、任务列表和编辑、同步状态、登出。
- `backend/`：FastAPI 模块化 API，提供认证、设备、Workspace、任务、同步、Web 登录和 WebSocket 协议；不包含模板、页面路由或浏览器 UI。
- `deploy/Caddyfile`：终止 TLS，静态服务 `web/dist`，将 `/api/*` 和 `/api/v1/realtime*` 反向代理到 FastAPI。
- `PostgreSQL`：唯一任务事实源和会话/授权存储。

Web 和 Android 必须共享后端 API、权限判断、Workspace cursor、冲突语义和错误格式。客户端实现可以不同，但不能复制另一端的数据库或业务事实。

## 3. Web 功能范围

### 3.1 首屏与二维码登录

浏览器打开根路径后，Web 生成高熵 `browserProof`，只在当前页面内存保存其原值，并发送其 SHA-256 摘要创建挑战。页面显示服务端返回的二维码、来源和安全码，轮询挑战状态。

用户使用自己的 ACTIVE Android 设备扫描二维码。Android 端继续负责显示来源、安全码并签名批准。浏览器在状态变为 `APPROVED` 后提交原始 `browserProof` 兑换服务端 HttpOnly Cookie。浏览器不得获取 Android 私钥、设备签名材料或移动端 Bearer token。

Web 请求使用同源 `/api` 路径并携带 `credentials: 'include'`。会话到期、被撤销或返回 `401` 时清除页面状态并回到二维码登录页。Web 页面不提供短信验证码登录。

### 3.2 任务与同步

首版 Web 页面只覆盖可验证的核心功能：

- 读取当前 Workspace 快照和增量变更；
- 展示任务标题、描述、状态、版本和同步游标；
- 创建任务；
- 修改允许的任务字段并展示字段冲突；
- 手动刷新；
- 登出。

所有写入沿用现有 `request_id` 幂等协议和字段版本冲突返回。Web 不实现离线写入，不在浏览器本地建立第二个事实源；网络失败时只显示明确的同步错误。

实时更新优先使用现有 WebSocket；连接失败时通过手动刷新或短轮询恢复。首版不要求浏览器后台可靠运行。

### 3.3 安全与浏览器边界

- Web 构建产物不包含 AppCode、OTP pepper、数据库凭据、Android 私钥或签名密钥。
- Web 只持有 HttpOnly、Secure、SameSite Cookie；JavaScript 不能读取会话值。
- Caddy 与 FastAPI 使用同源部署，避免首版额外跨域配置；开发环境使用显式的本地允许来源。
- 发布配置设置严格 CSP、`X-Content-Type-Options`、`X-Frame-Options`、Referrer-Policy 和无缓存 API 响应。
- 二维码挑战、proof、Cookie、OTP 和设备签名不写入日志或前端持久化存储。

## 4. Web 工程结构

实施时创建独立目录：

```text
web/
├── package.json
├── package-lock.json
├── tsconfig.json
├── vite.config.ts
├── index.html
├── src/
│   ├── main.ts
│   ├── api/client.ts
│   ├── auth/web-session.ts
│   ├── auth/qr-login.ts
│   ├── sync/workspace-sync.ts
│   ├── tasks/task-model.ts
│   ├── ui/qr-login-view.ts
│   ├── ui/workspace-view.ts
│   └── styles.css
└── test/
    ├── qr-login.test.ts
    ├── api-client.test.ts
    └── workspace-sync.test.ts
```

Vite 只负责开发服务器和生产静态打包。业务 API 地址默认使用同源 `/api`，通过 `VITE_API_BASE_URL` 支持本地独立开发；生产构建不把任何后端 Secret 注入 JavaScript。

首版使用浏览器原生 DOM 和 `fetch`，避免引入 React 等 UI 框架。可以使用小型、锁定版本的 QR 编码库生成二维码，但二维码 payload 必须来自后端，不能由前端重建或修改。若 QR 库需要额外运行时资源，必须打包进 `web/dist`，不得依赖第三方 CDN。

## 5. Android Flutter 边界

Flutter 应用保留 Android 所需代码：

- `MobileLoginController`、短信登录和移动会话存储；
- Android Keystore 设备签名密钥；
- 设备加入/审批/撤销页面；
- 二维码扫描与 Web 挑战批准；
- Workspace 任务、冲突和同步页面。

Flutter 应删除或不再编译以下 Web 专用内容：

- `kIsWeb` Web 启动分支和 `AppPlatform.web`；
- Web API transport、Web 登录 repository/controller；
- Web QR 登录页面、Web 会话过期页面；
- `client/web/` 静态入口和 Flutter Web 图标；
- `client/integration_test/web_session_flow_test.dart`；
- 所有 `flutter build web` 命令和 Web 构建 artifact。

Android 的扫码页面继续调用 `/api/v1/web-login/challenges/{id}/scan` 和 `/approve`，因此 Web 技术替换不会改变授权协议。

## 6. 构建、部署与 CI

### 6.1 本地与发布构建

Web 本地命令：

```bash
cd web
npm ci
npm run test
npm run build
```

生产 Web 产物为 `web/dist`，可打包为 `web-release.tar.gz`。Android 产物仍由 Flutter 生成 debug APK 和签名 AAB。

部署镜像使用 Node 构建阶段生成 Web 静态文件，再复制到 Caddy 镜像；FastAPI 镜像只安装 Python 后端依赖，不安装 Node 或 Web 依赖。Caddy 只服务构建后的 `index.html`、静态资源并代理 API，不运行任何 Flutter Web 或 SSR 运行时。

### 6.2 GitHub Actions 触发规则

`ci.yml` 只在以下事件触发：

```yaml
on:
  push:
    tags:
      - 'v*.*.*'
  release:
    types: [published]
```

普通分支 push、普通 tag（不符合版本格式）和 Pull Request 不触发 CI。版本 tag 与 `release.published` 可能指向同一提交，工作流必须通过并发键或事件条件避免重复发布副作用；测试重复执行可以接受，但不得重复上传同名发布产物。

CI 分工：

- `backend`：PostgreSQL、Alembic、完整 pytest 和云协议测试；
- `android`：Flutter format/analyze/test、Android debug APK；
- `web`：Node 依赖安装、TypeScript 检查、Vitest、Vite build；
- `deployment`：Compose、Caddy 配置和无旧运行时引用检查。

`release.yml` 只在版本 tag 或已发布 Release 的发布流程中生成签名 Android AAB 和 Web 静态压缩包。未配置 Android 签名 Secret 时，发布工作流必须明确失败，不得回退为“看似成功”的未签名产物。

## 7. 测试与验收

### Web 单元与构建

- API client 测试验证同源路径、Cookie credentials、JSON 错误解析和 `401` 会话清理；
- QR login 测试验证 proof 摘要、挑战轮询、批准后兑换和过期/撤销状态；
- sync 测试验证快照、cursor 增量、游标过期回退和手动刷新；
- `npm run typecheck`、`npm run test`、`npm run build` 必须在干净依赖下通过。

### Android 与后端

- Flutter 只运行 Android 单元/widget 测试和条件启用的 Android emulator 集成测试；不再执行 Web device 测试；
- 后端协议测试继续覆盖真实 Web QR challenge、Android 签名批准、Cookie exchange、撤销和任务冲突；
- 发布验收至少验证 Android 扫码登录 Web、Web 创建任务、Android 读取变更、Web 会话撤销和重新扫码。

### 验收标准

1. `client/` 不再包含可构建的 Flutter Web 入口，`flutter build web` 不属于任何 CI 或发布命令。
2. `web/` 可独立 `npm ci && npm run test && npm run build`，生成可由 Caddy 直接服务的静态目录。
3. 浏览器能通过 Android 扫码获得最长 18 小时 Web 会话，并能在设备撤销后立即失效。
4. Web 与 Android 使用同一 Workspace 数据、cursor 和冲突响应。
5. 普通 push 和 Pull Request 不启动 CI；版本 tag 与 `release.published` 启动检查，且不会产生重复发布副作用。
6. 发布产物包含 Android AAB 和 Web 静态包，不包含 IPA 或 Flutter Web 包。

## 8. 迁移顺序与非目标

实施按以下顺序进行：先搭建 Web API client 与测试，再完成二维码登录和任务页面；随后删除 Flutter Web 分支并更新 Android-only 构建；最后切换 Caddy/Compose、CI 和 release artifacts，执行全量协议与构建验收。

本规格不包含 iOS 实现、离线写入、任务端到端加密、FastAPI 模板渲染、后端 API 重构、数据库迁移策略变化或 UI 视觉重制。若 Web 未来需要复杂交互，可在不改变 API 合同的前提下引入组件框架。
