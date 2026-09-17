# Muyu v1 接手差异清单

日期：2026-09-16；文档与定点代码复核：2026-09-17

2026-09-17 施工复核：Android 与 Web 的四入口壳层、事项标题视图菜单、Home v1 回应指标过滤、任务查询 API 和 `next_step_text` 字段/表单已在本地实现并通过专项/全量回归；记账、打卡、纪念日仍为未开放状态，交接拟议下一步和创建给 TA 的原子流程仍缺失。原型 URL 在当前浏览器工具中被安全策略拒绝打开，未形成原型截图或交互证据；`adb devices` 没有授权设备，因此真机安装、截图和双设备人工验收仍为 pending。

## 当前工程

- 正式产品工程已经存在：Flutter Android 客户端、FastAPI/PostgreSQL 服务端，以及独立 React Web 客户端。
- Android 已使用短信登录、真实 Workspace 成员关系、服务端 cursor 同步和只读本地缓存；没有模拟身份切换作为生产路径。
- 任务已使用单一 `current_handler_id`，负责人转交需要另一位 ACTIVE 成员审批；验收由另一位成员通过或退回，并在事务中写入任务、审批请求、活动和 cursor。
- Android 已有「此刻」Home 投影、四象限、月历、任务详情和协作记录；三种视图读取同一份任务快照。

## 与 v1 基线的差异

| 领域 | 现状 | v1 施工决定 |
| --- | --- | --- |
| 底部导航 | 原实现为 `清单 / 四象限 / 日程 / 我的` | Android/Web 本地壳层已改为 `事项 / 记账 / 打卡 / 我的`；四象限和日程成为事项标题内视图，账本/打卡仍未开放。 |
| 事项标题 | 原实现为 `清单→此刻`、品牌栏和抽屉 | Android/Web 已改为可点击的 `此刻` 标题菜单并移除主事项页品牌/抽屉入口；真机视觉证据仍 pending。 |
| 首页 | 已有三指标和互斥 `blocked/mine/other` 投影 | 后端 canonical 计数/分页已收敛到交接/验收，旧广义审批字段继续兼容；Android/Web 已消费目标三段，业务时区仍待冻结。 |
| 任务状态 | 历史兼容的 `TODO / IN_PROGRESS / BLOCKED / REVIEW / DONE / CANCELLED` 加审批请求 | 暂不破坏生产状态与迁移；Android 展示层先映射为 v1 文案。`CANCELLED`、重开和旧兼容路径保留；若收敛需另行设计，v1 不新增这些操作。 |
| 任务字段 | 现有分类、象限、`due_at`、负责人、审批与活动事实；已新增可空 `next_step_text` | 字段、snapshot/changes、查询和 Android/Web 创建/编辑已落地；`proposed_next_step`、header 强制和创建给 TA 原子交接仍待批次 2。 |
| 记账、打卡、纪念日 | 尚未实现数据模型、API 或 Android 界面 | 实施计划批次 3/4（主设计阶段 3）新增独立领域模块；不能用任务数据或浏览器本地存储替代。 |
| 全部事情 | 原有列表可显示终态任务，但没有规范化查询入口 | 已增加服务端搜索/状态/负责人/历史/keyset 查询、`next_step_text` 搜索和事项次级入口；完整来源筛选和查询 UI 依赖批次 2。 |

## 复用与阻塞

- 复用：认证、双人 Workspace、设备会话、FastAPI 事务、乐观版本、幂等请求、cursor 同步、任务详情、审批服务和 Android 主题基础。
- 文档同步没有阻塞；功能施工仍有下表的协议/迁移设计前置项。记账、打卡和纪念日需要新的 PostgreSQL schema、API、客户端仓储和迁移，不能作为纯 UI 功能接入。
- 私密参考原型未在本次审计中被绕过；实现以本次交付文档为准。

## 补充差异与证据

主设计是最新目标；本表只记录现有代码与目标之间的缺口，不将工程建议当作已经实现。

| 目标 | 复核证据/现状 | 后续方案 |
| --- | --- | --- |
| 回应指标只统计接棒与验收 | `backend/app/home/routes.py` 的 `_pending_approval_page` 读取广义 PENDING，含无 task_id 审批 | 同步约束 count/page 和旧字段兼容；其他审批保留审批中心入口 |
| 统一业务时区自然周 | 同文件返回 `HomeWeek(timezone="UTC")` | 冻结 Workspace 时区和日期转换，跨端一致，注入时钟验证 |
| 明确下一步、新建给 TA | `CreateTaskRequest`、任务表、snapshot/changes 和跨端创建/编辑已支持可空 `next_step_text`；无目标成员字段 | 已完成用户文本的持久化和兼容窗口；仍需 `proposed_next_step`、创建给 TA 原子交接和 header 强制，保留创建者 owner，失败整笔回滚 |
| 70/90/500/1000 长度 | 当前标题 200、描述 10000、review_content 5000 | 客户端/服务端统一计数，兼容历史长文本 |
| important/urgent | `backend/app/tasks/service.py` 使用 quadrant Q1～Q4 | 布尔输入与 quadrant 单源映射，不随日期改变 |
| 无截止与新建进行中 | 现有默认截止与 TODO 路径不同于目标 | 先设计新旧命令兼容，不直接改变旧 API |
| 打卡删除与纪念日生成 | 原方案缺少关联记录删除语义、未来原始日期、生成者/状态/截止定义 | 已补入契约第 3/6 节；领域 schema 与迁移仍待实施 |

最新方案见 [v1 契约](../superpowers/specs/2026-09-16-muyu-v1-contract-and-delivery-design.md)，验收与批次依赖见 [实施计划](../superpowers/plans/2026-09-16-muyu-v1.md)。2026-09-17 已执行后端 PostgreSQL、Flutter 和 Web 本地回归；原型浏览器交互、真实设备和线上核验仍未执行。
