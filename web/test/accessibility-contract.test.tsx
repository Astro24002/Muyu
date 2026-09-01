import { fireEvent, waitFor, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type {
  ActivityEvent,
  TaskApprovalRequest,
  TaskItem,
  WorkspaceSnapshot,
} from '../src/api/types';
import type { QrLoginController, QrLoginState } from '../src/auth/qr-login';
import { ActivityPage } from '../src/pages/ActivityPage';
import { AllTasksPage } from '../src/pages/AllTasksPage';
import { ApprovalsPage } from '../src/pages/ApprovalsPage';
import { QrLoginPage } from '../src/pages/QrLoginPage';
import { TodayPage } from '../src/pages/TodayPage';
import { TaskDetailPanel } from '../src/components/tasks/TaskDetailPanel';
import { ConflictPanel } from '../src/components/conflicts/ConflictPanel';
import { TopNav } from '../src/components/layout/TopNav';
import { UserMenu } from '../src/components/layout/UserMenu';
import { TaskComposer } from '../src/components/tasks/TaskComposer';
import type { TaskDetailActions } from '../src/tasks/task-detail-actions';
import type { TaskConflict } from '../src/tasks/task-model';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { render } from './react-test-helpers';

vi.mock('qrcode', () => ({
  default: { toCanvas: vi.fn(() => new Promise<HTMLCanvasElement>(() => undefined)) },
}));

const task: TaskItem = {
  id: 'task-1',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: '整理周末晚餐',
  description: '列出需要购买的食材',
  due_at: null,
  status: 'TODO',
  current_handler_id: 'viewer',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: 30,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-09-01T08:00:00Z',
  updated_at: '2026-09-01T08:00:00Z',
  assignee_ids: ['viewer', 'partner'],
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q2',
  labels: ['生活'],
  progress: null,
};

const incomingApproval: TaskApprovalRequest = {
  id: 'approval-1',
  workspace_id: 'workspace-1',
  task_id: task.id,
  comment_id: null,
  requester_id: 'partner',
  approver_id: 'viewer',
  request_type: 'TASK_UPDATE',
  proposed_changes: { title: '新标题' },
  base_field_versions: { title: 1 },
  request_id: 'request-1',
  status: 'PENDING',
  created_at: '2026-09-01T09:00:00Z',
  reviewed_at: null,
  reviewed_by: null,
  rejection_reason: null,
  resolved_cursor: null,
};

function makeSnapshot(overrides: Partial<WorkspaceSnapshot> = {}): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [{ user_id: 'viewer', member_slot: 1 }, { user_id: 'partner', member_slot: 2 }],
    tasks: [task],
    conflicts: [],
    cursor: 1,
    viewer_user_id: 'viewer',
    comments: [],
    approval_requests: [incomingApproval],
    ...overrides,
  };
}

