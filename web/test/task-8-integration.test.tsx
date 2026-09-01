import { screen, waitFor, fireEvent } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, type ApiClient } from '../src/api/client';
import type { QrLoginController } from '../src/auth/qr-login';
import type { TaskItem, WorkspaceSnapshot } from '../src/api/types';
import { App } from '../src/app/App';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { render } from './react-test-helpers';

const task: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26090001',
  title: '整理周末晚餐', description: '列出食材', due_at: null, status: 'TODO', current_handler_id: 'viewer',
  blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null,
  planned_start_at: null, estimated_minutes: 30, completed_at: null, created_by: 'viewer',
  created_at: '2026-08-30T08:00:00Z', updated_at: '2026-08-30T08:00:00Z', assignee_ids: ['viewer'],
  delay_count: 0, total_delay_minutes: 0, version: 1, status_version: 1, field_versions: {},
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: [], progress: null,
};

function snapshot(): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [{ user_id: 'viewer', member_slot: 1 }], tasks: [task], conflicts: [], cursor: 1,
    viewer_user_id: 'viewer', comments: [], approval_requests: [],
  };
}

function makeSync(): WorkspaceSyncController {
  let state: WorkspaceSyncState = {
    snapshot: snapshot(), cursor: 1, loading: false, stale: false, error: null,
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
    clear: vi.fn(() => {
      state = { ...state, snapshot: null, approvals: [], comments: [] };
      listeners.forEach((listener) => listener(state));
    }),
    dispose: vi.fn(),
    createTask: vi.fn().mockResolvedValue(undefined),
    transitionTask: vi.fn().mockResolvedValue(undefined),
    patchTask: vi.fn().mockResolvedValue(undefined),
    addTaskComment: vi.fn().mockResolvedValue(undefined),
    addTaskDelay: vi.fn().mockResolvedValue(undefined),
    deleteTaskComment: vi.fn().mockResolvedValue(undefined),
    resolveConflict: vi.fn().mockResolvedValue(undefined),
    approveApproval: vi.fn().mockResolvedValue(undefined),
    rejectApproval: vi.fn().mockResolvedValue(undefined),
    cancelApproval: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;
}

function makeLogin(): QrLoginController {
  return {
    state: { kind: 'signed_in', expiresAt: '2026-09-02T00:00:00Z' },
    subscribe: () => () => undefined,
    start: vi.fn(), stop: vi.fn(), dispose: vi.fn(),
  } as unknown as QrLoginController;
}

afterEach(() => {
  window.location.hash = '';
});

describe('Task 8 App integration', () => {
  it('does not request activity until the activity route is active', async () => {
    window.location.hash = '#/today';
    const getTaskActivity = vi.fn().mockResolvedValue([{
      kind: 'operation', id: 'event-1', created_at: '2026-09-01T09:00:00Z',
      operation_type: 'UPDATE', actor_user_id: 'viewer', body: '已更新',
    }]);
    const api = { getTaskActivity } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} />);

    await waitFor(() => expect(screen.getByRole('heading', { name: '今天，先让一件事向前走' })).toBeInTheDocument());
    expect(getTaskActivity).not.toHaveBeenCalled();

    window.location.hash = '#/activity';
    await waitFor(() => expect(getTaskActivity).toHaveBeenCalledWith(task.id));
    expect(await screen.findByText('已更新')).toBeInTheDocument();
    expect(screen.getByText(task.title)).toBeInTheDocument();
    expect(screen.getByTestId('muyu-app')).toHaveAttribute('data-route', 'activity');
    expect(screen.queryByTestId('legacy-app-root')).not.toBeInTheDocument();
  });

  it('routes a session 401 through the App QR-login recovery lifecycle', async () => {
    window.location.hash = '#/today';
    const api = {
      listWebSessions: vi.fn().mockRejectedValue(new ApiError(401, 'AUTH', 'expired')),
      revokeWebSession: vi.fn().mockResolvedValue(undefined),
      revokeAllWebSessions: vi.fn().mockResolvedValue(undefined),
    } as unknown as ApiClient;
    render(<App api={api} login={makeLogin()} sync={makeSync()} />);

    await waitFor(() => expect(screen.getByRole('heading', { name: '今天，先让一件事向前走' })).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: '用户菜单' }));
    await waitFor(() => expect(screen.getByTestId('qr-login-page')).toBeInTheDocument());
    expect(screen.queryByTestId('legacy-app-root')).not.toBeInTheDocument();
  });
});
