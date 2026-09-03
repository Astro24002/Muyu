import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskItem, WorkspaceSnapshot } from '../src/api/types';
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
    fireEvent.change(screen.getByLabelText('标签'), { target: { value: '工作' } });
    expect(screen.getByRole('heading', { name: '写工作计划' })).toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(1);

    fireEvent.change(screen.getByLabelText('标签'), { target: { value: '' } });
    fireEvent.click(screen.getByRole('checkbox', { name: '只看我的任务' }));
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(2);
    expect(screen.queryByRole('heading', { name: '准备晚餐' })).toBeNull();
    expect(tasks.map((task) => task.id)).toEqual(originalOrder);
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
      screen.getByLabelText('标签'),
      screen.getByRole('checkbox', { name: '只看我的任务' }),
    ];

    for (const unavailableState of ['loading', 'stale', 'authRequired'] as const) {
      updateState({ loading: false, stale: false, authRequired: false, [unavailableState]: true });
      rerender(<AllTasksPage sync={sync} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
      getFilterControls().forEach((control) => expect(control).toBeDisabled());
    }
  });
});

function createFakeSync(tasks: TaskItem[]): {
  sync: WorkspaceSyncController;
  updateState: (patch: Partial<WorkspaceSyncState>) => void;
} {
  let state: WorkspaceSyncState = {
    snapshot: makeSnapshot(tasks),
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

function makeSnapshot(tasks: TaskItem[]): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [],
    tasks,
    conflicts: [],
    cursor: 1,
    viewer_user_id: 'viewer',
  };
}
