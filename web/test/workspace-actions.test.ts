import { describe, expect, it, vi } from 'vitest';
import { ApiClient, ApiError } from '../src/api/client';
import { WorkspaceView } from '../src/ui/workspace-view';
import type { WorkspaceSnapshot, TaskItem } from '../src/api/types';
import type { WorkspaceSyncState } from '../src/sync/workspace-sync';

describe('workspace actions', () => {
  it('uses snake_case transition body and preserves errors', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new ApiError(409, 'field_conflict', 'conflict'));
    await expect(new ApiClient().transitionTask('task-1', { requestId: 'r1', targetStatus: 'DONE', baseStatusVersion: 3 })).rejects.toMatchObject({ status: 409 });
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/tasks/task-1/transition', expect.objectContaining({ body: JSON.stringify({ request_id: 'r1', target_status: 'DONE', base_status_version: 3, blocked_reason: undefined, resume_handler_id: undefined, waiting_for_user_id: undefined }) }));
  });

  it('creates a task from the workspace form and clears the draft after the ACK', async () => {
    const task = makeTask('task-1', 'Draft task');
    const sync = fakeSync({ tasks: [], cursor: 1 });
    sync.createTask.mockImplementation(async (title: string, description: string) => {
      expect(title).toBe('Draft task');
      expect(description).toBe('Details');
      sync.state = { ...sync.state, snapshot: { ...sync.state.snapshot!, tasks: [task], cursor: 2 } };
    });
    const root = document.createElement('div');
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn());
    const title = root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')!;
    const description = root.querySelector<HTMLInputElement>('input[placeholder="任务描述"]')!;
    title.value = ' Draft task ';
    description.value = 'Details';
    title.dispatchEvent(new Event('input', { bubbles: true }));
    description.dispatchEvent(new Event('input', { bubbles: true }));
    root.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(sync.createTask).toHaveBeenCalledWith('Draft task', 'Details');
    expect(root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')?.value).toBe('');
    cleanup();
  });

  it('retains the draft when creation fails', async () => {
    const sync = fakeSync({ tasks: [], cursor: 1 });
    sync.createTask.mockRejectedValue(new Error('network'));
    const root = document.createElement('div');
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn());
    const title = root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')!;
    title.value = 'Keep me';
    title.dispatchEvent(new Event('input', { bubbles: true }));
    root.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await Promise.resolve();
    expect(title.value).toBe('Keep me');
    cleanup();
  });

  it('retains the draft when the sync controller reports a handled error', async () => {
    const sync = fakeSync({ tasks: [], cursor: 1 });
    sync.createTask.mockImplementation(async () => { sync.state = { ...sync.state, error: '无法创建任务' }; });
    const root = document.createElement('div');
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn());
    const title = root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')!;
    title.value = 'Keep handled error';
    title.dispatchEvent(new Event('input', { bubbles: true }));
    root.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await Promise.resolve();
    expect(title.value).toBe('Keep handled error');
    cleanup();
  });

  it('keeps create disabled while a sync loading rerender is in flight', async () => {
    const sync = fakeSync({ tasks: [], cursor: 1 });
    let resolveCreate!: () => void;
    sync.createTask.mockReturnValue(new Promise<void>((resolve) => { resolveCreate = resolve; }));
    const root = document.createElement('div');
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn());
    const title = root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')!;
    title.value = 'In flight'; title.dispatchEvent(new Event('input', { bubbles: true }));
    root.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    sync.state = { ...sync.state, loading: true };
    sync.emit();
    expect(root.querySelector<HTMLButtonElement>('form button')?.disabled).toBe(true);
    resolveCreate();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')?.value).toBe('');
    cleanup();
  });
});

function makeTask(id: string, title: string): TaskItem {
  return { id, workspace_id: 'workspace-1', parent_task_id: null, title, description: '', due_at: null, status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'user-1', created_at: '2026-08-26T00:00:00Z', updated_at: '2026-08-26T00:00:00Z', assignee_ids: ['user-1'], delay_count: 0, total_delay_minutes: 0, version: 1, status_version: 1, field_versions: { title: 1, description: 1 }, lifecycle_version: 1, deleted_at: null };
}

function fakeSync(input: { tasks: TaskItem[]; cursor: number }) {
  const state = { snapshot: { workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' }, members: [{ user_id: 'user-1', member_slot: 1 }], tasks: input.tasks, conflicts: [], cursor: input.cursor }, cursor: input.cursor, loading: false, stale: false, error: null as string | null, conflicts: [], authRequired: false };
  const listeners = new Set<(state: WorkspaceSyncState) => void>();
  const sync = { state: state as WorkspaceSyncState, subscribe: vi.fn((listener: (state: WorkspaceSyncState) => void) => { listeners.add(listener); return () => listeners.delete(listener); }), emit: () => listeners.forEach((listener) => listener(sync.state)), refresh: vi.fn(), createTask: vi.fn(), transitionTask: vi.fn(), addComment: vi.fn(), addDelay: vi.fn(), patchTask: vi.fn(), resolveConflict: vi.fn() };
  return sync;
}
