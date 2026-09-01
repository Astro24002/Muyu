import { fireEvent, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, type ApiClient } from '../src/api/client';
import type { QrLoginController } from '../src/auth/qr-login';
import type { ActivityEvent, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import { App } from '../src/app/App';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { TaskTimeline } from '../src/components/tasks/TaskTimeline';
import { render } from './react-test-helpers';

const taskOne: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26090001',
  title: '第一件事', description: '第一件事描述', due_at: null, status: 'TODO', current_handler_id: 'viewer',
  blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null,
  planned_start_at: null, estimated_minutes: 30, completed_at: null, created_by: 'viewer',
  created_at: '2026-08-30T08:00:00Z', updated_at: '2026-08-30T08:00:00Z', assignee_ids: ['viewer'],
  delay_count: 0, total_delay_minutes: 0, version: 1, status_version: 1, field_versions: {},
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: [], progress: null,
};

const taskTwo: TaskItem = { ...taskOne, id: 'task-2', task_number: '26090002', title: '第二件事' };

const eventOne: ActivityEvent = {
  kind: 'operation', id: 'event-1', created_at: '2026-09-01T08:00:00Z', operation_type: 'UPDATE',
  actor_user_id: 'viewer', body: '第一件事的旧活动',
};

const eventTwo: ActivityEvent = {
  kind: 'operation', id: 'event-2', created_at: '2026-09-01T09:00:00Z', operation_type: 'UPDATE',
  actor_user_id: 'viewer', body: '第二件事的当前活动',
};

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void; reject: (reason: unknown) => void } {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function makeSnapshot(tasks: TaskItem[] = [taskOne, taskTwo]): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [{ user_id: 'viewer', member_slot: 1 }], tasks, conflicts: [], cursor: 1,
    viewer_user_id: 'viewer', comments: [], approval_requests: [],
  };
}

function makeSync(): WorkspaceSyncController {
  const state: WorkspaceSyncState = {
    snapshot: makeSnapshot(), cursor: 1, loading: false, stale: false, error: null,
    conflicts: [], authRequired: false, comments: [], approvals: [],
  };
  const listeners = new Set<(next: WorkspaceSyncState) => void>();
  return {
    get state(): WorkspaceSyncState { return state; },
    loadSnapshot: vi.fn().mockResolvedValue(undefined),
    pull: vi.fn().mockResolvedValue(undefined),
    subscribe(listener: (next: WorkspaceSyncState) => void): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    dispose: vi.fn(),
    clear: vi.fn(),
    transitionTask: vi.fn().mockResolvedValue(undefined),
    patchTask: vi.fn().mockResolvedValue(undefined),
    addComment: vi.fn().mockResolvedValue(undefined),
    addDelay: vi.fn().mockResolvedValue(undefined),
    deleteTaskComment: vi.fn().mockResolvedValue(undefined),
    resolveConflict: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;
}

function makeLogin(): QrLoginController {
  return {
    state: { kind: 'signed_in', expiresAt: '2026-09-02T00:00:00Z' },
    subscribe: () => () => undefined,
    start: vi.fn(), stop: vi.fn(), dispose: vi.fn(),
  } as unknown as QrLoginController;
}

function makeSocketFactory(): NonNullable<React.ComponentProps<typeof App>['socketFactory']> {
  return () => ({ onopen: null, onclose: null, onerror: null, onmessage: null, close: vi.fn() });
}

afterEach(() => {
  window.location.hash = '';
});

describe('TaskTimeline activity state', () => {
  it('distinguishes loading and a genuinely empty activity result', () => {
    const { rerender } = render(
      <TaskTimeline activityState={{ status: 'loading', events: [] }} />,
    );

    expect(screen.getByRole('status')).toHaveTextContent('正在加载活动记录');
    expect(screen.queryByText('暂无活动')).not.toBeInTheDocument();

    rerender(<TaskTimeline activityState={{ status: 'success', events: [] }} />);
    expect(screen.getByText('暂无活动')).toBeInTheDocument();
  });

  it('shows permission errors without presenting them as an empty timeline', () => {
    render(
      <TaskTimeline
        activityState={{ status: 'error', events: [], error: '当前账号无权查看活动记录。', retryable: false }}
        onRetry={vi.fn()}
      />,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('无权查看活动记录');
    expect(screen.queryByText('暂无活动')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '重试' })).not.toBeInTheDocument();
  });

  it('exposes a retry action for recoverable activity failures', () => {
    const onRetry = vi.fn();
    render(
      <TaskTimeline
        activityState={{ status: 'error', events: [], error: '活动记录加载失败，请重试。', retryable: true }}
        onRetry={onRetry}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: '重试' }));
    expect(onRetry).toHaveBeenCalledOnce();
  });
});

