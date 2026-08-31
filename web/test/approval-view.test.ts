import { describe, expect, it, vi } from 'vitest';
import { ApiClient } from '../src/api/client';
import type { TaskApprovalRequest, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import { ApprovalView } from '../src/ui/approval-view';
import { WorkspaceSyncController, type WorkspaceSyncState } from '../src/sync/workspace-sync';

const approval: TaskApprovalRequest = {
  id: 'approval-1',
  workspace_id: 'workspace-1',
  task_id: 'task-1',
  comment_id: null,
  requester_id: 'user-2',
  approver_id: 'user-1',
  request_type: 'TASK_UPDATE',
  proposed_changes: { title: 'Pending title' },
  base_field_versions: { title: 1 },
  request_id: 'request-1',
  status: 'PENDING',
  created_at: '2026-08-28T00:00:00Z',
  reviewed_at: null,
  reviewed_by: null,
  rejection_reason: null,
  resolved_cursor: null,
};

const task: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26080001', title: 'Original', description: '',
  due_at: null, status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null,
  waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'user-1',
  created_at: '2026-08-28T00:00:00Z', updated_at: '2026-08-28T00:00:00Z', assignee_ids: ['user-1', 'user-2'], delay_count: 0,
  total_delay_minutes: 0, version: 1, status_version: 1, field_versions: { title: 1 }, lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: [],
};

function snapshot(): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [{ user_id: 'user-1', member_slot: 1 }, { user_id: 'user-2', member_slot: 2 }], tasks: [task], conflicts: [],
    viewer_user_id: 'user-1', comments: [], approval_requests: [], cursor: 5,
  };
}

describe('Web task approvals', () => {
  it('sends approval request and action bodies using the backend snake_case contract', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const path = String(input);
      if (path.endsWith('/approval-requests')) return new Response(JSON.stringify(approval), { status: 201 });
      return new Response(JSON.stringify({ approval_request: approval, cursor: 6 }), { status: 200 });
    });
    const client = new ApiClient();

    await client.createApprovalRequest({
      workspaceId: 'workspace-1', requestId: 'request-1', taskId: 'task-1', requestType: 'TASK_UPDATE',
      proposedChanges: { title: 'Pending title' }, baseFieldVersions: { title: 1 },
    });
    await client.approveApproval('approval-1', { workspaceId: 'workspace-1', requestId: 'action-1' });

    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/workspaces/workspace-1/approval-requests');
    expect(fetchMock.mock.calls[0][1]).toEqual(expect.objectContaining({
      credentials: 'include',
      body: JSON.stringify({
        request_id: 'request-1', task_id: 'task-1', comment_id: null, request_type: 'TASK_UPDATE',
        proposed_changes: { title: 'Pending title' }, base_field_versions: { title: 1 },
      }),
    }));
    expect(fetchMock.mock.calls[1][0]).toBe('/api/v1/workspaces/workspace-1/approval-requests/approval-1/approve');
    expect(fetchMock.mock.calls[1][1]).toEqual(expect.objectContaining({ body: JSON.stringify({ request_id: 'action-1' }) }));
  });

  it('keeps the task unchanged when a task write returns a pending approval', async () => {
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue(snapshot()),
      getWorkspaceChanges: vi.fn().mockResolvedValue({
        workspace_id: 'workspace-1', cursor: 6,
        changes: [{ cursor: 6, resource_type: 'approval_request', resource_id: approval.id, action: 'UPDATED', operation_id: null, resource: approval }],
      }),
      createTask: vi.fn(),
      patchTask: vi.fn().mockResolvedValue({ pending: true, approval_request: approval, cursor: 6 }),
      resolveConflict: vi.fn(), transitionTask: vi.fn(), addTaskComment: vi.fn(), addTaskDelay: vi.fn(),
      createApprovalRequest: vi.fn(), listApprovalRequests: vi.fn(), approveApproval: vi.fn(), rejectApproval: vi.fn(), cancelApproval: vi.fn(), deleteTaskComment: vi.fn(),
    };
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory: () => 'request-1' });
    await controller.loadSnapshot();

    const result = await controller.patchTask(task.id, { title: 'Pending title' });

    expect(result).toMatchObject({ pending: true, approval_request: { id: approval.id } });
    expect(controller.state.snapshot?.tasks[0]).toEqual(task);
    expect(controller.state.approvals).toEqual([approval]);
    expect(controller.state.cursor).toBe(6);
  });

  it('renders incoming and outgoing boxes and delegates approval actions', () => {
    const listeners = new Set<(state: WorkspaceSyncState) => void>();
    const state: WorkspaceSyncState = {
      snapshot: { ...snapshot(), approval_requests: [approval] }, cursor: 5, loading: false, stale: false,
      error: null, conflicts: [], authRequired: false,
    };
    const sync = {
      state,
      subscribe: (listener: (next: WorkspaceSyncState) => void) => { listeners.add(listener); return () => listeners.delete(listener); },
      approveApproval: vi.fn(async () => undefined), rejectApproval: vi.fn(async () => undefined), cancelApproval: vi.fn(async () => undefined),
    };
    const root = document.createElement('div');
    const cleanup = ApprovalView.mount(root, sync as never, 'user-1');

    expect(root.textContent).toContain('待我审批');
    expect(root.textContent).toContain('我发起的请求');
    root.querySelector<HTMLButtonElement>('button[data-action="approve"]')?.click();
    expect(sync.approveApproval).toHaveBeenCalledWith('approval-1');
    expect(root.querySelector<HTMLButtonElement>('button[data-action="cancel"]')).toBeNull();
    listeners.forEach((listener) => listener({ ...state, approvals: [approval], snapshot: { ...state.snapshot!, approval_requests: [approval] } }));
    cleanup();
    expect(root.childElementCount).toBe(0);
  });
});
