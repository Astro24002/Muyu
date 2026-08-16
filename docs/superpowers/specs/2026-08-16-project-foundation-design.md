# 工程基础与双人认证设计规格

## 1. 目标与范围

本规格定义第一轮工程交付，目标是让项目从空设计仓库变成可本地运行、可测试、可在 Android/Web 登录的单仓库应用。

本轮包含：

- 初始化 Git 和单仓库目录边界；
- Go API、PostgreSQL、Docker Compose 本地运行链路；
- 两名固定用户的幂等初始化；
- 手机号 + 统一密码登录；
- Access Token、Refresh Token、刷新、登出和会话撤销；
- 当前用户资料读取和昵称/角色修改；
- 双方用户信息读取；
- Flutter Android/Web 登录态和最小用户资料界面。

本轮不包含任务、子任务、事件、循环任务、评论、冲突、统计、Push、WebSocket、正式 ECS 部署和改密码。

## 2. 方案与仓库边界

采用单仓库垂直切片。客户端和服务端共享同一份设计文档，但不直接共享运行时代码；API 通过 OpenAPI 风格的 JSON 契约连接双方。

```text
.
├── backend/                  # Go API
│   ├── cmd/server/            # 进程入口
│   ├── internal/config/       # 环境变量解析与校验
│   ├── internal/auth/         # 登录、Token、会话
│   ├── internal/user/         # 固定用户和资料
│   ├── internal/httpapi/      # 路由、中间件、错误响应
│   └── migrations/            # PostgreSQL 迁移
├── client/                   # Flutter Android/Web
├── deploy/                   # Compose、反向代理和环境模板
├── docs/                     # 产品、技术、路线及规格
└── .github/workflows/        # 基础 CI（可在实现阶段加入）
```

服务端使用 Go 标准库 HTTP 栈，数据库驱动采用 pgx，密码哈希采用 bcrypt，JWT 使用成熟的 Go JWT 库。业务逻辑通过领域服务与 HTTP 适配层分离，避免路由处理器直接操作数据库。

客户端使用 Flutter，按 `data`、`domain`、`presentation` 分层。首轮不引入复杂状态管理框架：认证状态由一个可测试的会话控制器维护，HTTP 客户端、JSON 模型和本地 Token 存储通过接口注入。

## 3. 运行链路

### 3.1 本地启动

`deploy/docker-compose.yml` 启动 PostgreSQL 和 API。API 启动时等待数据库可用，执行版本化迁移，然后进行固定用户幂等初始化，最后提供健康检查。

Flutter 通过 `API_BASE_URL`（Web）或构建参数（Android）指定 API 地址。开发环境不要求 HTTPS；生产环境只允许 Caddy/Nginx 暴露 API，数据库不暴露公网端口。

### 3.2 配置

必须配置：

- `DATABASE_URL`；
- `AUTH_PASSWORD`：两名用户共用的初始密码；
- `JWT_ACCESS_SECRET`；
- `JWT_REFRESH_SECRET`；
- `ACCESS_TOKEN_TTL`，默认 15 分钟；
- `REFRESH_TOKEN_TTL`，默认 30 天；
- `HTTP_ADDR`，默认 `:8080`。

生产配置只通过 Secret 注入。仓库只提交 `.env.example`，不提交真实密码、密钥或数据库凭据。

## 4. 数据模型与迁移

首轮只创建 `users`、`sessions` 和迁移元数据表。

### users

```text
id             UUID primary key
phone          varchar unique not null
password_hash  varchar not null
nickname       varchar not null
avatar_key     varchar not null
role           varchar not null
created_at     timestamptz not null
updated_at     timestamptz not null
```

固定种子数据使用设计文档中的两个手机号。`id`、`phone`、`avatar_key` 由初始化逻辑固定；昵称和角色使用默认值但可由 API 修改。初始化必须使用唯一手机号冲突保护和事务，重复启动不能创建重复用户，也不能重置用户已修改的昵称、角色或密码。

### sessions

```text
id                 UUID primary key
user_id            UUID references users(id)
refresh_token_hash varchar not null
expires_at         timestamptz not null
revoked_at         timestamptz null
created_at         timestamptz not null
```

