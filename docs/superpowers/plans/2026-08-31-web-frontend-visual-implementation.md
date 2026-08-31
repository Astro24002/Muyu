# Web 前端视觉重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 TypeScript + Vite 原生 DOM Web 应用迁移为 React 组件架构，并实现已确认的“安静留白 + 柔和生活感”行动工作台。

**Architecture:** 保留现有 `ApiClient`、`QrLoginController`、`WorkspaceSyncController` 和 `WorkspaceSocket` 作为无 UI 的业务服务，通过 React hooks 订阅它们的状态。使用一个轻量 hash 路由承载“今天、所有任务、审批、动态、任务详情”页面，不引入全局状态库或后端 API 改造；所有页面通过集中设计令牌和可复用任务行表达一致的视觉语言。

**Tech Stack:** React、React DOM、TypeScript、Vite、Lucide React、Vitest、React Testing Library、Playwright；继续使用现有 `qrcode`、`fetch`、WebSocket 和同源 `/api` 协议。

**Spec:** `docs/superpowers/specs/2026-08-31-web-frontend-visual-direction-design.md`

## Global Constraints

- Web 首屏默认进入“今天”，并按照重点任务、接下来、等待、审批提醒和快速记录的顺序展示。
- Web 使用单层顶部应用栏，不使用固定深色侧栏。
- 桌面内容容器最大宽度保持 `900-960px`，常规页面左右内边距为 `24-32px`。
- 重点任务最多一个，使用浅绿色背景、左侧 `4px` 深绿强调线和不超过 `8px` 的圆角。
- 普通任务行建议高度 `52-60px`，使用稳定的线性行布局，不因悬停、加载、徽标或图标改变行高。
- 首版只实现亮色主题，颜色基线使用 `#F8FAF9`、`#FFFFFF`、`#1D2D29`、`#25312E`、`#7C8783`、`#225F50`、`#2E7663`、`#E7F0ED`、`#B2573B`、`#F3DFD7`、`#DCE3E0`、`#52A083`。
- 字体栈固定为 `Inter, "Segoe UI", ui-sans-serif, system-ui, sans-serif`，`letter-spacing: 0`，字号不得随 viewport 连续缩放。
- 使用 `4px` 基础间距体系，常用值为 `4 / 8 / 12 / 16 / 24 / 32 / 40`；普通控件圆角 `6px`，面板和浮层最大圆角 `8px`。
- 图标统一使用 Lucide，不手绘 SVG；图标按钮必须有可访问名称和 tooltip。
- 不使用渐变、玻璃拟态、光晕、装饰性圆形色块、Hero 区域、KPI 卡片、默认五列看板、卡片套卡片或固定深色管理侧栏。
- 所有异步操作显示局部处理中状态；错误靠近触发位置展示，并保留已经输入的内容。
- Web 不实现离线写入；网络失败时展示可能过期快照，不在浏览器建立第二个事实源。
- 认证、Cookie、二维码 proof、设备私钥和同步协议保持现有实现；本计划不修改后端 API、数据库或 Android 代码。
- 首要验收视口为 `1280x720`、`1440x900` 和 `1920x1080`；低于 `1024px` 时收紧布局并将次要操作收入菜单。

---

## 代码边界

实施前先按以下职责理解文件，避免把数据协议和视觉组件再次耦合：

| 路径 | 实施后的职责 |
| --- | --- |
| `web/src/api/` | HTTP 请求、错误解析和现有 snake_case API 合同 |
| `web/src/auth/` | 二维码登录和 Web 会话业务状态 |
| `web/src/sync/`、`web/src/realtime/` | Workspace 快照、增量同步、冲突和 WebSocket |
| `web/src/tasks/` | 纯任务模型、状态分组、今天页面派生选择和动态排序 |
| `web/src/app/` | React 根组件、hash 路由、业务服务适配 hook、登录/工作区生命周期 |
| `web/src/components/` | 不持有 API 事实的布局、控件、任务行、状态和浮层组件 |
| `web/src/pages/` | 页面级组合：登录、今天、所有任务、审批、动态、任务详情 |
| `web/src/styles/` | 设计令牌、全局重置、布局和组件样式；不在业务组件内散落颜色 |
| `web/test/` | 纯模型、服务适配、组件行为和页面路由测试 |
| `web/e2e/` | Playwright 视觉和主要工作流验收 |

当前 `web/src/ui/*.ts` 和 `web/src/app.ts` 是一次性原生 DOM 视图。迁移完成后删除它们及对应旧测试，业务服务文件继续复用。

### Task 1: React 工程基础与测试入口

**Files:**
- Modify: `web/package.json`
- Modify: `web/package-lock.json`
- Modify: `web/vite.config.ts`
- Modify: `web/tsconfig.json`
- Modify: `web/index.html`
- Create: `web/src/main.tsx`
- Create: `web/src/app/App.tsx`
- Create: `web/test/react-test-helpers.tsx`
- Create: `web/test/app-shell.test.tsx`
- Test: `web/test/app-shell.test.tsx`

