# 单分类任务模型设计

## 状态

本文是 2026-09-04 起任务分类行为的当前权威设计。此前
`2026-08-31-android-task-navigation-labels-design.md` 中的“多标签”规则已
被本设计替代；旧文档仅保留为历史记录。

## 目标与边界

Muyu 是固定两人 Workspace。分类只用于任务整理和筛选，不参与权限、负责人、
状态流转或审批人推导。一个任务在任意时刻只能属于一个分类。分类是 Workspace
级资源。Workspace 不提供系统分类；首个及后续分类都只有在双人审批通过后才能被任务
使用。

本轮不新增多选标签 UI、分类层级、分类颜色、分类统计、管理员审批或跨 Workspace
分类。协议字段 `labels` 暂不改名，以避免破坏快照、增量同步和字段版本；其当前
语义是一个长度为 0 或 1 的兼容数组，新写入必须恰好一个值。

## 领域规则

### Workspace 分类

`workspace_classifications` 保存已批准分类：

| 字段 | 规则 |
| --- | --- |
| `id` | UUID |
| `workspace_id` | 所属 Workspace |
| `name` | 去首尾空格，最多 5 个 Unicode 字符 |
| `normalized_name` | `casefold()` 后的比较值，归一化后也必须最多 5 个字符 |
| `created_by` | 发起分类的成员 |
| `created_at` | 服务端时间 |

同一 Workspace 的 `normalized_name` 唯一。Unicode `casefold()` 可能扩展字符（例如
`ß -> ss`），因此必须在归一化后再次做长度校验，不能把数据库的 `VARCHAR(5)`
错误暴露成服务端 500。Workspace 创建或双人绑定不会写入分类。任何名称都由成员在
Android“我的 → 分类管理”或 Web 对应入口提交 `CLASSIFICATION_CREATE`，请求状态为
`PENDING`；另一位 ACTIVE 成员批准后才插入分类记录并写入同步游标。新 Workspace 在
首个分类获批前不能创建任务。重复的已批准名称或待审批名称返回稳定冲突错误。

### 任务分类

任务继续存储：

```json
{ "labels": ["工作"] }
```

创建，以及负责人或非负责人显式写入 `labels` 时，都必须满足：

1. `labels` 是数组且原始长度恰好为 1；
2. 唯一值去首尾空格，并按不区分大小写匹配；
3. 值存在于当前 Workspace 的已批准分类；
4. 服务端以已批准记录的展示名称保存该值。

两个或更多值（包括重复值）返回 `422 invalid_request`，未知值返回
`422 classification_not_found`。客户端和服务端都不允许通过空数组清除分类。
历史迁移允许读取遗留空数组，以便开发环境逐步修复；生产新写入仍严格要求一个
分类。

### 负责人和审批

`current_handler_id` 仍是唯一任务负责人，不恢复参与人概念。负责人修改分类可
直接提交；另一位成员修改分类时创建普通 `TASK_UPDATE` 审批请求，审批前任务值
不变。分类创建本身使用独立的 `CLASSIFICATION_CREATE` 请求，`task_id`、
`comment_id` 和 `base_field_versions` 必须为空，`proposed_changes` 只能包含
`name`。

## API 与同步

新增接口：

```text
GET  /api/v1/workspaces/current/classifications
POST /api/v1/workspaces/current/classifications
GET  /api/v1/workspaces/{workspace_id}/classifications
POST /api/v1/workspaces/{workspace_id}/classifications
```

POST 请求体为 `{request_id, name}`，成功返回 `202` 和待审批请求。审批通过响应
包含 `classification`，快照和增量变更都包含已批准分类列表/资源。任务 API 的字段
名仍为 `labels`，客户端显示名统一为“分类”。

同步解析必须拒绝属于其他 Workspace 的分类、非法名称和多值任务分类。只要快照明确
包含 `classifications`，每个非空 `labels` 还必须恰好命中其中一个已批准分类；增量
合并后若不满足此关系，客户端丢弃该次增量并重新获取权威快照。失败时保留上一份有效
快照。旧版本地缓存可能没有 `classifications` 字段，这一读取兼容仅限于缓存恢复；下一
次权威快照会进入完整校验契约，旧缓存不能成为绕过新写入校验的来源。WebSocket 只发送
游标提示，REST 快照/增量仍是正确性路径。

## 数据迁移

- `0009_workspace_classifications`：添加 `CLASSIFICATION_CREATE` 枚举、分类表、
  分类索引，并允许无任务目标的审批请求和操作事件。
- `0010_single_task_classification`：将历史多值数组收敛为首项，并增加
  `jsonb_array_length(labels) <= 1` 检查。迁移不伪造缺失分类；空遗留数组只读兼容，
  后续由业务修复或重新创建任务。
- `0011_legacy_label_backfill`：为历史任务中合法的单值 `labels` 回填相应的已批准
  分类，不改变任务数据。
- `0012_default_classification`：历史版本曾为每个已有 ACTIVE Workspace 幂等补齐系统
  分类“默认”。
- `0013_remove_default_classification`：删除上述系统分类，并将仅使用该分类的历史任务
  转换为遗留空分类记录；后续由成员人工选择一个已批准分类。

`ck_tasks_single_classification` 由 `0010` 迁移拥有，当前不重复写入 SQLAlchemy
`Task` 元数据：历史迁移测试会使用当前 ORM 映射在 `0010` 之前的表结构中构造遗留
多值行。数据库 schema 检查测试必须持续断言该约束存在；未来若调整 ORM 与迁移测试
构造方式，再将约束收敛到元数据，不能只删除迁移中的约束定义。

迁移前必须备份数据库；开发环境可按项目约定重置数据。迁移后应检查分类表唯一性、
任务数组长度和 API 创建/修改路径。

## 客户端交互

- Android 新建任务和详情编辑使用单选分类控件，只列出已批准分类；分类为空时新建
  任务不可提交，并引导用户前往“我的 → 分类管理”。分类管理与“新建分类”入口位于
  “我的 → 分类管理”，任何分类都提交审批；清单更多菜单不提供分类入口。
- Web 任务创建、编辑和同步写入使用同一单选列表；即使绕过表单直接调用同步方法，
  也必须在 API 请求前校验单分类和 Workspace 归属。
- 分类名称超过 5 个字符、空值或未批准值不得进入本地任务状态。

## 验收标准

- 分类创建在审批前不可被任务选择，批准后双方快照都能看到。
- 任务缺少分类、包含两个不同分类或使用未批准分类时，服务端和两端客户端都拒绝。
- 负责人修改立即生效；非负责人修改返回 `202`，批准前任务保持原值，批准后双方
  通过游标同步得到同一个单值数组。
- 历史多值数据迁移后最多保留一个值，数据库检查约束生效。
- 归一化会扩展的超长分类名在创建审批前返回 `422`，不会触发数据库长度错误。
- 含 `classifications` 的快照、首页投影和增量任务资源都不能引用未批准分类；客户端在
  发现不一致增量时回拉权威快照。
- 后端、Web、Flutter 全量测试和迁移检查通过。
