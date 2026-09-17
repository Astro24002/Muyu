# 生活领域实施计划

状态：施工中。依据 [领域契约](../specs/2026-09-17-life-domains-contract.md)；本计划仅标记真实通过的证据。

- [x] 审计主设计、现有任务事务/同步、Android/Web 壳层与仓库状态。
- [x] 冻结独立表、命令、业务时区与 source_key 契约。
- [x] 完成 PostgreSQL 0016 空库迁移及 0015→0016→0015→head 迁移往返测试；真实现有数据升级/线上 head 待发布前验收。
- [ ] 完成账本精确金额、双人权限、版本/幂等、月度完整汇总、删除和 cursor/审计测试。
- [ ] 完成习惯周期边界、本人权限、重复打卡、撤销、暂停/恢复和历史测试。
- [ ] 完成纪念日未来日期/闰年、双人并发 source_key 和任务闭环测试。
- [ ] 扩展 Android/Web 的 snapshot/changes 模型、资源仓储及可操作页面，不使用任务或浏览器本地数据冒充正式事实。
- [ ] 运行完整跨端门禁；本阶段后端全量 285 passed/3 skipped、生活领域专项 5 passed、Flutter 227 passed、analyze 和 Android debug APK 已通过；Web 回归与真实数据迁移未执行。
- [ ] 线上备份、隔离恢复与迁移往返、API/Web 部署及公网健康检查已记录在开发状态；真实账号写入、真机与双用户人工验收、签名 release 仍 pending。
