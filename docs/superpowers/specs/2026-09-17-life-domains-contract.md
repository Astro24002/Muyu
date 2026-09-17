# 生活领域服务端契约（施工中）

日期：2026-09-17。依据 `Muyu-Codex-Design-and-Implementation.md` 第 6、7、10 节。此文件冻结本地实现边界；Android 已局部接入，Web 尚未接入，不表示 v1 验收完成。

## 事实与同步

`ledger_entries`、`habits`、`habit_checkins`、`anniversaries` 独立于任务。金额存整数分、固定 CNY；日期存 DATE，事件时间存 UTC。每个写命令使用服务端认证的 ACTIVE Workspace 成员、UUID request_id、目标版本（创建除外），同事务写领域记录、追加活动、Workspace cursor 和 `domain_commands` 幂等事实。删除保留 tombstone；客户端收到未知资源变更必须前进 cursor，不得将其判为缺口。snapshot 包含四个资源列表；changes 按全局 cursor 返回同名资源类型，旧客户端可忽略未知类型并在更新后回拉 snapshot。

第一版业务日历时区固定 `Asia/Shanghai`，服务端计算本周、习惯周期和纪念日发生日期；不能使用设备时区或客户端提供的周期键。此为首版部署约束，未来若引入 Workspace 时区须单独做数据迁移和客户端兼容。

## 记账

`GET /api/v1/ledger?month=YYYY-MM&type=EXPENSE|INCOME` 返回筛选后的明细；`GET /api/v1/ledger/summary?month=YYYY-MM` 始终统计整月全部有效明细。`POST /api/v1/ledger` 接受精确两位小数字符串 `amount` 或整数分 `amount_minor`，二者不能并存；改动使用 `PATCH /api/v1/ledger/{id}` 的 `changes` 和 `expected_version`；删除需要 `DELETE` body 中的 `confirm: true` 与期望版本。付款/收款人必须为 ACTIVE 成员，记录人与修改者由会话确定。删除后明细与汇总均不计入，但审计和 tombstone 保留。金额范围 1 至 2,000,000,000 分。

## 习惯

每个习惯只有创建者这个 owner。频率为 DAILY/WEEKLY/MONTHLY；周期键分别为当日 ISO 日期、当周周一日期、当月 `YYYY-MM`。数据库部分唯一索引 `(habit_id, frequency_snapshot, period_key) WHERE revoked_at IS NULL` 防止同一期两个有效记录，撤销当前期只置 `revoked_at`，历史保留。相同 request_id 重放同一结果；新的 request_id 重复点击返回当前有效记录，不产生新的活动或 cursor。本人可修改、暂停、恢复、打卡、撤销本期和确认删除；对方只读。删除隐藏关联有效记录，历史和活动留作审计。

## 纪念日

保存原始公历 DATE；若原始日期在未来，不计算比它更早的发生日。非闰年 2 月 29 日映射 2 月 28 日，日期差由日历日期计算。双方可编辑和确认删除。生成准备任务用 `anniversary:{id}:{occurrenceDate}` 的唯一 source_key；同一次日期返回现有任务，生成者是唯一负责人、初始 IN_PROGRESS、截止为发生日、`next_step_text` 明确。删除纪念日不删任务。生成任务需要已批准任务分类；没有分类时返回业务错误，不凭空造分类。

## 尚未完成的兼容与验收

Android life 页面目前直接用 REST 仓储读取，不消费统一 snapshot/changes；失败时保留已加载数据。Web 仍是未开放路由。需扩展两个客户端的统一增量资源模型，验证双用户并发、活动/cursor 连续性、重启后数据和真实设备交互。空库升级与 0015→0016→0015→head 往返已有自动化测试，现有真实数据升级、线上 head/备份尚未核对，禁止部署。
