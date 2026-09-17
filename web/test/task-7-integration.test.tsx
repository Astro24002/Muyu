import { fireEvent, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { ApiClient } from '../src/api/client';
import type { QrLoginController } from '../src/auth/qr-login';
import type { TaskApprovalRequest, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import { App } from '../src/app/App';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { render } from './react-test-helpers';

const task: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26090001',
  title: '整理周末晚餐', description: '列出需要购买的食材', due_at: '2026-09-02T12:00:00Z',
  status: 'TODO', current_handler_id: 'viewer', blocked_reason: null, blocked_since: null,
  resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: 30,
  completed_at: null, created_by: 'viewer', created_at: '2026-08-30T08:00:00Z',
  updated_at: '2026-08-30T08:00:00Z', delay_count: 0,
  total_delay_minutes: 0, version: 2, status_version: 1, field_versions: { title: 2 },
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: ['生活'], progress: null,
};

const approval: TaskApprovalRequest = {
  id: 'approval-1', workspace_id: 'workspace-1', task_id: task.id, comment_id: null,
  requester_id: 'partner', approver_id: 'viewer', request_type: 'TASK_UPDATE',
  proposed_changes: { title: '伙伴提出的新标题' }, base_field_versions: { title: 1 },
  request_id: 'request-1', status: 'PENDING', created_at: '2026-09-01T08:00:00Z',
  reviewed_at: null, reviewed_by: null, rejection_reason: null, resolved_cursor: null,
};

function makeSnapshot(): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [{ user_id: 'viewer', member_slot: 1 }, { user_id: 'partner', member_slot: 2 }],
    tasks: [task], conflicts: [], cursor: 8, viewer_user_id: 'viewer', comments: [],
    approval_requests: [approval],
  };
}

function makeApp(): { sync: WorkspaceSyncController; login: QrLoginController } {
  let state: WorkspaceSyncState = {
    snapshot: makeSnapshot(), cursor: 8, loading: false, stale: false, error: null,
    conflicts: [], authRequired: false, approvals: [approval], comments: [],
  };
  const listeners = new Set<(next: WorkspaceSyncState) => void>();
  const sync = {
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
  const login = {
    state: { kind: 'signed_in', expiresAt: '2026-09-02T00:00:00Z' },
    subscribe: () => () => undefined,
    start: vi.fn(),
    stop: vi.fn(),
    dispose: vi.fn(),
  } as unknown as QrLoginController;
  return { sync, login };
}

afterEach(() => {
  window.location.hash = '';
});

describe('Task 7 App integration', () => {
  it('renders the React approvals route', async () => {
    window.location.hash = '#/approvals';
    const { sync, login } = makeApp();
    render(<App api={{} as ApiClient} login={login} sync={sync} />);

    await waitFor(() => expect(screen.getByRole('heading', { name: '审批' })).toBeInTheDocument());

    expect(screen.getByTestId('muyu-app')).toHaveAttribute('data-route', 'approvals');
    expect(screen.getByTestId('react-route')).toHaveAttribute('data-route', 'approvals');
  });

  it.each(['today', 'tasks'] as const)('opens and closes a React task panel while preserving the %s list context', async (listRoute) => {
    window.location.hash = `#/${listRoute}`;
    const { sync, login } = makeApp();
    render(<App api={{} as ApiClient} login={login} sync={sync} />);

    const taskTrigger = await waitFor(() => screen.getByRole('button', { name: '整理周末晚餐' }));
    fireEvent.click(taskTrigger);

    await waitFor(() => expect(window.location.hash).toBe('#/tasks/task-1'));
    expect(screen.getByRole('dialog', { name: '任务详情' })).toBeInTheDocument();
    expect(screen.getByTestId('muyu-app')).toHaveAttribute('data-route', 'task:task-1');
    expect(document.querySelector(`[data-${listRoute === 'today' ? 'matters' : 'all-tasks'}-page`)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: '关闭任务详情' }));
    await waitFor(() => expect(window.location.hash).toBe(`#/${listRoute}`));
    expect(document.querySelector(`[data-${listRoute === 'today' ? 'matters' : 'all-tasks'}-page`)).toBeInTheDocument();
    expect(document.activeElement).toBe(taskTrigger);
  });

  it('restores focus to the task control after closing the detail panel with Escape', async () => {
    window.location.hash = '#/tasks';
    const { sync, login } = makeApp();
    render(<App api={{} as ApiClient} login={login} sync={sync} />);

    const taskTrigger = await waitFor(() => screen.getByRole('button', { name: '整理周末晚餐' }));
    taskTrigger.focus();
    fireEvent.click(taskTrigger);
    await waitFor(() => expect(screen.getByRole('dialog', { name: '任务详情' })).toBeInTheDocument());

    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(window.location.hash).toBe('#/tasks'));

    expect(document.activeElement).toBe(taskTrigger);
  });
});