**Interfaces:**
- Consumes: `ApiClient`, `QrLoginController`, `WorkspaceSyncController` from the existing service layer.
- Produces: `App` React component with props `{ api: ApiClient; login: QrLoginController; sync: WorkspaceSyncController }`, and a React Testing Library render helper.

- [ ] **Step 1: Add React and test dependencies**

在 `web/package.json` 增加运行时依赖 `react`、`react-dom`、`lucide-react`，开发依赖 `@vitejs/plugin-react`、`@types/react`、`@types/react-dom`、`@testing-library/react`、`@testing-library/jest-dom`、`@playwright/test`，并执行 `cd web && npm install` 更新 `package-lock.json`。保留 `qrcode` 和现有 Vite/Vitest 依赖，不引入 Zustand、Redux、React Router 或 CSS 框架。

- [ ] **Step 2: Configure Vite, TypeScript and the HTML entry**

在 `vite.config.ts` 使用 `react()` 插件并保留现有 `/api` 和 WebSocket proxy；在 `tsconfig.json` 增加 `jsx: "react-jsx"`；将 `index.html` 的入口改为 `/src/main.tsx`，保留 `lang="zh-CN"`、viewport 和 `Muyu` 标题。

- [ ] **Step 3: Add a minimal React root and failing shell test**

```tsx
export interface AppProps {
  api: ApiClient;
  login: QrLoginController;
  sync: WorkspaceSyncController;
}

export function App({ api, login, sync }: AppProps): JSX.Element {
  return <main data-testid="muyu-app" />;
}
```

测试使用 `render(<App ... />)`，断言 `data-testid="muyu-app"` 存在，并验证 `cleanup()` 后不会向旧 root 写入内容。

- [ ] **Step 4: Run the focused test and typecheck**

Run: `cd web && npm test -- --run web/test/app-shell.test.tsx && npm run typecheck`

Expected: 测试为 PASS，TypeScript 无错误。

- [ ] **Step 5: Commit the React bootstrap**

```bash
git add web/package.json web/package-lock.json web/vite.config.ts web/tsconfig.json web/index.html web/src/main.tsx web/src/app/App.tsx web/test/react-test-helpers.tsx web/test/app-shell.test.tsx
git commit -m "feat(web): bootstrap React application"
```

### Task 2: 建立设计令牌和基础 UI 原语

**Files:**
- Create: `web/src/styles/tokens.css`
- Create: `web/src/styles/global.css`
- Modify: `web/src/main.tsx`
- Create: `web/src/components/ui/Button.tsx`
- Create: `web/src/components/ui/IconButton.tsx`
- Create: `web/src/components/ui/StatusBadge.tsx`
- Create: `web/src/components/ui/SectionHeading.tsx`
- Create: `web/test/ui-primitives.test.tsx`
- Test: `web/test/ui-primitives.test.tsx`

**Interfaces:**
- Consumes: Global constraints中的颜色、字体、间距和 Lucide 规则。
- Produces: `Button`、`IconButton`、`StatusBadge`、`SectionHeading`，所有组件支持 `disabled`、可访问名称和稳定 class contract。

- [ ] **Step 1: Write primitive behavior tests**

测试覆盖：主按钮默认 `type="button"`；提交按钮可以显式传 `type="submit"`；禁用按钮不能触发 `onClick`；`IconButton` 必须输出 `aria-label` 和 `title`；`StatusBadge` 同时渲染状态文本和状态 class；`SectionHeading` 输出可关联的 heading 元素。

- [ ] **Step 2: Add centralized CSS tokens**

```css
:root {
  --color-page: #f8faf9;
  --color-surface: #ffffff;
  --color-text: #1d2d29;
  --color-body: #25312e;
  --color-muted: #7c8783;
  --color-brand: #225f50;
  --color-brand-interactive: #2e7663;
  --color-focus-surface: #e7f0ed;
  --color-coral: #b2573b;
  --color-coral-surface: #f3dfd7;
  --color-border: #dce3e0;
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-6: 24px;
  --space-8: 32px;
  --radius-control: 6px;
  --radius-panel: 8px;
}
```

在 `global.css` 定义 `box-sizing`、系统字体栈、`letter-spacing: 0`、可见焦点环、按钮/输入继承字体、`prefers-reduced-motion` 和断点基础规则。所有业务样式只引用这些变量。

- [ ] **Step 3: Implement primitives with Lucide icons**

`IconButton` 接收 `{ label: string; icon: ReactNode; onClick?: () => void; disabled?: boolean }`，不接受任意手写 SVG。`Button` 支持 `tone: 'primary' | 'neutral' | 'quiet' | 'danger'`；同一页面由调用方保证只有一个主动作。

