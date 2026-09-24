# 生活领域实施计划

状态：施工中。依据 [领域契约](../specs/2026-09-17-life-domains-contract.md)；本计划仅标记真实通过的证据。

- [x] 审计主设计、现有任务事务/同步、Android/Web 壳层与仓库状态。
- [x] 冻结独立表、命令、业务时区与 source_key 契约。
- [x] 完成 PostgreSQL 0016 空库迁移及 0015→0016→0015→head 迁移往返测试；真实现有数据升级/线上 head 待发布前验收。
- [ ] 完成账本精确金额、双人权限、版本/幂等、月度完整汇总、删除和 cursor/审计测试。
- [ ] 完成习惯周期边界、本人权限、重复打卡、撤销、暂停/恢复和历史测试。
- [ ] 完成纪念日未来日期/闰年、双人并发 source_key 和任务闭环测试。
- [x] 扩展 Android/Web 的 snapshot/changes 模型、资源仓储及可操作页面，不使用任务或浏览器本地数据冒充正式事实。服务端四类生活资源已进入统一 cursor；Android `WorkspaceSnapshot`/`WorkspaceChange`、`WorkspaceSyncController` 与 `LifeController` 解析并合并 ledger/habit/checkin/anniversary；Web 同步控制器和记账/打卡页面优先消费快照，写入仍回到正式 REST。
- [x] Web 已接入正式生活领域 REST 页面：记账整月汇总与明细筛选、增改删/二次确认；习惯 owner 打卡/撤销/暂停/恢复、编辑删除；纪念日增改删和准备事项生成。页面不复用任务或浏览器本地数据；专项、tombstone 和增量打卡投影回归通过，Web 全量 `288 passed`、typecheck 和 production build 通过。
- [x] 统一 snapshot/changes 客户端资源模型和仓储已完成本地实现；增量专项覆盖生活资源解析、游标推进、页面快照消费和 `DELETED + null resource` 按 ID 清除。完整并发、时区、重启和真实双用户验收仍未完成，不能据此宣称生活领域整体完成。
- [x] 2026-09-23 完成原型打卡近七日轨迹：复用正式 `habit_checkins`，Habit 投影由服务端给出 `Asia/Shanghai` 业务日期轴及有效记录日期，Android/Web 显示真实轨迹，增量创建/撤销同步更新；同日另一条有效记录存在时保留日期标记。后端 `304 passed, 3 skipped, 2 warnings`、Flutter `263 passed`/analyze、Web `290 passed`/typecheck/build 通过；无 schema/API 新增。生产未部署，真机、双用户及线上验收仍 pending。
- [x] 2026-09-24 将 `41bd888` 的 Habit 近七日读取投影部署到生产 API。SSH 使用已固定主机指纹连接 TCP `27001`；新 API 镜像摘要 `sha256:839571e33ddd619d4e3e7411acfcb887f45f7b0696d8988224f1548b0b8a7872`，只更新 API，保留旧镜像回滚标签。公网 live/ready 为 200，未授权习惯 API 为 401，生产 head 保持 `0018_task_invitations`；无 schema 变化，因此未迁移或新建数据库备份。生产验证和未完成项见开发状态。
- [x] 按原型补齐 Web 浅绿本期进度面板，按当前 owner 筛选后的权威习惯列表计算完成数/总数；Android 面板补圆形叶片标记；不持久化、不新增 API。Web 37 个测试文件 291 passed、typecheck/build 通过；Flutter 267 passed/analyze，窄屏覆盖 320/360/393/412。
- [x] 运行完整跨端门禁：隔离 PostgreSQL 上 `make verify` 通过，本地 head 迁移升级、后端 `303 passed, 3 skipped, 2 warnings`、Flutter format/analyze/全量 `261 passed`、Web 全量 `288 passed`（37 files）/typecheck/build、部署拓扑、旧运行时和客户端边界检查均通过；真实数据迁移、双用户和设备验收仍未完成。
- [x] 线上 pre-0018 custom-format 备份、`0016 -> 0017 -> 0018` 迁移、API/Web 更新及公网 live/ready、未授权和 CORS 边界已在开发状态记录；生产数据保留，旧镜像标签保留。
- [ ] 隔离恢复与迁移回滚往返、真实账号写入、真机与双用户人工验收、签名 release 仍 pending。

2026-09-22 门禁收口与生产更新：

- [x] `make verify` 在隔离 PostgreSQL 上通过，测试容器已清理；迁移回滚/备份恢复、重启持久性、真实双用户、授权真机、Web 人工窄视口和正式签名仍 pending。
- [x] 当前工作树重建 debug APK `Muyu-c4f6f71.apk`，归档、生产 API origin 和 SHA-256 检查通过；未安装到真实设备。
- [x] 生产已从 `0016_life_domains` 升至 `0018_task_invitations`；备份可读、API/Web/cleanup/Caddy healthy，公网 live/ready 为 200；没有清理生产数据。

2026-09-24 API 更新与 Android 调试构建：API 新镜像已部署且 healthy，旧镜像保留；生产 head 未变，未执行迁移。当前 debug APK `Muyu-8266e90.apk` 为 `203838389` 字节、SHA-256 `ce1820aaecaf7939d5d3ef6f2345b530b1eb5d09ecfada883982716076305b34`，ZIP 与生产 API origin 检查通过。真机安装、真实账户、双用户和正式签名仍 pending。
