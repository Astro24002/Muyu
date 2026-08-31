import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import type { TaskApprovalRequest, TaskComment } from '../src/api/types';
import { WorkspaceSyncController } from '../src/sync/workspace-sync';

const task = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, title: 'Original', description: 'Description',
  status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null,
  waiting_for_user_id: null, planned_start_at: null, due_at: null, estimated_minutes: null, completed_at: null,
  created_by: 'user-1', version: 3, status_version: 1, created_at: '2026-08-25T00:00:00.000Z', updated_at: '2026-08-25T00:00:00.000Z',
  assignee_ids: ['user-1'], delay_count: 0, total_delay_minutes: 0, field_versions: { title: 3, description: 1 },
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: [],
};

function snapshot(cursor = 5) {
  return { workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' }, members: [], tasks: [task], conflicts: [], cursor };
}

function apiStub() {
  return {
    getWorkspaceSnapshot: vi.fn().mockResolvedValue(snapshot()),
    getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-1', cursor: 5, changes: [] }),
    createTask: vi.fn(),
    patchTask: vi.fn(),
    resolveConflict: vi.fn(),
    addTaskComment: vi.fn(),
  };
}

describe('WorkspaceSyncController', () => {
  it('records the snapshot cursor and applies contiguous task changes', async () => {
    const api = apiStub();
    api.getWorkspaceChanges.mockResolvedValue({ workspace_id: 'workspace-1', cursor: 6, changes: [{ cursor: 6, resource_type: 'task', resource_id: task.id, action: 'UPDATED', operation_id: 'op-1', resource: { ...task, title: 'Updated' } }] });
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    await controller.pull();

    expect(controller.state.cursor).toBe(6);
    expect(controller.state.snapshot?.cursor).toBe(6);
    expect(controller.state.snapshot?.tasks[0]?.title).toBe('Updated');
    expect(api.getWorkspaceChanges).toHaveBeenCalledWith(5);
  });

  it('reloads the snapshot when the server expires the cursor', async () => {
    const api = apiStub();
    api.getWorkspaceChanges.mockRejectedValue(new ApiError(410, 'sync_cursor_expired', 'expired'));
    api.getWorkspaceSnapshot.mockResolvedValueOnce(snapshot(5)).mockResolvedValueOnce(snapshot(11));
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    await controller.pull();

    expect(api.getWorkspaceSnapshot).toHaveBeenCalledTimes(2);
    expect(controller.state.cursor).toBe(11);
  });

  it('reloads the snapshot instead of applying a non-contiguous change', async () => {
    const api = apiStub();
    api.getWorkspaceChanges.mockResolvedValue({ workspace_id: 'workspace-1', cursor: 7, changes: [{ cursor: 7, resource_type: 'task', resource_id: task.id, action: 'UPDATED', operation_id: 'op-2', resource: { ...task, title: 'Skipped' } }] });
    api.getWorkspaceSnapshot.mockResolvedValueOnce(snapshot(5)).mockResolvedValueOnce(snapshot(7));
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    await controller.pull();

    expect(api.getWorkspaceSnapshot).toHaveBeenCalledTimes(2);
    expect(controller.state.snapshot?.tasks[0]?.title).toBe('Original');
  });

  it('uses generated UUID request ids for online writes and stores the returned task', async () => {
    const api = apiStub();
    api.createTask.mockResolvedValue({ ...task, id: 'task-2', title: 'New task', cursor: 6 });
    const requestIdFactory = vi.fn(() => '00000000-0000-4000-8000-000000000001');
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory });
    await controller.loadSnapshot();

    await controller.createTask('New task', 'New description', 'Q2', ['工作']);

    expect(requestIdFactory).toHaveBeenCalledOnce();
    expect(api.createTask).toHaveBeenCalledWith({ requestId: '00000000-0000-4000-8000-000000000001', title: 'New task', description: 'New description', quadrant: 'Q2', labels: ['工作'] });
    expect(controller.state.snapshot?.tasks).toContainEqual(expect.objectContaining({ id: 'task-2', title: 'New task' }));
    expect(controller.state.cursor).toBe(6);
    expect(api.getWorkspaceChanges).toHaveBeenCalledWith(5);
  });

  it('sends the current base field versions when patching a task', async () => {
    const api = apiStub();
    api.patchTask.mockResolvedValue({ ...task, title: 'Modified', cursor: 6, field_versions: { ...task.field_versions, title: 4 } });
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory: () => '00000000-0000-4000-8000-000000000002' });
    await controller.loadSnapshot();

    await controller.patchTask(task.id, { title: 'Modified' });

    expect(api.patchTask).toHaveBeenCalledWith(task.id, {
      requestId: '00000000-0000-4000-8000-000000000002',
      changes: { title: 'Modified' },
      baseFieldVersions: { title: 3 },
    });
  });

  it('reconciles the cursor after a comment ACK', async () => {
    const api = apiStub();
    api.addTaskComment = vi.fn().mockResolvedValue({ id: 'comment-1', cursor: 6 });
    api.getWorkspaceChanges.mockResolvedValue({ workspace_id: 'workspace-1', cursor: 6, changes: [{ cursor: 6, resource_type: 'comment', resource_id: 'comment-1', action: 'CREATED', operation_id: null, resource: null }] });
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory: () => '00000000-0000-4000-8000-000000000004' });
    await controller.loadSnapshot();
    await controller.addComment(task.id, 'A note');
    expect(api.getWorkspaceChanges).toHaveBeenCalledWith(5);
    expect(controller.state.cursor).toBe(6);
  });

  it('keeps a field conflict visible after a 409 response', async () => {
    const api = apiStub();
    api.patchTask.mockRejectedValue(new ApiError(409, 'field_conflict', 'changed', { conflicts: [{ id: 'conflict-1', task_id: task.id, field: 'title', base: 'Original', current: 'Current', proposed: 'Modified' }] }));
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory: () => '00000000-0000-4000-8000-000000000002' });
    await controller.loadSnapshot();

    await controller.patchTask(task.id, { title: 'Modified' });

    expect(controller.state.conflicts).toContainEqual(expect.objectContaining({ id: 'conflict-1', current: 'Current', proposed: 'Modified' }));
    expect(controller.state.snapshot?.tasks[0]?.title).toBe('Original');
  });

  it('removes a successfully resolved conflict from controller state', async () => {
    const api = apiStub();
    api.getWorkspaceSnapshot.mockResolvedValue({
      ...snapshot(),
      conflicts: [{ id: 'conflict-1', task_id: task.id, field: 'title', base: 'Original', current: 'Current', proposed: 'Modified' }],
    });
    api.resolveConflict.mockResolvedValue({ ...task, title: 'Current', cursor: 6 });
    const controller = new WorkspaceSyncController(api as never, { requestIdFactory: () => '00000000-0000-4000-8000-000000000003' });
    await controller.loadSnapshot();

    await controller.resolveConflict(task.id, 'conflict-1', 'current');

    expect(controller.state.conflicts).toEqual([]);
  });

  it('marks existing data stale when a network request fails and never queues the write', async () => {
    const api = apiStub();
    api.createTask.mockRejectedValue(new TypeError('Network unavailable'));
    const controller = new WorkspaceSyncController(api as never);
    await controller.loadSnapshot();

    await controller.createTask('Offline', '', 'Q1');

    expect(controller.state).toMatchObject({ stale: true, loading: false });
    expect(controller.state.snapshot?.tasks).toHaveLength(1);
    expect(api.createTask).toHaveBeenCalledOnce();
  });

  it('clears session-bound workspace data before a new login', async () => {
    const api = apiStub();
    const controller = new WorkspaceSyncController(api as never);
    await controller.loadSnapshot();

    controller.clear();

    expect(controller.state).toEqual({
      snapshot: null,
      cursor: 0,
      loading: false,
      stale: false,
      error: null,
      conflicts: [],
      authRequired: false,
    });
  });

  it('ignores late old-session approval and comment responses after clear loads a new snapshot', async () => {
    const oldApproval = approval('approval-old', 'workspace-1');
    const oldComment = comment('comment-old', 'task-1');
    const oldCreate = deferred<typeof oldApproval & { cursor: number }>();
    const oldList = deferred<typeof oldApproval[]>();
    const oldAddComment = deferred<typeof oldComment & { cursor: number }>();
    const oldDelay = deferred<Record<string, unknown>>();
    const oldDelete = deferred<typeof oldComment & { cursor: number }>();
    const oldApprove = deferred<{ approval_request: typeof oldApproval; task: typeof task; cursor: number }>();
    const oldReject = deferred<{ approval_request: typeof oldApproval; comment: typeof oldComment; cursor: number }>();
    const oldCancel = deferred<{ approval_request: typeof oldApproval; cursor: number }>();
    const newSnapshot = {
      ...snapshot(12),
      workspace_id: 'workspace-new',
      workspace: { id: 'workspace-new', name: 'New workspace', status: 'ACTIVE' },
      tasks: [{ ...task, id: 'task-new', workspace_id: 'workspace-new', title: 'New task' }],
      comments: [],
      approval_requests: [],
    };
    const api = {
      ...apiStub(),
      getWorkspaceSnapshot: vi.fn().mockResolvedValueOnce(snapshot()).mockResolvedValueOnce(newSnapshot),
      createApprovalRequest: vi.fn(() => oldCreate.promise),
      listApprovalRequests: vi.fn(() => oldList.promise),
      addTaskComment: vi.fn(() => oldAddComment.promise),
      addTaskDelay: vi.fn(() => oldDelay.promise),
      deleteTaskComment: vi.fn(() => oldDelete.promise),
      approveApproval: vi.fn(() => oldApprove.promise),
      rejectApproval: vi.fn(() => oldReject.promise),
      cancelApproval: vi.fn(() => oldCancel.promise),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    const oldOperations = [
      controller.createApprovalRequest('task-1', {
        requestType: 'TASK_UPDATE', proposedChanges: { title: 'Old' }, baseFieldVersions: { title: 3 },
      }),
      controller.listApprovalRequests(),
      controller.addComment('task-1', 'old comment'),
      controller.addDelay('task-1', '2026-09-01T00:00:00.000Z', 'old reason'),
      controller.deleteTaskComment('task-1', 'comment-old', 1),
      controller.approveApproval('approval-old'),
      controller.rejectApproval('approval-old', 'old rejection'),
      controller.cancelApproval('approval-old'),
    ];

    controller.clear();
    await controller.loadSnapshot();
    const expectedState = controller.state;

    oldCreate.resolve({ ...oldApproval, cursor: 13 });
    oldList.resolve([oldApproval]);
    oldAddComment.resolve({ ...oldComment, cursor: 14 });
    oldDelay.resolve({ id: 'delay-old' });
    oldDelete.resolve({ ...oldComment, deleted_at: '2026-08-31T00:00:00.000Z', cursor: 15 });
    oldApprove.resolve({ approval_request: { ...oldApproval, status: 'APPROVED' }, task: { ...task, title: 'Old approval task' }, cursor: 16 });
    oldReject.resolve({ approval_request: { ...oldApproval, status: 'REJECTED' }, comment: { ...oldComment, body: 'Old approval comment' }, cursor: 17 });
    oldCancel.resolve({ approval_request: { ...oldApproval, status: 'CANCELLED' }, cursor: 18 });
    await Promise.all(oldOperations);

    expect(controller.state).toEqual(expectedState);
    expect(api.getWorkspaceChanges).not.toHaveBeenCalled();
  });

  it('does not publish a late old-session error or loading state after clear loads a new snapshot', async () => {
    const oldError = deferred<never>();
    const newSnapshot = { ...snapshot(12), workspace_id: 'workspace-new', workspace: { id: 'workspace-new', name: 'New workspace', status: 'ACTIVE' } };
    const api = {
      ...apiStub(),
      getWorkspaceSnapshot: vi.fn().mockResolvedValueOnce(snapshot()).mockResolvedValueOnce(newSnapshot),
      addTaskComment: vi.fn(() => oldError.promise),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    const oldOperation = controller.addComment('task-1', 'old comment');
    controller.clear();
    await controller.loadSnapshot();
    const expectedState = controller.state;

    oldError.reject(new TypeError('old session failed'));
    await oldOperation;

    expect(controller.state).toEqual(expectedState);
  });

  it('serializes overlapping pulls and starts queued hints from the newest applied cursor', async () => {
    const first = deferred<ReturnType<typeof changesResponse>>();
    const second = deferred<ReturnType<typeof changesResponse>>();
    const api = apiStub();
    api.getWorkspaceChanges.mockImplementation((afterCursor: number) => {
      if (afterCursor === 5) return first.promise;
      if (afterCursor === 6) return second.promise;
      return Promise.resolve(changesResponse(afterCursor));
    });
    const controller = new WorkspaceSyncController(api as never);
    await controller.loadSnapshot();

    const firstPull = controller.pull(6);
    const queuedPull = controller.pull(7);
    expect(api.getWorkspaceChanges).toHaveBeenCalledTimes(1);
    expect(api.getWorkspaceChanges).toHaveBeenCalledWith(5);

    first.resolve(changesResponse(6, { ...task, title: 'Older change' }));
    await vi.waitFor(() => {
      expect(api.getWorkspaceChanges).toHaveBeenCalledTimes(2);
      expect(api.getWorkspaceChanges).toHaveBeenLastCalledWith(6);
    });

    second.resolve(changesResponse(7, { ...task, title: 'Fresh change' }));
    await Promise.all([firstPull, queuedPull]);

    expect(controller.state.cursor).toBe(7);
    expect(controller.state.snapshot?.tasks[0]?.title).toBe('Fresh change');
  });

  it('coalesces duplicate realtime hints while a pull is in flight', async () => {
    const pending = deferred<ReturnType<typeof changesResponse>>();
    const api = apiStub();
    api.getWorkspaceChanges.mockReturnValue(pending.promise);
    const controller = new WorkspaceSyncController(api as never);
    await controller.loadSnapshot();

    const firstPull = controller.pull(6);
    const duplicatePull = controller.pull(6);
    expect(api.getWorkspaceChanges).toHaveBeenCalledTimes(1);

    pending.resolve(changesResponse(6, { ...task, title: 'Applied once' }));
    await Promise.all([firstPull, duplicatePull]);

    expect(api.getWorkspaceChanges).toHaveBeenCalledOnce();
    expect(controller.state.snapshot?.tasks[0]?.title).toBe('Applied once');
  });
});