- [ ] **Step 4: Run primitive tests and inspect computed styles**

Run: `cd web && npm test -- --run web/test/ui-primitives.test.tsx && npm run typecheck`

Expected: PASS；jsdom 中所有控件都有可访问名称，CSS 文件可被 Vite 正常解析。

- [ ] **Step 5: Commit the token layer**

```bash
git add web/src/styles/tokens.css web/src/styles/global.css web/src/main.tsx web/src/components/ui web/test/ui-primitives.test.tsx
git commit -m "feat(web): add visual design tokens"
```

### Task 3: 路由、服务状态适配和应用生命周期

**Files:**
- Create: `web/src/app/routes.ts`
- Create: `web/src/app/use-external-state.ts`
- Create: `web/src/app/use-workspace-realtime.ts`
- Modify: `web/src/app/App.tsx`
- Modify: `web/src/main.tsx`
- Create: `web/test/routes.test.ts`
- Create: `web/test/use-external-state.test.tsx`
- Create: `web/test/app-lifecycle.test.tsx`
- Test: `web/test/routes.test.ts`
- Test: `web/test/use-external-state.test.tsx`
- Test: `web/test/app-lifecycle.test.tsx`

**Interfaces:**
- Consumes: `WorkspaceSyncController.subscribe`, `QrLoginController.subscribe`, `WorkspaceSocket`, `ApiClient.logoutWebSession`。
- Produces: `Route = 'today' | 'tasks' | 'approvals' | 'activity' | { kind: 'task'; id: string }`；`parseHash(hash)`；`navigate(route)`；`useWorkspaceState(sync)`；`useQrLoginState(login)`。

- [ ] **Step 1: Define hash route parsing tests**

```ts
expect(parseHash('#/today')).toEqual({ kind: 'today' });
expect(parseHash('#/tasks')).toEqual({ kind: 'tasks' });
expect(parseHash('#/approvals')).toEqual({ kind: 'approvals' });
expect(parseHash('#/activity')).toEqual({ kind: 'activity' });
expect(parseHash('#/tasks/task-1')).toEqual({ kind: 'task', id: 'task-1' });
expect(parseHash('#/unknown')).toEqual({ kind: 'today' });
```

`navigate` 使用 `location.hash` 和 `hashchange`，不依赖服务器 history fallback，确保 Caddy 无需新增路由规则。

- [ ] **Step 2: Add external-store hooks**

```ts
export function useWorkspaceState(sync: WorkspaceSyncController): WorkspaceSyncState {
  return useSyncExternalStore(
    (onStoreChange) => sync.subscribe(() => onStoreChange()),
    () => sync.state,
    () => sync.state,
  );
}
```

`useQrLoginState` 使用相同模式。hook 不复制状态、不修改 controller，只负责 React 重渲染订阅。

- [ ] **Step 3: Move load, login, logout and realtime into App lifecycle effects**

App 启动时调用一次 `sync.loadSnapshot()`；有快照时创建 `WorkspaceSocket`，以 `workspace.changed` hint 调用 `sync.pull()`；WebSocket 失败时每 `10_000ms` 做一次可见页面 fallback pull，连接恢复后停止 fallback。`authRequired` 时销毁工作区和 socket，回到 QR 登录页；登出先清理本地 sync、socket 和 React view，再调用 `logoutWebSession()`。

- [ ] **Step 4: Test stale session isolation**

测试覆盖：旧 workspace 的快照 promise 在新登录后完成时不渲染旧内容；登出会关闭 socket 并清空快照；初始 `401` 显示登录页；未授权工作区不能渲染可编辑页面；组件卸载后 controller 回调不会更新 DOM。

- [ ] **Step 5: Run lifecycle tests**

Run: `cd web && npm test -- --run web/test/routes.test.ts web/test/use-external-state.test.tsx web/test/app-lifecycle.test.tsx && npm run typecheck`

Expected: PASS；socket、定时器和订阅均在卸载或登出时清理。

- [ ] **Step 6: Commit the application shell**

```bash
git add web/src/app web/src/main.tsx web/test/routes.test.ts web/test/use-external-state.test.tsx web/test/app-lifecycle.test.tsx
git commit -m "feat(web): add React app lifecycle and routing"
```

### Task 4: 顶部应用栏、登录页和通用状态区域

**Files:**
- Create: `web/src/components/layout/AppShell.tsx`
- Create: `web/src/components/layout/TopNav.tsx`
- Create: `web/src/components/layout/UserMenu.tsx`
- Create: `web/src/components/status/SyncStatus.tsx`
- Create: `web/src/components/status/InlineError.tsx`
- Create: `web/src/pages/QrLoginPage.tsx`
- Modify: `web/src/app/App.tsx`
- Create: `web/test/top-nav.test.tsx`
- Create: `web/test/qr-login-page.test.tsx`
- Test: `web/test/top-nav.test.tsx`
- Test: `web/test/qr-login-page.test.tsx`

