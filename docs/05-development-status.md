# 开发状态与变更记录

本文是工程开发过程的状态入口。每次开始或完成一个阶段、发现验收差异、调整设计方案或改变范围时，必须先更新本文或关联设计文档，再提交代码。

## 当前状态

- 当前阶段：首轮工程基础与认证实施计划（Task 1-6）已完成；等待进入路线图后续任务/事件功能。
- 产品与技术设计：已确认，分别见 [产品需求](./01-product.md)、[技术设计](./02-technical-design.md)、[开发路线](./03-roadmap.md)、[已确认决策](./04-decisions.md)。
- 首轮工程规格：[工程基础与双人认证设计规格](./superpowers/specs/2026-08-16-project-foundation-design.md)。
- 首轮实施计划：[Project Foundation And Auth Implementation Plan](./superpowers/plans/2026-08-16-project-foundation-auth.md)。
- Git：本地 `main` 已跟踪 GitHub `origin/main`；设计基线提交为 `1804216`，实施计划与状态记录提交为 `cd8820b`。

## 已完成

### 2026-08-16

- 完成产品、技术、路线和决策文档审阅。
- 初始化 Git 仓库并建立 `main` 分支。
- 将当前设计内容同步到 `Astro24002/Muyu` 的 `origin/main`。
- 形成并提交首轮工程规格。
- 形成首轮工程实施计划。
- 完成 Python 3.12/FastAPI 运行时骨架、配置校验、Dockerfile、Compose 和健康检查。
- 完成 SQLAlchemy 模型、Alembic `users`/`sessions` 迁移、固定用户幂等初始化、用户仓库和启动生命周期接线。

## 当前实施顺序

严格按以下顺序推进，前一项未通过验收不得跳到后一项：

1. 仓库与运行时骨架；
2. PostgreSQL 迁移与两名固定用户初始化；
3. 密码、JWT 和 Refresh Session；
4. FastAPI HTTP API 与统一错误契约；
5. Flutter Android/Web 登录与账户页；
6. Compose、CI 和端到端验收。

## 设计变更

### 2026-08-16 - 后端从 Go 切换为 Python 3.12

- 类型：设计变更
- 变更：后端由 Go 切换为 Python 3.12 + FastAPI + SQLAlchemy 2.0 + Alembic + psycopg + pytest；REST API、数据库模型、客户端和验收标准保持不变。
- 原因：项目维护者更熟悉 Python；当前只有 Go 测试契约，尚无 Go 业务实现，切换风险低。
- 影响文件：`docs/02-technical-design.md`、`docs/superpowers/specs/2026-08-16-project-foundation-design.md`、`docs/superpowers/plans/2026-08-16-project-foundation-auth.md`。
- 替代方案：保留 Go、改用 Flask 或采用 Django REST Framework；综合开发熟悉度、自动 API 契约和项目规模后选择 FastAPI。
- 迁移影响：无数据库迁移；后端工程骨架和依赖安装方式重新生成。
- 验收影响：服务端测试命令改为 `pytest`，容器镜像改为 Python 3.12；API 行为验收不变。

## 实施进度

### 2026-08-16 - Task 1 Python 运行时与配置骨架

- 类型：实施进度 / 验收
- 变更：新增 Python 3.12 项目元数据、Pydantic Settings 配置、FastAPI 应用和 `/healthz`、Python Dockerfile、PostgreSQL Compose 和开发 Makefile。
- 原因：为 Phase 0/1 的迁移、固定用户初始化、认证 API 和 Flutter 联调提供可复现的运行底座。
- 影响文件：`.gitignore`、`Makefile`、`backend/`、`deploy/`。
- 验证命令与结果：在 `m.daocloud.io/docker.io/library/python:3.12-slim` 中运行 pytest，9 项通过；`python -m compileall -q app` 通过；`docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config` 通过；镜像构建成功；容器 `GET /healthz` 返回 `{"status":"ok"}`。
- 下一步：Task 2，使用 Alembic 创建 `users`/`sessions` 迁移，并实现两名固定用户的幂等初始化。

### 2026-08-16 - Docker 镜像源调整

- 类型：设计变更 / 工程配置
- 变更：所有 Docker 基础镜像统一改用 `m.daocloud.io/docker.io` 前缀。
- 原因：默认 Docker Registry 拉取不稳定，Daocloud 镜像源已验证可用。
- 影响文件：`backend/Dockerfile`、`deploy/docker-compose.yml`、技术规格和实施计划。
- 验证命令与结果：成功拉取 `m.daocloud.io/docker.io/library/python:3.12-slim`，并用该镜像运行测试和构建 API 镜像。
- 下一步：后续新增 Docker 镜像继续使用该镜像源并在文档中记录。

### 2026-08-16 - Task 2 数据库与固定用户初始化实现