function changesResponse(cursor: number, nextTask = task) {
  return {
    workspace_id: 'workspace-1',
    cursor,
    changes: cursor === 5 ? [] : [{
      cursor,
      resource_type: 'task' as const,
      resource_id: nextTask.id,
      action: 'UPDATED',
      operation_id: null,
      resource: nextTask,
    }],
  };
}

function approval(id: string, workspaceId: string, status: TaskApprovalRequest['status'] = 'PENDING'): TaskApprovalRequest {
  return {
    id,
    workspace_id: workspaceId,
    task_id: workspaceId === 'workspace-1' ? 'task-1' : 'task-new',
    comment_id: null,
    requester_id: 'user-1',
    approver_id: 'user-2',
    request_type: 'TASK_UPDATE' as const,
    proposed_changes: { title: 'Old title' },
    base_field_versions: { title: 3 },
    request_id: `${id}-request`,
    status,
    created_at: '2026-08-31T00:00:00.000Z',
    reviewed_at: null,
    reviewed_by: null,
    rejection_reason: null,
    resolved_cursor: null,
  };
}

function comment(id: string, taskId: string): TaskComment {
  return {
    id,
    task_id: taskId,
    author_user_id: 'user-1',
    body: 'Old comment',
    version: 1,
    deleted_at: null,
    deleted_by: null,
    created_at: '2026-08-31T00:00:00.000Z',
  };
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (error: unknown) => void;
} {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, resolve, reject };
}