**Interfaces:**
- Consumes: `Route`、`QrLoginState`、`WorkspaceSyncState` 和 `QrLoginController`。
- Produces: `AppShell` props `{ route; onNavigate; onLogout; pendingApprovalCount; children }`；`SyncStatus` props `{ loading; stale; error }`。

- [ ] **Step 1: Write navigation and login tests**

测试断言顶部只有“今天、所有任务、审批、动态”四个一级入口；当前入口有 `aria-current="page"` 和底部指示线 class；审批数量显示为文本可读的小徽标；搜索和用户入口有可访问名称；二维码页保留 canvas、安全码、当前站点、过期时间、轮询和重新生成操作。

- [ ] **Step 2: Implement AppShell and TopNav**

顶部应用栏高度固定在 `56-60px`，白色表面、浅色底边框，最大内容宽度跟随页面容器。左侧显示“木鱼 / MUYU”，中部使用文字导航，右侧使用 Lucide 搜索、新建任务和用户菜单图标。搜索先打开一个轻量搜索状态/输入层，不能出现空白无功能按钮；新建任务调用页面提供的 `onCreateTask`。

- [ ] **Step 3: Implement QR login using the existing controller**

将现有 `QrLoginView` 的状态分支迁移到 React，不改变 proof 生成、2 秒轮询、二维码 payload 或登录交换。二维码 canvas 使用 `useEffect` 调用 `QRCode.toCanvas`，cleanup 时只停止 React effect，不读取或持久化原始 proof。

- [ ] **Step 4: Implement SyncStatus and inline errors**

正常同步只显示绿色状态点和“刚刚同步”等低权重文案；过期快照显示“内容可能不是最新”；错误显示在触发位置并保留输入内容；认证失效由 App 生命周期处理，不在工作区继续显示可编辑控件。

- [ ] **Step 5: Run focused UI tests**

Run: `cd web && npm test -- --run web/test/top-nav.test.tsx web/test/qr-login-page.test.tsx && npm run typecheck`

Expected: PASS；登录状态与工作区状态切换不泄漏旧 DOM。

- [ ] **Step 6: Commit shell and login**

```bash
git add web/src/components/layout web/src/components/status web/src/pages/QrLoginPage.tsx web/src/app/App.tsx web/test/top-nav.test.tsx web/test/qr-login-page.test.tsx
git commit -m "feat(web): add action-oriented app shell"
```

### Task 5: 任务模型派生和可复用任务行

**Files:**
- Modify: `web/src/tasks/task-view-model.ts`
- Create: `web/src/components/tasks/TaskRow.tsx`
- Create: `web/src/components/tasks/TaskList.tsx`
- Create: `web/src/components/tasks/FocusTask.tsx`
- Create: `web/src/components/tasks/TaskStatusLabel.tsx`
- Create: `web/src/components/tasks/TaskMeta.tsx`
- Modify: `web/src/tasks/task-model.ts` only when a typed helper is needed by the new selectors
- Create: `web/test/today-view-model.test.ts`
- Create: `web/test/task-row.test.tsx`
- Test: `web/test/today-view-model.test.ts`
- Test: `web/test/task-row.test.tsx`

**Interfaces:**
- Consumes: `TaskItem`、`TaskApprovalRequest`、`TaskStatus`、`TaskQuadrant`。
- Produces:

```ts
export interface TodayModel {
  focus: TaskItem | null;
  next: TaskItem[];
  waiting: TaskItem[];
  pendingApprovals: TaskApprovalRequest[];
}

export function deriveTodayModel(
  tasks: TaskItem[],
  approvals: TaskApprovalRequest[],
  viewerId: string,
  now: Date,
): TodayModel;
```

`TaskRow` props 为 `{ task; onOpen; onComplete; busy }`；`TaskList` props 为 `{ tasks; emptyMessage; onOpen; onComplete; busy }`；`FocusTask` props 为 `{ task; onContinue; busy }`。

- [ ] **Step 1: Write deterministic selector tests**

测试验证：忽略已删除任务；focus 选择当前用户 `IN_PROGRESS` 任务中 `updated_at` 最新的一件，时间相同时按 id 稳定排序；next 排除 focus、等待和终态，按截止时间升序、无截止时间置后；waiting 只包含等待任务；审批只保留当前用户待处理请求；空 focus 返回 `null`。

- [ ] **Step 2: Implement selectors without side effects**

选择函数只接收数据和 `now`，不读取全局时间、不修改输入数组、不根据随机更新时间改变结果。next 列表最多返回 8 项，其余通过“查看所有任务”进入完整列表。

- [ ] **Step 3: Write task row behavior tests**

