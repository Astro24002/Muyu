# 开发状态与变更记录

本文是工程开发过程的状态入口。每次开始或完成一个阶段、发现验收差异、调整设计方案或改变范围时，必须先更新本文或关联设计文档，再提交代码。

## 当前状态

- 当前阶段：Python 3.12 版 Task 1 已完成，准备进入 Task 2（数据库迁移和固定用户初始化）。
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
