# 开发状态与变更记录

本文是工程开发过程的状态入口。每次开始或完成一个阶段、发现验收差异、调整设计方案或改变范围时，必须先更新本文或关联设计文档，再提交代码。

## 当前状态

- 当前阶段：Python 3.12 版 Task 1 已创建测试契约和项目元数据，等待工具链验证后继续。
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

## 当前实施顺序

严格按以下顺序推进，前一项未通过验收不得跳到后一项：

1. 仓库与运行时骨架；
2. PostgreSQL 迁移与两名固定用户初始化；
3. 密码、JWT 和 Refresh Session；
4. FastAPI HTTP API 与统一错误契约；
5. Flutter Android/Web 登录与账户页；
6. Compose、CI 和端到端验收。

## 当前阻塞

## 设计变更

### 2026-08-16 - 后端从 Go 切换为 Python 3.12

- 类型：设计变更
- 变更：后端由 Go 切换为 Python 3.12 + FastAPI + SQLAlchemy 2.0 + Alembic + psycopg + pytest；REST API、数据库模型、客户端和验收标准保持不变。
- 原因：项目维护者更熟悉 Python；当前只有 Go 测试契约，尚无 Go 业务实现，切换风险低。
- 影响文件：`docs/02-technical-design.md`、`docs/superpowers/specs/2026-08-16-project-foundation-design.md`、`docs/superpowers/plans/2026-08-16-project-foundation-auth.md`。
- 替代方案：保留 Go、改用 Flask 或采用 Django REST Framework；综合开发熟悉度、自动 API 契约和项目规模后选择 FastAPI。
- 迁移影响：无数据库迁移；后端工程骨架和依赖安装方式重新生成。
- 验收影响：服务端测试命令改为 `pytest`，容器镜像改为 Python 3.12；API 行为验收不变。

### 2026-08-16 - Task 1 Python 工具链阻塞

- 类型：阻塞
- 变更：已创建 `backend/pyproject.toml`、`backend/app/__init__.py` 和 `backend/tests/core/test_config.py`；测试尚未完成红灯验证。
- 原因：宿主机 Python 为 3.14 且没有 pip/venv；Python 3.12 Docker 镜像拉取在 Registry 网络阶段卡住；Flutter/Dart 仍未安装。
- 影响文件：`backend/pyproject.toml`、`backend/app/__init__.py`、`backend/tests/core/test_config.py`。
- 验证命令与结果：`docker info` 已可返回 Docker Server 版本；`docker run ... python:3.12-slim` 未完成镜像拉取；`python3 -m venv` 返回 `ensurepip is not available`。
- 下一步：安装 Python pip/venv 或提供可用 Python 3.12 镜像后，执行 `python -m pytest tests/core/test_config.py -q` 的红灯验证；工具链恢复前不标记 Task 1 完成。

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