测试断言行有稳定 `data-task-row`、标题、辅助信息、尾部日期/状态和完成控件；点击完成不会触发行打开；处理中时完成控件 disabled；等待、临期和完成同时有文本语义，不只依赖颜色；长标题不会通过脚本裁切为不可读文本。

- [ ] **Step 4: Implement linear task components**

普通任务使用底部分隔线和 `52-60px` 最小高度，不使用卡片边框和阴影。行尾放截止时间或状态，标题区域允许收缩和换行；`FocusTask` 是唯一使用浅绿色背景和左侧 `4px` 强调线的任务组件，主按钮只有“继续处理”。

- [ ] **Step 5: Run model and component tests**

Run: `cd web && npm test -- --run web/test/today-view-model.test.ts web/test/task-row.test.tsx && npm run typecheck`

Expected: PASS；selector 是纯函数，组件操作不会改变任务对象。

- [ ] **Step 6: Commit task primitives**

```bash
git add web/src/tasks/task-view-model.ts web/src/tasks/task-model.ts web/src/components/tasks web/test/today-view-model.test.ts web/test/task-row.test.tsx
git commit -m "feat(web): add linear task workbench primitives"
```

### Task 6: “今天”和“所有任务”页面

**Files:**
- Create: `web/src/pages/TodayPage.tsx`
- Create: `web/src/pages/AllTasksPage.tsx`
- Create: `web/src/components/tasks/TaskComposer.tsx`
- Create: `web/src/components/tasks/TaskFilters.tsx`
- Create: `web/src/components/approvals/InlineApprovalNotice.tsx`
- Modify: `web/src/app/App.tsx`
- Create: `web/test/today-page.test.tsx`
- Create: `web/test/all-tasks-page.test.tsx`
- Create: `web/test/task-composer.test.tsx`
- Test: `web/test/today-page.test.tsx`
- Test: `web/test/all-tasks-page.test.tsx`
- Test: `web/test/task-composer.test.tsx`

**Interfaces:**
- Consumes: `useWorkspaceState(sync)`、`deriveTodayModel`、`TaskRow`、`FocusTask`、`sync.createTask`、`sync.transitionTask`。
- Produces: 页面组件 props `{ sync; onOpenTask; onCreateTask }`，并将筛选状态限制在页面本地，不改变事实源。

- [ ] **Step 1: Write Today page structure tests**

测试断言默认顺序为页面标题/日期、同步状态、重点任务、接下来、等待中、审批提醒、快速记录；无重点任务时不产生空重点区域；没有任务时显示一句解释和“记下一件事”；审批通知包含数量、说明和“去处理”动作。

- [ ] **Step 2: Implement Today page**

内容容器最大宽度 `960px`，顶部间距 `32-40px`。页面标题使用“今天，先让一件事向前走”，辅助文案低权重。只渲染 `TodayModel` 的顺序，不渲染 KPI、统计矩阵、状态数量汇总或侧栏。

- [ ] **Step 3: Write All Tasks and composer tests**

测试覆盖状态、四象限、标签和“只看我的任务”筛选；筛选结果仍使用同一 `TaskRow`；创建任务时标题或四象限缺失显示就地错误；提交中禁用按钮；网络失败保留标题、描述、象限和标签草稿；成功 ACK 后清空草稿。

- [ ] **Step 4: Implement All Tasks page and composer**

所有任务页面使用线性列表和轻量筛选工具行，不恢复五列看板。创建任务默认收起为一条“记下一件事”输入入口，展开后依次显示标题、下一步描述、四象限、标签和一个主提交按钮。标签沿用 `parseTaskLabelsInput`，不在 UI 重写服务端规范化规则。

- [ ] **Step 5: Connect page actions to sync controller**

完成操作调用 `sync.transitionTask(task.id, 'DONE')`；创建调用 `sync.createTask(title, description, quadrant, labels)`；所有操作根据 `state.loading`、`state.stale` 和 `state.authRequired` 正确禁用，不复制 API 请求。

- [ ] **Step 6: Run page tests**

Run: `cd web && npm test -- --run web/test/today-page.test.tsx web/test/all-tasks-page.test.tsx web/test/task-composer.test.tsx && npm run typecheck`

Expected: PASS；默认路由为“今天”，页面没有看板、KPI 卡片或无意义右侧栏。

- [ ] **Step 7: Commit core workbench pages**

```bash
git add web/src/pages/TodayPage.tsx web/src/pages/AllTasksPage.tsx web/src/components/tasks web/src/components/approvals/InlineApprovalNotice.tsx web/src/app/App.tsx web/test/today-page.test.tsx web/test/all-tasks-page.test.tsx web/test/task-composer.test.tsx
git commit -m "feat(web): build today and task list pages"
```

### Task 7: 审批、任务详情和冲突处理