describe('App activity loading', () => {
  it('renders loading and then a real empty activity result', async () => {
    window.location.hash = '#/tasks/task-1';
    const activity = deferred<ActivityEvent[]>();
    const api = { getTaskActivity: vi.fn(() => activity.promise) } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} socketFactory={makeSocketFactory()} />);

    await waitFor(() => expect(screen.getByText(/正在加载活动记录/)).toBeInTheDocument());
    activity.resolve([]);
    await waitFor(() => expect(screen.getByText('暂无活动')).toBeInTheDocument());
  });

  it.each([401, 403])('shows %s permission failures without presenting an empty timeline or retry', async (status) => {
    window.location.hash = '#/tasks/task-1';
    const getTaskActivity = vi.fn()
      .mockRejectedValueOnce(new ApiError(status, status === 401 ? 'unauthorized' : 'forbidden', 'permission denied'));
    const api = { getTaskActivity } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} socketFactory={makeSocketFactory()} />);

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('无权查看活动记录'));
    expect(screen.queryByText('暂无活动')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '重试' })).not.toBeInTheDocument();
  });

  it('distinguishes a missing activity resource from a permission failure and offers recovery', async () => {
    window.location.hash = '#/tasks/task-1';
    const getTaskActivity = vi.fn().mockRejectedValueOnce(new ApiError(404, 'not_found', 'not found'));
    const api = { getTaskActivity } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} socketFactory={makeSocketFactory()} />);

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('无法找到活动记录'));
    expect(screen.getByRole('button', { name: '重试' })).toBeInTheDocument();
    expect(screen.queryByText('无权查看活动记录')).not.toBeInTheDocument();
  });

  it('retries a service failure and renders the recovered activity', async () => {
    window.location.hash = '#/tasks/task-1';
    const getTaskActivity = vi.fn()
      .mockRejectedValueOnce(new Error('服务暂时不可用'))
      .mockResolvedValueOnce([eventOne]);
    const api = { getTaskActivity } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} socketFactory={makeSocketFactory()} />);

    await waitFor(() => expect(screen.getByRole('button', { name: '重试' })).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: '重试' }));
    await waitFor(() => expect(screen.getByText('第一件事的旧活动')).toBeInTheDocument());
    expect(getTaskActivity).toHaveBeenCalledTimes(2);
  });

  it('ignores a late activity response after the task route changes', async () => {
    window.location.hash = '#/tasks/task-1';
    const first = deferred<ActivityEvent[]>();
    const second = deferred<ActivityEvent[]>();
    const getTaskActivity = vi.fn((id: string) => id === taskOne.id ? first.promise : second.promise);
    const api = { getTaskActivity } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} socketFactory={makeSocketFactory()} />);

    await waitFor(() => expect(getTaskActivity).toHaveBeenCalledWith(taskOne.id));
    window.location.hash = '#/tasks/task-2';
    await waitFor(() => expect(getTaskActivity).toHaveBeenCalledWith(taskTwo.id));

    second.resolve([eventTwo]);
    await waitFor(() => expect(screen.getByText('第二件事的当前活动')).toBeInTheDocument());
    first.resolve([eventOne]);
    await waitFor(() => expect(screen.queryByText('第一件事的旧活动')).not.toBeInTheDocument());
    expect(screen.getByText('第二件事的当前活动')).toBeInTheDocument();
  });
});
