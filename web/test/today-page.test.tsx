import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskApprovalRequest, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { TodayPage } from '../src/pages/TodayPage';
import { render } from './react-test-helpers';

const makeTask = (overrides: Partial<TaskItem> = {}): TaskItem => ({
  id: 'task-1',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: '整理周末晚餐',
  description: '列出需要购买的食材',
  due_at: '2026-09-01T12:00:00Z',
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
  created_at: '2026-08-30T08:00:00Z',
  updated_at: '2026-08-30T08:00:00Z',
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
  ...overrides,
});

const makeApproval = (overrides: Partial<TaskApprovalRequest> = {}): TaskApprovalRequest => ({
  id: 'approval-1',
  workspace_id: 'workspace-1',
  task_id: 'task-1',
  comment_id: null,
  requester_id: 'partner',
  approver_id: 'viewer',
  request_type: 'TASK_UPDATE',
  proposed_changes: {},
  base_field_versions: {},
  request_id: 'request-1',
  status: 'PENDING',
  created_at: '2026-08-31T08:00:00Z',
  reviewed_at: null,
  reviewed_by: null,
  rejection_reason: null,
  resolved_cursor: null,
  ...overrides,
});

describe('TodayPage', () => {
  it('renders the action sections in the prescribed order and wires approval navigation', () => {
    const focus = makeTask({ id: 'focus', title: '继续整理周末晚餐', status: 'IN_PROGRESS', progress: 40, updated_at: '2026-08-31T10:00:00Z' });
    const next = makeTask({ id: 'next', title: '买橄榄油', due_at: '2026-09-02T12:00:00Z' });
    const blocked = makeTask({ id: 'blocked', title: '等伙伴确认菜单', status: 'BLOCKED', blocked_reason: '等待伙伴确认' });
    const { sync } = createFakeSync([focus, next, blocked], [makeApproval()]);
    const onOpenTask = vi.fn();

    render(<TodayPage sync={sync} onOpenTask={onOpenTask} onCreateTask={vi.fn()} />);

    expect(Array.from(document.querySelectorAll('[data-today-section]')).map((node) => node.getAttribute('data-today-section')))
      .toEqual(['intro', 'sync', 'focus', 'next', 'blocked', 'approval', 'composer']);
    expect(screen.getByRole('heading', { name: '今天，先让一件事向前走' })).toBeInTheDocument();
    expect(screen.getByTestId('today-date')).toHaveTextContent('2026');
    expect(screen.getByText('刚刚同步')).toBeInTheDocument();
    expect(screen.getByText(focus.title)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: '接下来' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: '阻塞中' })).toBeInTheDocument();
    expect(screen.getByText('有 1 个变更等你确认')).toBeInTheDocument();
    expect(screen.getByText('不用清空列表，完成真正重要的一步就好')).toBeInTheDocument();
    expect(document.querySelector('[data-kpi-card]')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: '去处理' }));
    expect(window.location.hash).toBe('#/approvals');
  });

  it('omits an empty focus region and gives an empty workspace one clear action', () => {
    const { sync } = createFakeSync([]);

    render(<TodayPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(document.querySelector('[data-today-section="focus"]')).toBeNull();
    expect(screen.getByText('今天没有需要处理的任务')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '记下一件事' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: '阻塞中' })).toBeNull();
  });

  it('completes a next task through the sync controller without opening it', () => {
    const task = makeTask({ id: 'next-task', title: '完成下一步' });
    const { sync } = createFakeSync([task]);
    const onOpenTask = vi.fn();

    render(<TodayPage sync={sync} onOpenTask={onOpenTask} onCreateTask={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: '完成' }));

    expect(sync.transitionTask).toHaveBeenCalledWith(task.id, 'DONE');
    expect(onOpenTask).not.toHaveBeenCalled();
  });
});

function createFakeSync(tasks: TaskItem[], approvals: TaskApprovalRequest[] = []): {
  sync: WorkspaceSyncController;
  setState: (state: WorkspaceSyncState) => void;
} {
  let current: WorkspaceSyncState = {
    snapshot: makeSnapshot(tasks, approvals),
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
    approvals,
  };
  const listeners = new Set<(state: WorkspaceSyncState) => void>();
  const sync = {
    get state(): WorkspaceSyncState { return current; },
    subscribe: vi.fn((listener: (state: WorkspaceSyncState) => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    }),
    transitionTask: vi.fn().mockResolvedValue(undefined),
    createTask: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;

  return {
    sync,
    setState: (state) => {
      current = state;
      for (const listener of listeners) listener(current);
    },
  };
}

function makeSnapshot(tasks: TaskItem[], approvals: TaskApprovalRequest[]): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [],
    tasks,
    conflicts: [],
    cursor: 1,
    viewer_user_id: 'viewer',
    approval_requests: approvals,
  };
}