**Files:**
- Create: `web/src/pages/ApprovalsPage.tsx`
- Create: `web/src/components/approvals/ApprovalRequestRow.tsx`
- Create: `web/src/components/tasks/TaskDetailPanel.tsx`
- Create: `web/src/components/tasks/TaskEditForm.tsx`
- Create: `web/src/components/tasks/TaskTimeline.tsx`
- Create: `web/src/components/conflicts/ConflictPanel.tsx`
- Modify: `web/src/api/types.ts` only if activity event types are added
- Modify: `web/src/app/App.tsx`
- Create: `web/test/approvals-page.test.tsx`
- Create: `web/test/task-detail-panel.test.tsx`
- Create: `web/test/conflict-panel.test.tsx`
- Test: `web/test/approvals-page.test.tsx`
- Test: `web/test/task-detail-panel.test.tsx`
- Test: `web/test/conflict-panel.test.tsx`

**Interfaces:**
- Consumes: `TaskDetailActions` 的现有业务动作语义、`WorkspaceSyncState.approvals`、`state.conflicts`、`TaskComment`。
- Produces: `TaskDetailPanel` props `{ task; members; syncState; actions; onClose }`；`ApprovalRequestRow` props `{ request; task; incoming; busy; onApprove; onReject; onCancel }`。

活动类型在本任务中定义为：

```ts
export type ActivityEvent = {
  kind: 'operation' | 'comment' | 'delay';
  id: string;
  created_at: string;
  operation_type?: string;
  body?: string;
  author_user_id?: string;
  actor_user_id?: string;
  reason?: string;
  note?: string;
  new_due_at?: string;
  delay_duration_minutes?: number;
  request_id?: string;
  [key: string]: unknown;
};
```

- [ ] **Step 1: Write approval behavior tests**

测试覆盖 incoming/outgoing 两组、待审批数量、批准/拒绝/取消按钮层级、处理中禁用、冲突请求明确说明、空状态和错误保留列表；批准或拒绝后页面使用 sync 状态重新渲染，而不是手动伪造任务结果。

- [ ] **Step 2: Implement approvals as linear request rows**

审批页不使用仪表盘统计和嵌套卡片。每项只表达一个任务变更对象、发起人、提议变更和动作；“批准”作为唯一主动作，“拒绝/取消”使用次要或危险色动作。拒绝需要轻量原因输入，提交中保留输入。

- [ ] **Step 3: Write task detail and conflict tests**

测试断言打开任务后详情在桌面使用右侧抽屉，在宽度低于 `1024px` 时使用占据主要视口的全宽底部 sheet，不离开当前列表上下文；标题、下一步描述、状态、负责人、截止时间优先；评论、延期、审批、活动按区块展开；同字段冲突提供“保留当前”和“采用提议”两个明确动作；关闭后回到原路由。

- [ ] **Step 4: Implement task detail panel**

将当前 `task-detail-view.ts` 的字段编辑、状态转换、评论、延期、评论删除和冲突动作迁移为 React 组件。保留 `sync.patchTask`、`sync.transitionTask`、`sync.addComment`、`sync.addDelay`、`sync.deleteTaskComment` 和 `sync.resolveConflict` 的现有调用契约。面板最多使用一层浮层阴影，焦点进入面板并在关闭时恢复到打开任务的控件。

- [ ] **Step 5: Add activity event typing only for existing endpoint data**

将 `getTaskActivity(id)` 返回值定义为 `ActivityEvent[]`，至少覆盖 `operation`、`comment`、`delay` 三种 `kind`，保留未知字段以兼容现有 API。此步骤不新增后端路由；任务详情按需加载单任务活动。

- [ ] **Step 6: Run detail and approval tests**

Run: `cd web && npm test -- --run web/test/approvals-page.test.tsx web/test/task-detail-panel.test.tsx web/test/conflict-panel.test.tsx web/test/approval-view.test.ts web/test/task-detail-view.test.ts && npm run typecheck`

Expected: 新 React 视图和旧行为测试均 PASS；并发冲突、审批和错误状态没有被 UI 迁移丢失。

- [ ] **Step 7: Commit approval and detail surfaces**

```bash
git add web/src/pages/ApprovalsPage.tsx web/src/components/approvals web/src/components/tasks/TaskDetailPanel.tsx web/src/components/tasks/TaskEditForm.tsx web/src/components/tasks/TaskTimeline.tsx web/src/components/conflicts web/src/api/types.ts web/src/app/App.tsx web/test/approvals-page.test.tsx web/test/task-detail-panel.test.tsx web/test/conflict-panel.test.tsx
git commit -m "feat(web): add approvals and task detail surfaces"
```

### Task 8: 动态页、用户菜单和 Web 会话管理

