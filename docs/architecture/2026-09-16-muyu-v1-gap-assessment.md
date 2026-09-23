# Muyu v1 接手差异清单

日期：2026-09-16；初次文档与定点代码复核：2026-09-17；最近状态复核：2026-09-23

2026-09-23 原型/代码差距复核：通过本地订阅启动临时 Mihomo，代理仅映射到宿主机 `127.0.0.1`；当前原型 HTML 与 `fonts.css`、`style.css`、`life.css`、`life.js`、`app.js` 均返回 200。Chromium 在 393×851 实载首页，并用当次 HTML/CSS/JS 检查“需要我处理”、记账、打卡/纪念日、我的、四象限和日程。实时 `style.css` 与 `app.js` 的校验和与 9 月 20 日存档一致；不要据此推断后续资源未变。当前代码确认的差异是：Android 打卡有当前范围的完成汇总，Web 已有 owner 筛选、逐项状态及近七日实际轨迹，但缺聚合本期数量；本轮补此只读投影。Android 真机像素对照、320/360/393/412、读屏和大字体验收仍 pending。

2026-09-22 生活领域同步、全量门禁与线上更新：账目、习惯、打卡和纪念日已由服务端统一 snapshot/changes 返回；Android/Web 客户端已增加资源模型、workspace cursor 合并、删除/撤销 tombstone 处理（包括无正文的 `DELETED` 事件按资源 ID 清除），增量打卡会更新习惯本期投影，记账和打卡页面消费同步快照，写入仍走正式 REST。隔离 PostgreSQL 上 `make verify` 通过：本地 head 迁移升级、后端 `303 passed, 3 skipped, 2 warnings`、Flutter 全量 `261 passed`、Web 全量 `288 passed`、typecheck/build、部署拓扑和边界检查均通过；生产已在备份后升至 `0018_task_invitations`，API/Web/Caddy healthy，公网 live/ready 为 200。并发、可配置时区、重启、线上回滚恢复、双用户和真实设备验收仍 pending。

2026-09-21 新版“事项”原型协议施工：当前站点新增按独立申请展示的“需要我处理”、任务邀请、整组约定修改/取消以及独立完成标准。Android/Web 已完成 `acceptance_criteria` 独立持久化、`TASK_INVITATION` 无任务申请和 agreement/cancellation 专用申请的本地实现：批准后才建 TA 负责任务或应用整组约定，拒绝/撤回不改任务事实，字段/生命周期并发和终态失效返回冲突，Home action count/page 识别申请；四象限新增负责人过滤，四象限/日程限开放任务，日程支持回到今天。后端全量 `303 passed, 3 skipped, 2 warnings`，Web API 专项 `15 passed`，Flutter 仓储专项 `9 passed`；新迁移尚未部署生产，真机和真实双人验收仍 pending。

2026-09-20 视觉复核：直接浏览器访问私密 v4 仍受限制，但只读代理取得了该 URL 的 HTML/CSS/JS，隔离 Chromium 已形成 393×851 的页面和交互参考。Android 已恢复原型问候、调整此刻指标与任务卡，并将记账/打卡/纪念日改为正式领域数据驱动的原型式布局；Flutter 248 passed，debug APK 已重建。没有授权真机、逐日打卡历史 API、真实双人和像素对照，视觉与产品验收继续 pending。以下 2026-09-18 审计反映当时状态，不能再将“没有原型参照”作为当前事实。

2026-09-18 施工复核：Android 与 Web 的四入口壳层、事项标题视图菜单、Home v1 回应指标过滤、任务查询 API、`next_step_text` 字段/表单、`HANDLER_TRANSFER.proposed_next_step`、客户端契约 Header 和创建给 TA 原子流程已在本地实现并通过专项回归；记账、打卡、纪念日后端/API、Android 页面及 Web 正式 REST 页面已局部接入，统一 snapshot/changes 客户端资源模型、完整领域并发/时区回归、Workspace 可配置时区、完整来源筛选、线上真实双账户和设备验收仍未完成。原型 URL 在当时浏览器工具中被安全策略拒绝打开，未形成原型截图或交互证据；`adb devices` 没有授权设备，因此真机安装、截图和双设备人工验收仍为 pending。

## 当前工程

- 正式产品工程已经存在：Flutter Android 客户端、FastAPI/PostgreSQL 服务端，以及独立 React Web 客户端。
- Android 已使用短信登录、真实 Workspace 成员关系、服务端 cursor 同步和只读本地缓存；没有模拟身份切换作为生产路径。
- 任务已使用单一 `current_handler_id`，负责人转交需要另一位 ACTIVE 成员审批；验收由另一位成员通过或退回，并在事务中写入任务、审批请求、活动和 cursor。
- Android 已有「此刻」Home 投影、四象限、月历、任务详情和协作记录；三种视图读取同一份任务快照。

## 与 v1 基线的差异

