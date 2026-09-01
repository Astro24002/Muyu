import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import { WorkspaceSyncController } from '../src/sync/workspace-sync';

const task = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, title: 'Original', description: 'Description',
  status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null,
  waiting_for_user_id: null, planned_start_at: null, due_at: null, estimated_minutes: null, completed_at: null,
  created_by: 'user-1', version: 3, status_version: 1, created_at: '2026-08-25T00:00:00.000Z', updated_at: '2026-08-25T00:00:00.000Z',
  delay_count: 0, total_delay_minutes: 0, field_versions: { title: 3, description: 1 },
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
});