**Files:**
- Create: `web/src/pages/ActivityPage.tsx`
- Create: `web/src/components/activity/ActivityRow.tsx`
- Modify: `web/src/api/types.ts`
- Modify: `web/src/api/client.ts`
- Create: `web/src/tasks/activity-view-model.ts`
- Create: `web/src/components/account/WebSessionPanel.tsx`
- Modify: `web/src/components/layout/UserMenu.tsx`
- Create: `web/test/activity-view-model.test.ts`
- Create: `web/test/activity-page.test.tsx`
- Create: `web/test/web-session-panel.test.tsx`
- Test: `web/test/activity-page.test.tsx`
- Test: `web/test/web-session-panel.test.tsx`

**Interfaces:**
- Consumes: `ApiClient.getTaskActivity`、`WebSessionViewApi`、当前快照任务集合。
- Produces: `loadWorkspaceActivity(tasks, getTaskActivity): Promise<{ events: ActivityEvent[]; failedTaskIds: string[] }>`，并发上限为 4、最多保留按时间倒序的 50 条事件；`WebSessionPanel` 使用现有 list/revoke/revoke-all API。

- [ ] **Step 1: Write activity aggregation tests**

测试覆盖多个任务活动合并、按 `created_at` 倒序、同时间按 id 稳定排序、单个任务请求失败时保留其他任务结果并显示局部错误、空任务集不发请求、最多 4 个并发请求和最多 50 条结果。

- [ ] **Step 2: Implement activity loader and ActivityPage**

动态页只有在进入 `#/activity` 后加载，避免首屏请求 N 个任务活动。页面显示“最近动态”、任务标题、活动类型、操作者和时间；活动行沿用分隔线和次级文字，不显示 request id、cursor 或版本号作为主信息。没有活动时显示一句解释和返回“今天”的动作。

- [ ] **Step 3: Migrate Web session management into UserMenu**

用户菜单显示账户相关操作、网页登录会话和退出登录。会话列表只显示 active 且未过期项，不能渲染 token、cookie、proof 或 digest；撤销失败保留列表并就地提示；任意 `401` 触发 App 的 QR 登录流程。

- [ ] **Step 4: Run activity and session tests**

Run: `cd web && npm test -- --run web/test/activity-view-model.test.ts web/test/activity-page.test.tsx web/test/web-session-panel.test.tsx web/test/web-session-view.test.ts && npm run typecheck`

Expected: PASS；动态页按需加载，用户菜单不会把敏感凭据渲染到 DOM。

- [ ] **Step 5: Commit activity and account surfaces**

```bash
git add web/src/pages/ActivityPage.tsx web/src/components/activity web/src/tasks/activity-view-model.ts web/src/components/account web/src/components/layout/UserMenu.tsx web/src/api/types.ts web/src/api/client.ts web/test/activity-view-model.test.ts web/test/activity-page.test.tsx web/test/web-session-panel.test.tsx
git commit -m "feat(web): add activity and session surfaces"
```

### Task 9: 响应式样式、无障碍和视觉回归

**Files:**
- Modify: `web/src/styles/global.css`
- Modify: `web/src/styles/tokens.css` only for verified contrast adjustments
- Modify: all React files under `web/src/components/` and `web/src/pages/` when adding missing labels or focus targets
- Create: `web/playwright.config.ts`
- Create: `web/e2e/visual.spec.ts`
- Create: `web/e2e/fixtures.ts`
- Create: `web/test/accessibility-contract.test.tsx`
- Test: `web/e2e/visual.spec.ts`
- Test: `web/test/accessibility-contract.test.tsx`

**Interfaces:**
- Consumes: 已完成的 React 页面、设计令牌、`data-testid` 稳定选择器和现有 API mock 边界。
- Produces: Playwright 在 `1280x720`、`1440x900`、`1920x1080` 下对主要页面截图和关键文本/溢出断言。

- [ ] **Step 1: Add responsive and motion rules**

桌面内容容器保持 `900-960px`；低于 `1024px` 时导航次要项进入用户/更多菜单；低于 `640px` 时输入和主动作纵向排列。任务行、徽标和加载态使用稳定尺寸。只添加 `120-180ms` 的状态过渡，并在 `prefers-reduced-motion: reduce` 下关闭。

- [ ] **Step 2: Add accessibility contract tests**

测试扫描登录、今天、所有任务、审批和详情的按钮/输入/图标，断言每个表单控件有 label，每个 icon-only 控件有 `aria-label`，当前导航有 `aria-current`，错误有 `role="alert"`，处理中状态有 `aria-live`，键盘 Tab 可以到达主要动作。

- [ ] **Step 3: Configure Playwright and deterministic fixtures**

`fixtures.ts` 使用 `page.route('**/api/**')` 返回固定的二维码挑战、快照、审批、评论、活动和同步响应；不连接真实账号、不写入 Cookie 以外的敏感测试数据。Playwright 配置使用 Vite preview 或 dev server，默认 `use.baseURL = 'http://127.0.0.1:4173'`，桌面 project 覆盖三种目标 viewport。

- [ ] **Step 4: Add visual workflow assertions**