| 领域 | 现状 | v1 施工决定 |
| --- | --- | --- |
| 底部导航 | 原实现为 `清单 / 四象限 / 日程 / 我的` | Android/Web 本地壳层已改为 `事项 / 记账 / 打卡 / 我的`；四象限和日程成为事项标题内视图，账本/打卡已接入正式 REST 页面和统一 snapshot/changes 消费，完整领域验收仍待完成。 |
| 事项标题 | 原实现为 `清单→此刻`、品牌栏和抽屉 | Android/Web 已改为可点击的 `此刻` 标题菜单并移除主事项页品牌/抽屉入口；真机视觉证据仍 pending。 |
| 首页 | 已有三指标和互斥 `blocked/mine/other` 投影 | 后端 canonical 计数/分页已收敛到交接/验收，旧广义审批字段继续兼容；Android/Web 已消费目标三段，首版业务时区已冻结为 `Asia/Shanghai`，Workspace 可配置时区仍待设计。 |
| 任务状态 | 历史兼容的 `TODO / IN_PROGRESS / BLOCKED / REVIEW / DONE / CANCELLED` 加审批请求 | 暂不破坏生产状态与迁移；Android 展示层先映射为 v1 文案。`CANCELLED`、重开和旧兼容路径保留；若收敛需另行设计，v1 不新增这些操作。 |
| 任务字段 | 现有分类、象限、`due_at`、负责人、审批与活动事实；已新增可空 `next_step_text` 和 `acceptance_criteria` | 字段、snapshot/changes、查询、Header、`proposed_next_step`、独立完成标准、创建邀请和整组 agreement/cancellation 申请已落地；业务时区可配置和完整来源筛选仍待后续批次。 |
| 记账、打卡、纪念日 | 后端独立模型/API、Android 页面和 Web 正式 REST 页面已存在；两端已补齐四类资源的 snapshot/changes 模型和游标合并 | 继续沿用独立领域模块；补齐并发/恢复/无障碍回归和线上/双用户验收，不能用任务数据或浏览器本地存储替代。 |
| 打卡页本期进度 | 当前原型含浅绿汇总块和圆形叶片标记；Android 原有汇总数但缺标记；Web 原有逐项 `checked_in` 与最近七日轨迹但缺整个汇总块 | 已补 Android 叶片标记和 Web 浅绿汇总块；Web 数量按当前 owner 筛选后的正式 Habit 集合计算，不新增服务端字段或事实源。Web 全量 291 passed，Flutter 全量 267 passed/analyze；真机验收 pending。 |
| 全部事情 | 原有列表可显示终态任务，但没有规范化查询入口 | 已增加服务端搜索/状态/负责人/历史/keyset 查询、`next_step_text` 搜索和事项次级入口；完整来源筛选和查询 UI 依赖批次 2。 |

## 复用与阻塞

- 复用：认证、双人 Workspace、设备会话、FastAPI 事务、乐观版本、幂等请求、cursor 同步、任务详情、审批服务和 Android 主题基础。
- 文档同步没有阻塞；功能施工仍有下表的协议/迁移设计前置项。记账、打卡和纪念日已接入独立 PostgreSQL schema、API 和客户端仓储，剩余同步与验收不能作为纯 UI 功能处理。
- 私密 v4 已通过只读代理在隔离浏览器审计；Android 真机像素和授权交互仍 pending。

## 补充差异与证据

主设计是最新目标；本表只记录现有代码与目标之间的缺口，不将工程建议当作已经实现。

| 目标 | 复核证据/现状 | 后续方案 |
| --- | --- | --- |
| 回应指标按申请计数 | Home 对 `TASK_INVITATION` 无 task_id 申请和带 marker 的 `TASK_UPDATE`/`TASK_DELETE` 使用同一申请 ID 口径纳入 action count/page；本周到期仍只查询已成立任务 | 保留申请谓词、去重和旧字段兼容；线上双用户和旧运行时回归仍待执行 |
| 统一业务时区自然周 | Home 返回 `HomeWeek(timezone="Asia/Shanghai")`，周边界以 UTC 瞬时表示 | 首版冻结时区和集中日期转换已落地并通过跨 UTC 日期测试；Workspace 可配置时区、LocalDate/时间点兼容和完整 DST 验证仍待施工 |
| 明确下一步、新建给 TA、完成标准、整组约定 | `next_step_text`、`acceptance_criteria`、目标成员、Header、交接拟议值和 agreement/cancellation endpoint 均已接入；新客户端邀请使用独立 `/task-invitations` | 邀请接受与约定批准的任务/审批/活动/Operation/cursor/幂等本地回归通过；业务时区可配置、线上双用户和设备验收仍 pending |
| 70/90/500/1000 长度 | 当前标题 200、描述 10000、review_content 5000 | 客户端/服务端统一计数，兼容历史长文本 |
| important/urgent | `backend/app/tasks/service.py` 使用 quadrant Q1～Q4 | 布尔输入与 quadrant 单源映射，不随日期改变 |
| 无截止与新建进行中 | 现有默认截止与 TODO 路径不同于目标 | 先设计新旧命令兼容，不直接改变旧 API |
| 打卡删除与纪念日生成 | 独立领域、迁移/API、Android/Web REST 页面与统一同步模型已在本地实现 | 仍需周期/时区并发、恢复、真实双用户和设备验收；不得把本地实现标成线上完成 |

最新方案见 [v1 契约](../superpowers/specs/2026-09-16-muyu-v1-contract-and-delivery-design.md)，验收与批次依赖见 [实施计划](../superpowers/plans/2026-09-16-muyu-v1.md)。2026-09-23 已通过本地 Clash/Mihomo 读取当前原型并核对主要页面；393×851 首页已有浏览器截图。授权 Android 真机、320/360/393/412 截图、键盘/安全区、大字体和读屏对照仍 pending。