- 类型：实施进度 / 部分验收
- 变更：新增 SQLAlchemy 2.0 数据模型、Alembic 首个迁移、用户仓库、固定用户初始化服务，并将迁移和初始化接入 FastAPI lifespan；新增启动顺序测试。
- 原因：完成首个持久化垂直切片，保证 API 只有在迁移和两名固定用户初始化成功后才报告健康。
- 影响文件：`backend/alembic.ini`、`backend/alembic/`、`backend/app/db/`、`backend/app/user/`、`backend/app/main.py`、`backend/tests/`。
- 验证命令与结果：容器内 `python -m compileall -q app alembic` 通过；使用 `sqlite:////tmp/muyu-test.db` 运行 `tests/core tests/test_main.py tests/test_main_startup.py tests/db tests/user`，14 项通过；启动生命周期顺序测试通过。PostgreSQL 集成测试尚未完成：`m.daocloud.io/docker.io/library/postgres:16-alpine` manifest 返回 `403 DENIED`，无法启动 Compose 数据库。
- 下一步：恢复可用的 DaoCloud PostgreSQL 镜像访问后，运行 Compose 集成测试，确认迁移、重复初始化和 `users` 数量为 2，再关闭 Task 2 验收并进入 Task 3。

### 2026-08-17 - Task 2 PostgreSQL Compose 集成验收

- 类型：验收 / 阻塞解除
- 变更：使用 Docker Compose 启动 PostgreSQL，并在同一 Compose 网络中启动 API、运行完整后端测试和重复初始化验证。
- 原因：此前未完成 PostgreSQL 容器集成验收；当前 Docker 权限恢复且镜像可用后，需要验证真实 PostgreSQL 路径而非仅 SQLite 测试路径。
- 影响文件：无运行时代码变更。
- 验证命令与结果：`docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml build api` 成功；PostgreSQL 健康检查通过；Compose 网络内的 `python -m pytest -q` 测试容器以退出码 0 完成；API 两次启动后内部 `GET /healthz` 均返回 `{"status":"ok"}`；`SELECT count(*) FROM users` 返回 `2`。宿主机 8080 已被其他项目占用，因此本次 API 使用 `docker compose run --no-deps` 在内部网络验收，未修改默认 Compose 端口配置。
- 下一步：进入 Task 3，实现密码、JWT 和 Refresh Session。

### 2026-08-17 - Task 3 密码、JWT 和 Refresh Session

- 类型：实施进度 / 验收
- 变更：新增 bcrypt 密码散列校验、严格区分 Access/Refresh 的 JWT 管理器、Refresh Token SHA-256 哈希会话仓储，以及登录、刷新轮换和幂等登出服务；认证测试目录增加包标记，避免同名测试模块冲突。
- 原因：完成认证服务垂直切片，为后续 FastAPI 路由提供稳定的领域接口。
- 影响文件：`backend/app/auth/`、`backend/tests/auth/`、`backend/tests/user/__init__.py`。
- 验证命令与结果：认证测试 `12 passed`；PostgreSQL Compose 网络内完整后端测试 `26 passed`；`python -m compileall -q app alembic` 通过。测试覆盖密码正确/错误校验、JWT 签名/类型/过期校验、登录、Refresh 轮换撤销、无效凭据、过期令牌和幂等登出。
- 下一步：进入 Task 4，实现 FastAPI 认证与用户资料路由、鉴权依赖和统一错误响应。

### 2026-08-17 - Task 4 FastAPI 路由、鉴权依赖和错误契约

- 类型：实施进度 / 验收
- 变更：新增统一错误响应与 `X-Request-ID` 中间件、数据库和 Bearer Token 依赖、认证路由、当前用户资料路由及双方用户列表路由；应用生命周期创建 TokenManager 并接入路由。
- 原因：将认证领域服务接入可供 Flutter/Web 消费的 HTTP JSON 契约。
- 影响文件：`backend/app/httpapi/`、`backend/app/auth/routes.py`、`backend/app/user/routes.py`、`backend/app/main.py`、`backend/tests/httpapi/`、启动测试 mock。
- 验证命令与结果：HTTP API 测试 `5 passed`；PostgreSQL Compose 网络内完整后端测试 `31 passed`；`python -m compileall -q app alembic` 通过；真实 Compose API 生命周期健康检查返回 `{"status":"ok"}`，认证冒烟验证登录、`/api/me`、Refresh 轮换、旧令牌拒绝、登出和撤销后拒绝全部通过。测试输出有 1 条现有 Starlette/httpx 弃用警告，不影响结果。
- 下一步：进入 Task 5，实现 Flutter Android/Web 登录与账户页。

### 2026-08-17 - Task 5 Flutter 环境准备

- 类型：阻塞解除 / 工程环境
- 变更：在当前用户目录安装 Flutter 3.47.0、Dart 3.13.0、Temurin JDK 17.0.20、Android SDK 36、Build Tools 36.0.0 和 Platform Tools，并在 `~/.bashrc` 配置用户级环境变量。
- 原因：Flutter Android/Web 客户端必须通过 Flutter SDK 生成、测试、分析和构建。
- 影响文件：用户级 `~/.bashrc` 和 `/home/muyu/develop/` 工具目录；无客户端代码变更。
- 验证命令与结果：`flutter --version`、`dart --version`、`java -version` 和 `adb --version` 均通过；`flutter doctor -v` 的 Flutter 与 Android toolchain 检查通过，Android 许可证全部接受。Chrome 和 Linux desktop 工具未安装，不影响计划中的 Web 编译和 Android 构建。
- 下一步：生成 `client/` Flutter Android/Web 工程并继续 Task 5。