截图覆盖二维码登录、今天有重点任务、今天无重点任务、所有任务筛选、审批页、任务详情/冲突面板。每个页面断言无横向滚动、无文字溢出、没有固定深色侧栏、没有 `.task-board`、首屏存在顶部导航和任务主线。

- [ ] **Step 5: Run visual and build verification**

Run:

```bash
cd web
npm run typecheck
npm test -- --run
npm run build
npx playwright test
```

Expected: TypeScript、Vitest、Vite build 和 Playwright 全部退出码为 0；截图差异只在明确批准的文案或数据 fixture 变化内。

- [ ] **Step 6: Commit visual verification setup**

```bash
git add web/src/styles web/src/components web/src/pages web/playwright.config.ts web/e2e web/test/accessibility-contract.test.tsx
git commit -m "test(web): add visual and accessibility verification"
```

### Task 10: 删除旧 DOM 视图并完成交付验收

**Files:**
- Delete: `web/src/app.ts`
- Delete: `web/src/styles.css`
- Delete: `web/src/ui/qr-login-view.ts`
- Delete: `web/src/ui/workspace-view.ts`
- Delete: `web/src/ui/task-detail-view.ts`
- Delete: `web/src/ui/approval-view.ts`
- Delete: `web/src/ui/web-session-view.ts`
- Delete: old DOM-only tests after equivalent React coverage is green: `web/test/app.test.ts`, `web/test/approval-view.test.ts`, `web/test/task-detail-view.test.ts`, `web/test/workspace-actions.test.ts`, `web/test/web-session-view.test.ts`
- Modify: `docs/README.md` to add this implementation plan under “待执行实施计划”
- Test: full `web/test/` and `web/e2e/`

**Interfaces:**
- Consumes: 所有 React 页面、服务层、设计令牌、单元测试和 Playwright 验收。
- Produces: 单一 React UI 入口，不再存在旧原生 DOM view 的 import、class name 或构建入口。

- [ ] **Step 1: Search for old view imports and forbidden visual patterns**

Run: `rg -n "from './app'|from '../src/ui|task-board|workspace-controls|task-summary|#172033|#d5dce6|linear-gradient|backdrop-filter" web/src web/test`

Expected: 不存在旧 UI 文件 import；旧看板和旧颜色只允许出现在已删除文件的 Git diff 中，不能出现在新源代码。

- [ ] **Step 2: Delete old views after replacement coverage passes**

删除清单中的旧视图和旧测试，不删除 `api`、`auth`、`sync`、`realtime`、`tasks` 纯模型文件。确认 `main.tsx` 是唯一浏览器入口，`npm run build` 不再打包旧 DOM 代码。

- [ ] **Step 3: Update documentation index**

在 `docs/README.md` 的“待执行实施计划”中增加：

```markdown
3. [Web 前端视觉重构实施计划](./superpowers/plans/2026-08-31-web-frontend-visual-implementation.md)
   - React + Vite 渐进迁移；
   - 今天、所有任务、审批、动态和任务详情页面；
   - 设计令牌、响应式、无障碍和 Playwright 视觉验收。
```

- [ ] **Step 4: Run complete delivery verification**

Run:

```bash
cd web
npm run typecheck
npm test -- --run
npm run build
npx playwright test
```

Expected: 全部退出码为 0，构建产物包含 React 页面、二维码登录和同步逻辑；当前仓库中与本计划无关的后端、Android 和 Web 业务协议改动保持不变。

- [ ] **Step 5: Commit the migration cleanup**

```bash
git add web docs/README.md
git commit -m "refactor(web): complete React visual migration"
```

## 交付检查表

- [ ] `web/` 使用 React + Vite，未引入全局状态库、React Router 或 CSS 框架。
- [ ] `ApiClient`、二维码 proof、HttpOnly Cookie、Workspace cursor、WebSocket 和错误协议未被 UI 重构破坏。
- [ ] 默认页面是“今天”，不是统计首页、看板或管理控制台。
- [ ] 普通任务为稳定高度线性行，唯一重点任务使用浅绿色区域。
- [ ] 顶部轻导航、审批徽标、用户菜单、同步状态和快速创建可操作。
- [ ] 所有任务、审批、动态、任务详情、评论、延期和冲突动作具备等价覆盖。
- [ ] 断网、快照过期、认证失效、空列表、等待、审批、冲突和局部错误都有稳定状态。
- [ ] `1280x720`、`1440x900`、`1920x1080` 无横向溢出、文字遮挡或操作重叠。
- [ ] `npm run typecheck`、`npm test -- --run`、`npm run build` 和 `npx playwright test` 全部通过。
- [ ] 旧 DOM 视图、五列看板、旧主题硬编码和无替代 import 已删除。

该计划只覆盖 Web 前端工程实施。未来 Windows 壳层继续复用 React 页面和设计令牌，另行制定平台适配计划，不在本次迁移中选择 Electron 或 Tauri。
