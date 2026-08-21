# 设计文档索引

本目录记录双人协作行动管理系统在进入工程开发前已经确认的产品和技术设计。

## 文档

1. [产品需求](./01-product.md)
   - 产品定位；
   - 用户模型；
   - 任务、子任务、事件和循环任务；
   - 首页和反拖延原则；
   - MVP 范围。

2. [技术设计](./02-technical-design.md)
   - 总体架构；
   - 数据模型；
   - 状态转换；
   - 延期、阻塞和冲突；
   - API；
   - 认证、时间和部署。

3. [开发路线](./03-roadmap.md)
   - Phase 0 至 Phase 9；
   - 每阶段目标和验收标准。

4. [已确认决策](./04-decisions.md)
   - 讨论中已经冻结的关键规则；
   - MVP 边界；
   - 后续开发的默认依据。

5. [开发状态与变更记录](./05-development-status.md)
   - 当前实施阶段；
   - 已完成工作和验收结果；
   - 设计变更与进度记录规则。

6. [工程规格](./superpowers/specs/2026-08-16-project-foundation-design.md)
   - 首轮工程基础与双人认证设计。

7. [实施计划](./superpowers/plans/2026-08-16-project-foundation-auth.md)
   - 首轮工程任务分解和测试验收步骤。

8. [Local-first P2P 双人同步架构规格](./superpowers/specs/2026-08-21-local-first-p2p-architecture-design.md)
   - 两台 Android 设备直连同步、设备身份、事件加密、事件合并和换机规则。

9. [Local-first P2P 实施计划](./superpowers/plans/2026-08-21-local-first-p2p.md)
   - 本地 SQLite Event Store、加密事件、确定性合并、P2P 续传和 Android 验收任务。

## 当前状态

当前已完成首轮 Python/FastAPI 后端、PostgreSQL 迁移、认证 API、Flutter Android/Web 客户端、Phase 2 Task Core，以及 Phase 3 延期和阻塞的服务端、客户端和 PostgreSQL 自动化验收。2026-08-21 起新架构转向两台 Android 客户端直接 P2P 同步，架构规格已通过复核，实现计划已形成，服务端任务数据路径和旧 Phase 4 状态冲突方案暂不继续实施。密码等部署敏感信息不写入文档和代码，使用部署环境 Secret 注入。所有工程进度和设计变更记录在 [开发状态与变更记录](./05-development-status.md)。

## 本地验收

以下命令只验收历史 Phase 0-3 的服务端基线；P2P 客户端验收按 [实施计划](./superpowers/plans/2026-08-21-local-first-p2p.md) 的任务逐步加入。

```bash
make test
make compose-clean
API_PORT=8090 make compose-up
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-auth.sh
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-tasks.sh
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-delay-blocking.sh
```

默认 Compose 不暴露 PostgreSQL 端口，只暴露可配置的 API 端口。`deploy/.env.example` 仅用于本地验收模板；正式部署必须替换密码和 JWT Secret。