Refresh Token 轮换时撤销旧 session 并创建新 session。数据库永远不保存明文 Refresh Token。

迁移必须可重复执行，失败时 API 不应报告健康状态。回滚脚本不是首轮要求，但每个迁移要有明确版本号和事务边界。

## 5. 认证与 API 契约

### 5.1 登录

`POST /api/auth/login`

请求：

```json
{"phone":"15028180169","password":"..."}
```

成功返回当前用户、短期 Access Token 和 Refresh Token。密码错误、手机号不存在和输入格式错误统一返回不会泄露账号存在性的认证错误；登录端点需要基础限流接口，具体生产限流参数留到部署阶段配置。

### 5.2 刷新、登出

- `POST /api/auth/refresh`：校验 Refresh Token、session 未撤销且未过期，执行轮换并返回新 Token；
- `POST /api/auth/logout`：撤销当前 Refresh Token 对应 session，重复调用保持幂等；
- Access Token 失效统一返回 `401 UNAUTHORIZED`；
- Refresh Token 无效、过期或已撤销返回 `401 UNAUTHORIZED`，不得创建新 session。

### 5.3 用户接口

- `GET /api/me`：返回当前用户；
- `PATCH /api/me`：只允许更新 `nickname`、`role`，拒绝修改 `phone`、`avatar_key`、`id`；
- `GET /api/users`：返回两名用户的公开资料，按固定用户 ID 稳定排序。

成功的资料修改只更新允许字段和 `updated_at`；任务活动表在后续任务迁移中加入，不在本轮伪造任务事件。

### 5.4 错误格式

所有错误返回统一结构：

```json
{
  "code":"VALIDATION_ERROR",
  "message":"可供用户理解的简短信息",
  "details":{}
}
```

至少支持 `400 BAD_REQUEST`、`401 UNAUTHORIZED`、`404 NOT_FOUND`、`422 VALIDATION_ERROR`、`429 RATE_LIMITED` 和 `500 INTERNAL_ERROR`。服务端日志记录 request ID，响应不泄露 SQL、密码或 Token。

## 6. 客户端结构与流程

客户端首轮页面：登录页、登录后的账户页。登录成功后进入账户页，同时加载 `/api/me` 和 `/api/users`；刷新 Token 成功则恢复登录态，刷新失败则清理本地凭据并回到登录页。

Token 存储通过平台安全存储实现：Web 使用受限的浏览器存储封装，Android 使用安全存储；具体实现由 `TokenStore` 接口隔离，测试使用内存实现。HTTP 层遇到一次 `401` 时只尝试一次刷新，刷新失败不得形成无限重试。

登录、刷新、登出、资料读取和资料更新均提供加载中、成功、失败状态。资料更新失败时保留用户正在编辑的表单内容，不静默覆盖。

## 7. 测试与验收

### 服务端

- 密码哈希和校验：正确密码成功、错误密码失败；
- 固定用户初始化：空库创建两人，重复执行不重复、不重置资料；
- Token：签名校验、过期、错误类型、刷新轮换和撤销；
- API：登录成功/失败、`/me` 鉴权、资料字段白名单、登出幂等；
- 集成测试使用临时 PostgreSQL 或 Compose 测试数据库，迁移从空库开始执行。

### 客户端

- 登录成功进入账户页；
- 登录失败显示错误且不保存 Token；
- Access Token 过期时只刷新一次并继续原请求；
- Refresh Token 失败时清理会话并回到登录页；
- 资料编辑只提交允许字段；
- 登出后重新打开应用不保留登录态。

### 端到端验收

1. 本地启动 Compose，数据库迁移和 API 健康检查通过；
2. Android 和 Web 分别使用两组固定手机号登录；
3. 两端读取到相同的双方用户资料；
4. 一端修改昵称或角色，另一端刷新后可见；
5. 登出后 Refresh Token 不能再次换取 Access Token；
6. API、服务端测试和 Flutter 测试全部通过。

## 8. 后续演进约束

任务、活动记录、状态冲突和时间规则必须沿用现有技术设计，不为了首轮认证引入多租户、RBAC、Redis、消息队列或实时通信。新增数据表和接口都必须先落迁移/契约测试，再接入客户端，保持后续 Phase 2-3 可以在本架构上增量实现。
