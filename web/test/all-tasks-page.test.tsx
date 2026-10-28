import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskApprovalRequest, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { AllTasksPage } from '../src/pages/AllTasksPage';
import { render } from './react-test-helpers';

const makeTask = (overrides: Partial<TaskItem> = {}): TaskItem => ({
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
  estimated_minutes: null,
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

describe('AllTasksPage', () => {
  it('filters status, quadrant, labels, and ownership locally while keeping the source order intact', () => {
    const tasks = [
      makeTask({ id: 'todo-work', title: '写工作计划', status: 'TODO', quadrant: 'Q1', labels: ['工作'], current_handler_id: 'viewer' }),
      makeTask({ id: 'progress-life', title: '准备晚餐', status: 'IN_PROGRESS', quadrant: 'Q2', labels: ['生活'], current_handler_id: 'partner' }),
      makeTask({ id: 'blocked-reading', title: '等待书单确认', status: 'BLOCKED', quadrant: 'Q3', labels: ['阅读'], current_handler_id: 'viewer' }),
    ];
    const originalOrder = tasks.map((task) => task.id);
    const { sync } = createFakeSync(tasks);

    render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(3);
    expect(document.querySelectorAll('[data-task-row]')[0]).toHaveTextContent('写工作计划');

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
    expect(screen.getByRole('heading', { name: '准备晚餐' })).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q3' } });
    expect(screen.getByRole('heading', { name: '等待书单确认' })).toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);

    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('分类'), { target: { value: '工作' } });
    expect(screen.getByRole('heading', { name: '写工作计划' })).toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);

    fireEvent.change(screen.getByLabelText('分类'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('负责人'), { target: { value: 'mine' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(2);
    expect(screen.queryByRole('heading', { name: '准备晚餐' })).toBeNull();
    expect(tasks.map((task) => task.id)).toEqual(originalOrder);
  });

  it('searches task facts and filters the v1 task scopes from the shared snapshot', () => {
    const tasks = [
      makeTask({ id: 'open', title: '准备旅行', status: 'IN_PROGRESS', current_handler_id: 'viewer', labels: ['出行'], next_step_text: '确认车票' }),
      makeTask({ id: 'blocked', title: '整理行李', status: 'BLOCKED', current_handler_id: 'partner', labels: ['出行'], next_step_text: '等 TA 回复' }),
      makeTask({ id: 'review', title: '预订酒店', status: 'REVIEW', current_handler_id: 'viewer', labels: ['旅行'], next_step_text: '检查订单' }),
      makeTask({ id: 'transfer', title: '确认接送时间', status: 'IN_PROGRESS', current_handler_id: 'partner', labels: ['安排'], next_step_text: '问 Alex 是否方便' }),
      makeTask({ id: 'done', title: '买好车票', status: 'DONE', current_handler_id: 'viewer', labels: ['出行'], completed_at: '2026-08-31T08:00:00Z' }),
    ];
    const transferRequest: TaskApprovalRequest = {
      id: 'approval-transfer', workspace_id: 'workspace-1', task_id: 'transfer', comment_id: null,
      requester_id: 'viewer', approver_id: 'partner', request_type: 'HANDLER_TRANSFER', proposed_changes: {},
      base_field_versions: {}, request_id: 'request-transfer', status: 'PENDING', created_at: '2026-08-30T08:00:00Z',
      reviewed_at: null, reviewed_by: null, rejection_reason: null, resolved_cursor: null,
    };
    const { sync } = createFakeSync(tasks, [transferRequest]);

    render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    const search = screen.getByRole('searchbox', { name: '搜索全部事情' });
    fireEvent.change(search, { target: { value: '确认车票' } });
    expect(screen.getByRole('heading', { name: '准备旅行' })).toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);

    fireEvent.change(search, { target: { value: 'Alex' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(2);
    fireEvent.change(search, { target: { value: '出行' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(2);
    fireEvent.change(search, { target: { value: '整理行李' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
    fireEvent.change(search, { target: { value: '检查订单' } });
    expect(screen.getByRole('heading', { name: '预订酒店' })).toBeInTheDocument();

    fireEvent.change(search, { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'open' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(4);
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'all' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(5);
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'blocked' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'review' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'transfer' } });
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
    fireEvent.change(screen.getByLabelText('任务范围'), { target: { value: 'done' } });
    expect(screen.getByRole('heading', { name: '买好车票' })).toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);
  });

  it('keeps preview browsing read-only while leaving filters available', () => {
    const { sync } = createFakeSync([makeTask()]);
    render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} readOnly />);

    expect(screen.queryByRole('button', { name: '新建任务' })).toBeNull();
    expect(screen.queryByRole('button', { name: '开始' })).toBeNull();
    expect(screen.getByRole('searchbox', { name: '搜索全部事情' })).toBeEnabled();
    expect(screen.getByLabelText('任务范围')).toBeEnabled();
  });

  it('uses the shared task row and routes the start action through sync', () => {
    const task = makeTask({ id: 'start-me', title: '可以开始的任务' });
    const { sync } = createFakeSync([task]);

    render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(screen.getByRole('heading', { name: task.title })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '开始' }));
    expect(sync.transitionTask).toHaveBeenCalledWith(task.id, 'IN_PROGRESS');
  });

  it('disables every filter control while sync is unavailable', () => {
    const { sync, updateState } = createFakeSync([makeTask()]);
    const { rerender } = render(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    const getFilterControls = (): HTMLElement[] => [
      screen.getByLabelText('状态'),
      screen.getByLabelText('四象限'),
      screen.getByLabelText('分类'),
      screen.getByLabelText('负责人'),
    ];

    for (const unavailableState of ['loading', 'stale', 'authRequired'] as const) {
      updateState({ loading: false, stale: false, authRequired: false, [unavailableState]: true });
      rerender(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
      getFilterControls().forEach((control) => expect(control).toBeDisabled());
    }
  });
});

function createFakeSync(tasks: TaskItem[], approvalRequests: TaskApprovalRequest[] = []): {
  sync: WorkspaceSyncController;
  updateState: (patch: Partial<WorkspaceSyncState>) => void;
} {
  let state: WorkspaceSyncState = {
    snapshot: makeSnapshot(tasks, approvalRequests),
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
  };
  const listeners = new Set<(nextState: WorkspaceSyncState) => void>();
  const sync = {
    get state(): WorkspaceSyncState { return state; },
    subscribe: vi.fn((listener: (nextState: WorkspaceSyncState) => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    }),
    transitionTask: vi.fn().mockResolvedValue(undefined),
    createTask: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;
  const updateState = (patch: Partial<WorkspaceSyncState>): void => {
    state = { ...state, ...patch };
    listeners.forEach((listener) => listener(state));
  };
  return { sync, updateState };
}

function makeSnapshot(tasks: TaskItem[], approvalRequests: TaskApprovalRequest[] = []): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [
      { user_id: 'viewer', display_name: '我', member_slot: 1, membership_status: 'ACTIVE' },
      { user_id: 'partner', display_name: 'Alex', member_slot: 2, membership_status: 'ACTIVE' },
    ],
    tasks,
    approval_requests: approvalRequests,
    conflicts: [],
    cursor: 1,
    viewer_user_id: 'viewer',
  };
}
