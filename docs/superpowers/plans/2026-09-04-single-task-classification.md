# 单分类任务模型实施计划

> 状态：已实施并通过本地全量验证（2026-09-04）。本文件记录可复现的施工
> 顺序和验收门禁，供后续部署或回滚使用。

## 目标

在不改动 `labels` 协议字段名的前提下，将任务分类从旧的自由多标签集合收口为
“一个任务一个已批准分类”，并贯通 PostgreSQL、FastAPI、REST/cursor 同步、
Android Flutter 和 TypeScript Web。

## 施工顺序

### 1. 数据库与领域层

- 新增 `WorkspaceClassification` 模型及 Workspace 内规范名称唯一约束，并在
  `casefold()` 后再次校验 5 字符上限，避免 Unicode 归一化扩展穿透到数据库。
- 新增 `CLASSIFICATION_CREATE` 审批枚举和无 `task_id` 的审批/操作事件支持。
- 在任务创建、修改和审批应用路径调用统一分类校验器。
- 将历史多值数组压缩为首项，增加数组长度检查；保留遗留空数组只读兼容。单值检查由
  `0010` 迁移拥有，schema 测试显式断言，不能在未改造历史迁移 fixture 前直接复制到
  当前 ORM 元数据。

### 2. API 与审批

- 增加当前 Workspace 和显式 Workspace 的分类列表/创建接口。
- 创建分类只返回 `202` 待审批请求；批准后写分类记录并发布游标事件。
- 分类审批请求只允许 `name`，拒绝任务、评论和版本字段。
- 多分类、空分类、超长分类、未知分类返回稳定业务错误，不产生部分写入。

### 3. Android

- 快照模型增加已批准分类列表，并在同步边界校验 Workspace 归属；当前协议快照或增量
  的非空任务分类必须命中已批准列表，不一致增量回拉权威快照。没有分类字段的旧缓存
  仅作读取恢复兼容。
- 新建任务和详情编辑改为单选分类；创建/修改前要求恰好一个已批准值。
- “我的 → 分类管理”的新建分类入口提交审批请求；清单更多菜单不提供分类入口，
  且不增加多选或自由输入兼容入口。
- 任务模型在 JSON 解析和本地构造边界拒绝超过一个分类或超过 5 字符的值。

### 4. Web

- 类型、快照和任务模型增加分类资源及单分类解析规则。
- 创建器、编辑器和详情面板使用单选分类控件，界面文案统一为“分类”。
- `createTask`、`patchTask` 与通用审批请求即使被直接调用，也校验数组长度、已批准
  归属并规范展示名称，不能只依赖表单验证。

### 5. 测试与文档

- 将旧多标签 fixture 统一改为已批准的单分类 fixture。
- 增加分类审批、重复名称、归一化后超长、缺少分类、未知分类和多分类拒绝测试。
- 覆盖 Android/Web 的快照、首页投影、增量与通用审批请求，确保未批准分类不能进入
  已缓存状态或被直接发送。
- 运行后端 PostgreSQL、Web Vitest、TypeScript typecheck、Flutter 测试和分析。
- 更新任务工作流、产品/技术设计、开发状态；旧多标签规格标记为历史替代文档。

## 验收命令

```sh
# Backend (disposable PostgreSQL)
docker run --rm --network container:muyu-task1-postgres \
  -v "$PWD/backend:/src" -w /src \
  -e TEST_DATABASE_URL='postgresql+psycopg://muyu:muyu-task1-password@127.0.0.1:5432/muyu_task1' \
  muyu-backend-test-deps:20260828 pytest -q

# Web
cd web
npm run typecheck
npm test -- --run

# Android
cd ../client
flutter analyze
flutter test
```

## 发布前门禁

1. `git diff --check` 和 Python compileall 通过。
2. Alembic 在干净数据库从当前 head 升级到 `0010_single_task_classification`。
3. 线上备份完成后再执行迁移；检查任务 `labels` 数组长度不超过 1。
4. API/Web 部署与 Android APK 发布分开验收，未完成线上迁移不得标记生产完成。

## 回滚边界

迁移 downgrade 不恢复被压缩的多值历史，也不移除 PostgreSQL 枚举值；如需回滚，
使用部署前数据库备份恢复。客户端回滚版本必须能够读取单值 `labels`，不得重新打开
多选写入口。