function makeSync(overrides: Partial<WorkspaceSyncState> = {}): WorkspaceSyncController {
  let state: WorkspaceSyncState = {
    snapshot: makeSnapshot(),
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
    approvals: [incomingApproval],
    comments: [],
    ...overrides,
  };
  const listeners = new Set<(next: WorkspaceSyncState) => void>();
  return {
    get state(): WorkspaceSyncState { return state; },
    subscribe: (listener: (next: WorkspaceSyncState) => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    transitionTask: vi.fn().mockResolvedValue(undefined),
    createTask: vi.fn().mockResolvedValue(undefined),
    approveApproval: vi.fn().mockResolvedValue(undefined),
    rejectApproval: vi.fn().mockResolvedValue(undefined),
    cancelApproval: vi.fn().mockResolvedValue(undefined),
    __update(next: Partial<WorkspaceSyncState>) {
      state = { ...state, ...next };
      listeners.forEach((listener) => listener(state));
    },
  } as unknown as WorkspaceSyncController;
}

function makeActions(): TaskDetailActions {
  return {
    onTransition: vi.fn().mockResolvedValue(undefined),
    onComment: vi.fn().mockResolvedValue(undefined),
    onDelay: vi.fn().mockResolvedValue(undefined),
    onSave: vi.fn().mockResolvedValue(undefined),
    onDeleteComment: vi.fn().mockResolvedValue(undefined),
    onResolveConflict: vi.fn().mockResolvedValue(undefined),
    currentUserId: 'viewer',
    canWrite: true,
  };
}

function assertNamedFormControls(root: HTMLElement): void {
  for (const control of root.querySelectorAll<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>('input, textarea, select')) {
    const labelledBy = control.getAttribute('aria-labelledby');
    const hasAriaName = Boolean(control.getAttribute('aria-label')?.trim());
    const hasLabelReference = Array.from(root.querySelectorAll('label')).some((label) => (
      label.htmlFor === control.id || label.contains(control)
    ));
    const hasLabelledByText = Boolean(labelledBy && labelledBy.split(/\s+/).every((id) => root.querySelector(`#${CSS.escape(id)}`)?.textContent?.trim()));
    expect(hasAriaName || hasLabelReference || hasLabelledByText, `${control.outerHTML} must have an accessible name`).toBe(true);
  }
}

function assertButtonNames(root: HTMLElement): void {
  for (const button of root.querySelectorAll<HTMLButtonElement>('button')) {
    const hasName = Boolean(button.getAttribute('aria-label')?.trim() || button.textContent?.trim());
    expect(hasName, `${button.outerHTML} must have an accessible name`).toBe(true);
    if (!button.textContent?.trim()) expect(button).toHaveAttribute('aria-label');
  }
}

function assertNoNestedInteractive(root: HTMLElement): void {
  const selector = 'a[href], button, input, textarea, select, [role="button"], [role="link"], [role="menuitem"], [tabindex]:not([tabindex="-1"])';
  for (const element of root.querySelectorAll<HTMLElement>(selector)) {
    expect(element.parentElement?.closest(selector), `${element.outerHTML} must not be nested in an interactive element`).toBeNull();
  }
}

function assertTabReachable(element: HTMLElement): void {
  expect(element).not.toBeDisabled();
  expect(element.tabIndex).toBeGreaterThanOrEqual(0);
}

function assertBusyIsAnnounced(root: HTMLElement): void {
  for (const busy of root.querySelectorAll<HTMLElement>('[aria-busy="true"]')) {
    const announced = busy.getAttribute('aria-live') || busy.querySelector('[aria-live], [role="status"], [role="alert"]');
    expect(announced, `${busy.outerHTML} must announce its busy state`).toBeTruthy();
  }
}

describe('React accessibility contract', () => {
  it('names controls and keeps primary actions keyboard reachable across migrated workbench pages', async () => {
    const sync = makeSync();
    const today = render(<TodayPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    fireEvent.click(within(today.container).getByRole('button', { name: '记下一件事' }));
    assertNamedFormControls(today.container);
    assertButtonNames(today.container);
    assertNoNestedInteractive(today.container);
    assertTabReachable(within(today.container).getByRole('button', { name: '创建任务' }));
    today.unmount();

    const allTasks = render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    assertNamedFormControls(allTasks.container);
    assertButtonNames(allTasks.container);
    assertNoNestedInteractive(allTasks.container);
    assertTabReachable(within(allTasks.container).getByRole('button', { name: '记下一件事' }));
    assertTabReachable(within(allTasks.container).getByLabelText('状态'));
    allTasks.unmount();

    const approvals = render(<ApprovalsPage sync={sync} />);
    assertNamedFormControls(approvals.container);
    assertButtonNames(approvals.container);
    assertNoNestedInteractive(approvals.container);
    assertTabReachable(within(approvals.container).getByRole('button', { name: '批准' }));
    approvals.unmount();

    const activity = render(
      <ActivityPage
        tasks={[task]}
        getTaskActivity={vi.fn().mockResolvedValue([])}
      />,
    );
    await waitFor(() => expect(within(activity.container).getByText('还没有可展示的动态')).toBeInTheDocument());
    assertButtonNames(activity.container);
    assertNoNestedInteractive(activity.container);
    assertTabReachable(within(activity.container).getByRole('button', { name: '回到今天' }));
    activity.unmount();

    const detailState: WorkspaceSyncState = {
      ...sync.state,
      conflicts: [{ id: 'conflict-1', task_id: task.id, field: '标题', current: '当前', proposed: '提议' }],
      error: '同步失败',
    };
    const detail = render(
      <TaskDetailPanel
        task={task}
        members={detailState.snapshot!.members}
        syncState={detailState}
        actions={makeActions()}
        onClose={vi.fn()}
      />,
    );
    assertNamedFormControls(detail.container);
    assertButtonNames(detail.container);
    assertNoNestedInteractive(detail.container);
    assertTabReachable(within(detail.container).getByRole('button', { name: '保存' }));
    assertTabReachable(within(detail.container).getByRole('button', { name: '关闭任务详情' }));
    expect(within(detail.container).getByRole('alert')).toHaveTextContent('同步失败');
    detail.unmount();

    const conflict: TaskConflict = { id: 'conflict-2', task_id: task.id, field: '标题', current: '当前', proposed: '提议' };
    const conflicts = render(<ConflictPanel conflicts={[conflict]} busy={false} onResolve={vi.fn()} />);
    assertButtonNames(conflicts.container);
    assertNoNestedInteractive(conflicts.container);
    assertTabReachable(within(conflicts.container).getByRole('button', { name: '保留当前' }));
    assertTabReachable(within(conflicts.container).getByRole('button', { name: '采用提议' }));
  });

  it('exposes current navigation, icon-only names, QR labels, and UserMenu dialog semantics', () => {
    const nav = render(<TopNav route={{ kind: 'activity' }} onNavigate={vi.fn()} />);
    const navigation = within(nav.container).getByRole('navigation', { name: '主导航' });
    expect(within(navigation).getByRole('link', { name: '动态' })).toHaveAttribute('aria-current', 'page');
    expect(within(navigation).queryAllByRole('link', { current: 'page' })).toHaveLength(1);
    assertButtonNames(nav.container);
    assertNoNestedInteractive(nav.container);
    assertTabReachable(within(nav.container).getByRole('button', { name: '搜索' }));
    nav.unmount();

    const userMenu = render(<UserMenu />);
    const trigger = within(userMenu.container).getByRole('button', { name: '用户菜单' });
    expect(trigger).toHaveAttribute('aria-haspopup', 'dialog');
    fireEvent.click(trigger);
    const dialog = within(userMenu.container).getByRole('dialog', { name: '用户菜单' });
    expect(dialog).toHaveAttribute('aria-modal', 'false');
    expect(dialog).toHaveAttribute('aria-labelledby', 'muyu-user-menu-title');
    assertButtonNames(userMenu.container);
    assertNoNestedInteractive(userMenu.container);
    assertTabReachable(within(dialog).getByRole('button', { name: '退出登录' }));
    userMenu.unmount();

    const loginState: QrLoginState = {
      kind: 'waiting_for_approval',
      challenge: {
        challenge_id: 'challenge-1',
        qr_payload: 'safe-payload',
        origin: 'https://muyu.example',
        safety_code: '123456',
        expires_at: '2026-09-02T09:00:00Z',
      },
    };
    const login = {
      state: loginState,
      start: vi.fn().mockResolvedValue(undefined),
      poll: vi.fn().mockResolvedValue(undefined),
      subscribe: vi.fn(() => () => undefined),
    } as unknown as QrLoginController;
    const qr = render(<QrLoginPage controller={login} state={loginState} />);
    expect(within(qr.container).getByRole('img', { name: '登录二维码' })).toBeInTheDocument();
    assertButtonNames(qr.container);
    assertNoNestedInteractive(qr.container);
    assertTabReachable(within(qr.container).getByRole('button', { name: '检查授权状态' }));
    assertTabReachable(within(qr.container).getByRole('button', { name: '重新生成二维码' }));
  });

  it('announces sync, page errors, and busy states instead of relying on visual text alone', async () => {
    const errorSync = makeSync({ error: '同步失败' });
    const todayError = render(<TodayPage sync={errorSync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    expect(within(todayError.container).getByRole('alert')).toHaveTextContent('同步失败');
    todayError.unmount();

    const loadingSync = makeSync({ loading: true });
    const allTasksLoading = render(<AllTasksPage sync={loadingSync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    expect(within(allTasksLoading.container).getByRole('status')).toHaveAttribute('aria-live', 'polite');
    allTasksLoading.unmount();

    let releaseApproval!: () => void;
    const approvalSync = makeSync();
    (approvalSync.approveApproval as unknown as ReturnType<typeof vi.fn>).mockReturnValue(new Promise<void>((resolve) => { releaseApproval = resolve; }));
    const approvals = render(<ApprovalsPage sync={approvalSync} />);
    fireEvent.click(within(approvals.container).getByRole('button', { name: '批准' }));
    const approvalRow = approvals.container.querySelector(`[data-approval-id="${incomingApproval.id}"]`);
    expect(approvalRow).not.toBeNull();
    expect(within(approvalRow as HTMLElement).getByRole('status')).toHaveAttribute('aria-live', 'polite');
    releaseApproval();
    approvals.unmount();

    const activity = render(
      <ActivityPage
        tasks={[task]}
        getTaskActivity={vi.fn(() => new Promise<ActivityEvent[]>(() => undefined))}
      />,
    );
    expect(within(activity.container).getByRole('status')).toHaveAttribute('aria-live', 'polite');
    activity.unmount();

    const detail = render(
      <TaskDetailPanel
        task={task}
        members={[]}
        syncState={makeSync().state}
        actions={makeActions()}
        onClose={vi.fn()}
        activityState={{ status: 'loading', events: [] }}
      />,
    );
    expect(within(detail.container).getByRole('status')).toHaveAttribute('aria-live', 'polite');
    detail.unmount();

    let releaseCreate!: () => void;
    const composer = render(
      <TaskComposer
        sync={makeSync()}
        onCreateTask={vi.fn(() => new Promise<void>((resolve) => { releaseCreate = resolve; }))}
      />,
    );
    fireEvent.click(within(composer.container).getByRole('button', { name: '记下一件事' }));
    fireEvent.change(within(composer.container).getByLabelText('任务标题'), { target: { value: '新任务' } });
    fireEvent.change(within(composer.container).getByLabelText('四象限'), { target: { value: 'Q2' } });
    fireEvent.click(within(composer.container).getByRole('button', { name: '创建任务' }));
    expect(within(composer.container).getByRole('button', { name: '正在保存' })).toBeInTheDocument();
    assertBusyIsAnnounced(composer.container);
    releaseCreate();
    composer.unmount();

    const qr = render(
      <QrLoginPage
        state={{ kind: 'creating' }}
        controller={{ state: { kind: 'creating' }, start: vi.fn(), poll: vi.fn(), subscribe: vi.fn(() => () => undefined) } as unknown as QrLoginController}
      />,
    );
    assertBusyIsAnnounced(qr.container);
  });

  it('marks QR failures as alerts and keeps the main recovery action reachable', () => {
    const controller = {
      state: { kind: 'failure', message: '二维码不可用' },
      start: vi.fn().mockResolvedValue(undefined),
      poll: vi.fn().mockResolvedValue(undefined),
      subscribe: vi.fn(() => () => undefined),
    } as unknown as QrLoginController;
    const qr = render(<QrLoginPage controller={controller} state={{ kind: 'failure', message: '二维码不可用' }} />);
    expect(within(qr.container).getByRole('alert')).toHaveTextContent('二维码不可用');
    assertButtonNames(qr.container);
    assertTabReachable(within(qr.container).getByRole('button', { name: '重新生成二维码' }));
  });
});
