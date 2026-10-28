# Muyu · 木鱼协作

**两个人的日常，一起向前一点点。**

Muyu 是 Android 优先的双人日常协作产品：安排事项、记录共同收支、坚持自己的习惯、记住重要的日子。每个人使用真实身份进入共享空间，一件事由一位负责人推进，完成结果由另一位成员确认。

[Android 发布下载](https://github.com/Astro24002/Muyu/releases) · [产品设计](Muyu-Codex-Design-and-Implementation.md) · [开发状态](docs/05-development-status.md) · [文档索引](docs/README.md)

## 项目介绍官网

官网源码位于 [`web/src/website/`](web/src/website/)，以独立页面 `/about/` 与 Web 应用一起构建。首页包含产品介绍、可切换的功能示意、协作流程及 Android/Web 入口。示意内容不连接业务 API。

```sh
cd web
npm ci
npm run dev -- --host 127.0.0.1
```

打开 **http://127.0.0.1:5173/about/** 查看官网；根路径 `/` 是原有 Web 应用。介绍页无需后端即可预览。构建命令为 `npm run build`，产物为 `web/dist/about/index.html`，共享资源位于 `web/dist/assets/`。GitHub Pages 使用独立静态构建，见下文。

## 一起管理日常

| 能力 | 可以做什么 |
| --- | --- |
| 事项 | 用此刻、四象限、日程查看同一份任务；记录下一步、一级子任务、阻塞、延期、评论和协作历史 |
| 交接与验收 | 对方确认后才交接负责人；负责人提交结果，另一位成员通过或说明原因退回 |
| 共享记账 | 记录收入/支出、付款或收款人，按月查看汇总与明细；金额以整数分保存 |
| 个人打卡 | 每日、每周、每月习惯；本人打卡与管理，对方可查看；支持撤销本期、暂停与恢复 |
| 纪念日 | 公历纪念日、准备天数、手动生成准备事项；生成事项进入同一任务协作流程 |
| 账户与设备 | 手机号登录、最多两名有效成员的共享空间、设备管理、Android 扫码授权 Web |

当前底部入口为 **事项 / 记账 / 打卡 / 我的**。事项通过标题菜单切换视图；默认“此刻”关注需要我处理、等对方、即将到期，并提供逾期和完成/归档折叠清单；“全部事情”位于“我的”。

可以先一个人开始，但没有另一位有效成员时不能独自验收完成。Muyu 不设置积分、排名、惩罚或绩效看板。

## 使用与交付状态

1. 从 [Releases](https://github.com/Astro24002/Muyu/releases) 获取 Android 安装包，按发布说明安装。
2. 使用真实手机号和短信验证码登录 Android，创建或进入共享空间。
3. 在 Web 应用发起二维码登录，用已授权的 Android 扫码确认；Web 获得临时会话。

截至 2026-10-28，开发记录已包含 Android **v0.2.1** 签名 APK 发布、Android/Web 任务及生活领域页面、生产数据库 `0018_task_invitations` 迁移记录。完整跨端、真实双人账户、真机视觉和无障碍验收仍有待完成项；本地实现、版本发布与生产部署分别记录，不能视作全部 v1 验收通过。最新证据和限制以 [开发状态](docs/05-development-status.md) 为准。

## 架构与技术栈

```text
Android · Flutter          Web · React / TypeScript
          \                 /
           FastAPI · 模块化单体
                     |
             PostgreSQL 16
```

- **服务端**：Python 3.12、FastAPI、SQLAlchemy 2、Alembic、PostgreSQL 16。
- **Android**：Flutter、Dart、Material 3；首版不构建 iOS 或 Linux 桌面客户端。
- **Web 与官网**：React 19、TypeScript、Vite、Lucide；Vitest 与 Playwright 验证。
- **部署**：Docker Compose、Caddy、GitHub Actions；数据库仅在内部网络暴露。

PostgreSQL 是共享事实源。REST snapshot / cursor changes 保证同步正确性，WebSocket 只提示更新。业务写入在同一事务中保存实体、版本、历史、审计、cursor 与幂等结果；现有实体写入需要期望版本。Android 可读取最后有效快照，但不支持离线提交。

任务保留 `TODO / IN_PROGRESS / BLOCKED / REVIEW / DONE / CANCELLED` 六个内部状态；审批请求拥有独立状态，不能用审批状态代替任务状态。

## 目录

```text
backend/        API、领域服务、迁移与服务端测试
client/         Flutter Android 客户端
web/            Web 应用与 /about/ 项目介绍官网
  about/        官网 HTML 入口
  src/website/  官网组件与样式
  e2e/          浏览器验证
deploy/        Compose、Caddy、备份与恢复工具
scripts/        构建、门禁与运维脚本
docs/           工程文档及 Pages 官网（index.html、assets/）
```

## 本地开发与验证

Web 需要 Node.js 22（与部署构建环境一致）和 npm。开发服务器默认代理项目已配置的 API；调试本地后端时显式指定目标：

```sh
cd web
npm ci
MUYU_API_PROXY_TARGET=http://127.0.0.1:8080 npm run dev
npm run typecheck
npm test -- --run
npm run build
npx playwright test e2e/website.spec.ts --project=desktop-1440 --workers=1
```

浏览器验证需要 Playwright Chromium：尚未安装时执行 `npx playwright install chromium`（Linux 可按环境安装系统依赖）。官网自身不发起 API 请求；根路径应用使用实际认证与 API。

从仓库根目录运行领域门禁：

```sh
make backend-test  # 需要 Docker 与可用的隔离 PostgreSQL 测试库
make client-test   # 需要 Flutter / Android 开发环境
make web-test
make web-build
make verify       # 还包括迁移、部署拓扑、旧运行时和客户端边界检查
git diff --check
```

后端测试与迁移通过 `TEST_DATABASE_URL` 指向**隔离测试数据库**，不要指向生产。凭据仅在本机环境或 Secret 中注入，不写入仓库或输出。

Android 本地 debug 包：

```sh
make client-build API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` 适用于 Android 模拟器访问宿主机；真机使用可达的开发 API 地址。正式签名包须走受保护的 [release workflow](.github/workflows/release.yml)，不能以 debug 包代替正式交付。

## 部署与进一步阅读

官网随现有 `deploy/web.Dockerfile` 构建，Caddy 从 `/srv` 服务静态文件并代理 API。部署整个 `web/dist`，不要只复制官网 HTML；生产的根路径仍是 Web 应用，介绍页为 `/about/`。该方式适用于现有服务器；GitHub Pages 使用以下独立产物。

- [官网规格与范围](docs/superpowers/specs/2026-10-28-project-website.md)
- [v1 契约与交付设计](docs/superpowers/specs/2026-09-16-muyu-v1-contract-and-delivery-design.md)
- [v1 分阶段计划](docs/superpowers/plans/2026-09-16-muyu-v1.md)
- [首个共享空间操作说明](docs/operations/first-workspace-setup.md)
- [运维文档目录](docs/operations/)
- [工程协作约束](AGENTS.md)

部署前核对迁移 head 与备份，按运行手册验证恢复；数据库凭据、短信服务密钥、会话 Token 和签名材料只通过部署 Secret 注入。

### GitHub Pages 静态页面

**发布目录：main 分支的 `/docs`；首页：[docs/index.html](docs/index.html)，资源：[docs/assets/](docs/assets/)。**

在仓库 Settings → Pages 中设置：

- Source：**Deploy from a branch**
- Branch：**main**
- Folder：**/docs**

保存后由 GitHub Pages 自动发布，无需自定义或手动工作流。默认地址为 `https://astro24002.github.io/Muyu/`，以 Pages 设置页的实际部署结果为准。

更新官网时，源码仍在 `web/src/website/`。运行：

```sh
cd web
npm ci
npm run export:website
```

导出先构建到 `web/dist-website/`，再更新 `docs/index.html` 和 `docs/assets/`，保留工程文档。将这些静态文件与源码一同提交到 main；不要直接把 Vite 的输出目录设为 docs（清理输出会误删文档）。

导出同时生成 `docs/_config.yml`，逐项放行首页、当前资源文件和自定义域名的 CNAME，现有工程文档不发布到官网。**不要添加 `.nojekyll`，否则会绕过此过滤。** `npm run test:website` 可验证独立构建在仓库子路径下的交互与资源。

官网使用相对资源路径；“打开 Web”指向 `https://muyu.bkverse.space/`。此前 gh-pages 分支保留为历史交付，当前维护及发布源均为 main/docs。仓库当前为私有，Releases 与项目文档链接仅对有仓库访问权的人可用；本次不更改仓库可见性。
