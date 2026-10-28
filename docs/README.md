# 设计文档索引

项目总览见 [根 README](../README.md)；项目介绍官网本地入口为 `/about/`，运行与构建方式见根 README。GitHub Pages 静态首页为本目录的 `index.html`，配置发布源 `main /docs`；`_config.yml` 排除工程资料，仅发布首页与 assets。

## 产品核心价值

> Muyu 帮助两个人把拖延变成可见的协作事实，把模糊责任变成明确的下一步，并通过双方确认完成任务闭环。

本目录记录双人协作行动管理系统在进入工程开发前已经确认的产品和技术设计。

## 当前规格

1. [云端协调双人协作架构规格](./superpowers/specs/2026-08-24-cloud-coordinated-collaboration-design.md)
   - 云端明文事实源、短信认证、设备审批和 Web 扫码会话；
   - PostgreSQL 事务、字段级冲突、cursor 增量同步与通知；
   - Android APK/AAB 与 Web 静态构建的共同发布和验收边界。
2. [Android 与独立 Web 客户端边界设计](./superpowers/specs/2026-08-25-android-web-client-boundary-design.md)
   - Flutter 只负责 Android；
   - TypeScript + Vite 负责独立 Web SPA；
   - FastAPI 只提供 API，Caddy 服务 Web 静态构建并代理 API。
3. [Web 前端视觉方向设计](./superpowers/specs/2026-08-31-web-frontend-visual-direction-design.md)
   - 固定“安静留白 + 柔和生活感”的产品气质；
   - 使用顶部轻导航、重点任务和线性行动列表，避免传统后台控制台；
   - 定义桌面与未来 Windows 适配的设计令牌、禁用模式和视觉验收标准。
4. [Android 客户端视觉方向设计](./superpowers/specs/2026-08-31-android-visual-direction-design.md)
   - 与 Web 共享颜色、层级、文案和状态语义；
   - 基于 Material 3、底部导航、触控和系统返回设计实际页面；
   - 明确跨端必须一致、可以不同和禁止偏离的视觉边界。
5. [产品路线与单人起步、双人验收设计](./superpowers/specs/2026-09-10-product-roadmap-and-bootstrap-completion-design.md)
   - 单人 Workspace 自动提供个人起步分类；
   - 第二位成员加入后切换到共享分类和双人协作；
   - 任务必须由另一位成员验收后才能完成。
6. [Muyu「此刻」协作链浏览器原型设计](./superpowers/specs/2026-09-11-moment-collaboration-prototype-design.md)
   - 将清单 Tab 定义为默认的「此刻」协作工作台；
   - 冻结“需要我处理、等对方、本周到期”入口和“卡住、我在推进、对方在推进”主体分组；
   - 明确交接、验收、退回和活动证据的双人协作闭环。

## 待执行实施计划

1. [Android 首个共享空间引导实施计划](./superpowers/plans/2026-08-26-android-first-workspace-bootstrap.md)
   - 登录后查询当前 Workspace；
   - 新用户显式创建首个共享空间；
   - 创建后才开放任务页与 Web 扫码授权。
2. [任务领域完整实施计划](./superpowers/plans/2026-08-27-task-domain-completion.md)
   - 完成任务创建、编辑、状态、评论、延期和冲突处理；
   - 统一 Android 与 Web 的云端任务同步和验收流程。
3. [Web 前端视觉重构实施计划](./superpowers/plans/2026-08-31-web-frontend-visual-implementation.md)
   - React + Vite 渐进迁移；
   - 今天、所有任务、审批、动态和任务详情页面；
   - 设计令牌、响应式、无障碍和 Playwright 视觉验收。
4. [Muyu「此刻」协作闭环生产实施计划](./superpowers/plans/2026-09-11-moment-collaboration.md)
   - 后端 Home 投影、交接/验收请求内容和活动证据；
   - Android 此刻首页、任务详情下一步和双用户动作权限；
   - cursor 同步、回归测试、双设备验收和发布回滚门禁。

## 关联资料

1. [产品需求](./01-product.md)
   - 产品定位；
   - 用户模型；
   - 任务、子任务、事件和循环任务；
   - 首页和反拖延原则；
   - MVP 范围。

2. [技术设计（历史 Phase 0-3 基线）](./02-technical-design.md)
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

6. [首个共享空间操作说明](./operations/first-workspace-setup.md)
   - Android 登录后的首个 Workspace 创建；
   - Android 扫码批准 Web 登录；
   - 双人 Workspace 成员授权边界。

7. [工程规格（历史）](./superpowers/specs/2026-08-16-project-foundation-design.md)
   - 首轮工程基础与双人认证设计。

8. [实施计划（历史）](./superpowers/plans/2026-08-16-project-foundation-auth.md)
   - 首轮工程任务分解和测试验收步骤。

9. [Local-first P2P 双人同步架构规格（历史）](./superpowers/specs/2026-08-21-local-first-p2p-architecture-design.md)
   - 两台 Android 设备直连同步、设备身份、事件加密、事件合并和换机规则。

10. [Local-first P2P 实施计划（历史）](./superpowers/plans/2026-08-21-local-first-p2p.md)
   - 本地 SQLite Event Store、加密事件、确定性合并、P2P 续传和 Android 验收任务。

## 当前状态

当前运行时设计已转为云端协调协作：PostgreSQL 是明文事实源，Android 和 Web 使用同一 FastAPI API、cursor 和冲突规则。Android 只构建 APK/AAB，独立 TypeScript + Vite 应用构建 `web/dist`，Caddy 负责静态文件和 API/WebSocket 反向代理。当前产品路线优先处理单人起步、双人加入、双人验收、同步可靠性和任务可发现性；最新的默认工作台是「清单 → 此刻」，其生产施工边界见[Muyu「此刻」协作闭环生产实施计划](./superpowers/plans/2026-09-11-moment-collaboration.md)。密码、验证码、令牌和 Cookie 等敏感信息不得写入文档或代码；部署 Secret 由环境注入。所有工程进度和设计变更记录在 [开发状态与变更记录](./05-development-status.md)。

## 历史基线验收

轻量行动闭环：创建任务后可指派一名或两名成员，按 `TODO`、`IN_PROGRESS`、`WAITING`、`DONE`、`CANCELLED` 流转；`WAITING` 要求原因和恢复负责人，延期、评论和活动记录只追加。Web 和 Android 提供我的任务、全部任务、列表/看板投影，并在网络失败时只展示可能过期快照，不执行离线写入。本阶段不支持附件、依赖图、自定义工作流或新增项目/团队层级。

以下命令只验收历史 Phase 0-3 服务端基线，不验证当前云端协调架构。新架构的 PostgreSQL、Android APK/AAB 和 Web 静态构建验收命令将在实施计划中定义。

```bash
make test
make compose-clean
API_PORT=8090 make compose-up
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-auth.sh
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-tasks.sh
API_BASE_URL=http://localhost:8090 AUTH_PASSWORD=change-this-shared-password ./scripts/smoke-delay-blocking.sh
```

默认 Compose 不暴露 PostgreSQL 端口，只暴露可配置的 API 端口。`deploy/.env.example` 仅用于本地验收模板；正式部署必须替换密码和 JWT Secret。