### 2026-08-17 - Task 5 Flutter Android/Web 客户端

- 类型：实施进度 / 验收
- 变更：生成仅包含 Android/Web 的 Flutter 工程；实现 API 配置、JSON 模型、平台 Token 存储、登录/刷新/登出仓库、401 单次刷新、会话控制器、登录页和账户资料页；后端增加本地 Web CORS 预检支持；Android 主清单加入网络权限，debug 仅允许明文 HTTP。
- 原因：完成首个可操作客户端垂直切片，覆盖两名固定用户的登录态恢复、资料修改和退出流程。
- 影响文件：`client/`、`backend/app/main.py`、`backend/tests/httpapi/test_cors.py`。
- 兼容性决策：`flutter_secure_storage 11.0.0` 要求 Android compile SDK 37，而 Flutter 3.47 工程默认 compile SDK 为 36；锁定 `flutter_secure_storage 10.0.0`，保持 Android SDK 36 基线并避免依赖平台命名兼容问题。
- 验证命令与结果：客户端 `dart format --output=none --set-exit-if-changed .`、`flutter analyze` 和 `flutter test` 通过（12 项）；`flutter build web --dart-define=API_BASE_URL=http://localhost:8090` 成功；`flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8090` 成功；后端完整测试 32 项通过；CORS 预检、API 健康检查和真实登录冒烟通过。Linux desktop feature 保持关闭。
- 下一步：Task 6，补充 Compose/API/Flutter CI 和完整认证端到端脚本。

### 2026-08-17 - Task 6 Compose、CI 和端到端验收启动

- 类型：实施进度
- 变更：开始补充 Compose API 健康检查、可配置宿主端口、认证 smoke 脚本、Makefile 统一入口和 GitHub Actions。
- 原因：将前五项垂直切片收敛为可重复启动、测试和验收的工程流程。
- 影响文件：`.github/workflows/ci.yml`、`scripts/smoke-auth.sh`、`deploy/`、`Makefile`、`docs/README.md`。
- 验证命令与结果：随后完成干净 PostgreSQL Compose 卷、认证 smoke、完整测试和 API 重启持久性验收，详见下方 Task 6 完成记录。
- 下一步：先完成 smoke 脚本和 Compose/CI wiring，再用干净 PostgreSQL 卷运行完整验收。

### 2026-08-17 - Task 6 Compose、CI 和端到端验收

- 类型：验收 / 实施完成
- 变更：新增 API 容器健康检查和可配置宿主端口；新增不输出 Token/密码的双用户认证 smoke 脚本；Makefile 增加后端、客户端、Compose、清理和 smoke 入口；GitHub Actions 增加 PostgreSQL 后端测试与 Flutter format/analyze/test；补充跨 SQLite/PostgreSQL 的 UTC datetime 类型。
- 原因：把首轮垂直切片收敛为可重复执行的本地和 CI 验收流程，并修复 SQLite 测试环境中的 naive/aware datetime 差异。
- 影响文件：`.github/workflows/ci.yml`、`scripts/smoke-auth.sh`、`deploy/docker-compose.yml`、`deploy/.env.example`、`Makefile`、`backend/app/db/types.py`、`backend/app/user/models.py`、`docs/README.md`。
- 验证命令与结果：`make backend-test` 通过（32 passed，SQLite）；`make client-test` 通过（12 tests，format/analyze clean）；隔离全新 PostgreSQL Compose 项目 `task6` healthcheck 通过；`AUTH_PASSWORD=change-this-shared-password API_BASE_URL=http://localhost:8091 ./scripts/smoke-auth.sh` 通过；PostgreSQL 网络内完整后端测试 32 passed；API 重启后仍 healthy，数据库用户数保持 2 且资料未被重置；Compose config、Shell syntax 和 CI YAML 检查通过。
- 下一步：首轮基础与认证验收完成，进入路线图后续任务/事件功能开发。

## 文档变更规则

- 新方案先写入对应规格或决策文档，再进入代码实现。
- 设计变化必须说明：变更原因、影响范围、替代方案、是否需要迁移，以及对验收标准的影响。
- 每个实施任务完成后，更新本文的状态、测试命令和验收结果。
- 测试失败、环境阻塞和未完成项必须如实记录，不用“已完成”掩盖。
- 代码提交信息应能对应一个文档中的实施任务或文档变更。

## 记录模板

```markdown
### YYYY-MM-DD - [任务或变更名称]

- 类型：实施进度 / 设计变更 / 验收 / 阻塞
- 变更：
- 原因：
- 影响文件：
- 验证命令与结果：
- 下一步：
```
