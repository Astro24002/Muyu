import { describe, expect, it, vi } from 'vitest';
import type { TaskItem } from '../src/api/types';
import { TaskDetailView } from '../src/ui/task-detail-view';
import { WorkspaceView } from '../src/ui/workspace-view';
import type { WorkspaceSyncState } from '../src/sync/workspace-sync';

const task: TaskItem = { id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, title: 'Original', description: 'Details', due_at: null, status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'user-1', created_at: '2026-08-26T00:00:00Z', updated_at: '2026-08-26T00:00:00Z', delay_count: 0, total_delay_minutes: 0, version: 3, status_version: 2, field_versions: { title: 3, description: 2, quadrant: 1, labels: 1 }, lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: ['工作', '婚礼'] };

describe('TaskDetailView', () => {
  it('saves edited fields and exposes status, comment, delay and conflict actions', async () => {
    const root = document.createElement('div');
    const actions = { onTransition: vi.fn(async () => undefined), onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave: vi.fn(async () => undefined), conflicts: [{ id: 'conflict-1', task_id: task.id, field: 'title', current: 'Server', proposed: 'Local' }] };
    const cleanup = TaskDetailView.mount(root, task, [], actions);
    const title = root.querySelector<HTMLInputElement>('input[aria-label="标题"]')!;
    title.value = 'Updated';
    root.querySelector<HTMLButtonElement>('button[data-action="save"]')!.click();
    await settle();
    expect(actions.onSave).toHaveBeenCalledWith({ title: 'Updated', description: 'Details' });
    root.querySelector<HTMLSelectElement>('select[aria-label="状态"]')!.value = 'IN_PROGRESS';
    root.querySelector<HTMLButtonElement>('button[data-action="transition"]')!.click();
    await settle();
    root.querySelector<HTMLInputElement>('input[aria-label="评论"]')!.value = 'A note';
    root.querySelector<HTMLButtonElement>('button[data-action="comment"]')!.click();
    await settle();
    root.querySelector<HTMLInputElement>('input[aria-label="延期至 (ISO 时间)"]')!.value = '2026-08-27T12:00';
    root.querySelector<HTMLButtonElement>('button[data-action="delay"]')!.click();
    await settle();
    root.querySelector<HTMLButtonElement>('button[data-action="resolve-current"]')!.click();
    expect(actions.onTransition).toHaveBeenCalledWith('IN_PROGRESS');
    expect(actions.onComment).toHaveBeenCalled();
    expect(actions.onDelay).toHaveBeenCalled();
    expect(root.textContent).toContain('Server');
    cleanup();
  });

  it('keeps the open detail draft while workspace state is reconciled', () => {
    const root = document.createElement('div');
    const listeners = new Set<(state: WorkspaceSyncState) => void>();
    const sync: {
      state: WorkspaceSyncState;
      subscribe: (listener: (state: WorkspaceSyncState) => void) => () => boolean;
      refresh: ReturnType<typeof vi.fn>;
      createTask: ReturnType<typeof vi.fn>;
      transitionTask: ReturnType<typeof vi.fn>;
      addComment: ReturnType<typeof vi.fn>;
      addDelay: ReturnType<typeof vi.fn>;
      patchTask: ReturnType<typeof vi.fn>;
      resolveConflict: ReturnType<typeof vi.fn>;
    } = {
      state: { snapshot: { workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' }, members: [{ user_id: 'user-1', member_slot: 1 }], tasks: [task], conflicts: [], cursor: 2 }, cursor: 2, loading: false, stale: false, error: null as string | null, conflicts: [], authRequired: false },
      subscribe: (listener: (state: WorkspaceSyncState) => void) => { listeners.add(listener); return () => listeners.delete(listener); },
      refresh: vi.fn(), createTask: vi.fn(async () => undefined), transitionTask: vi.fn(async () => undefined), addComment: vi.fn(async () => undefined), addDelay: vi.fn(async () => undefined), patchTask: vi.fn(async () => undefined), resolveConflict: vi.fn(async () => undefined),
    };
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn());
    expect(root.querySelector('.task-row')?.textContent).toContain('工作');
    expect(root.querySelector('.task-row')?.textContent).toContain('婚礼');
    root.querySelector<HTMLElement>('.task-row')!.click();
    const title = root.querySelector<HTMLInputElement>('input[aria-label="标题"]')!;
    title.value = 'Local draft';
    title.dispatchEvent(new Event('input', { bubbles: true }));
    sync.state = { ...sync.state, loading: true, snapshot: { ...sync.state.snapshot!, tasks: [{ ...task, title: 'Server update' }] } };
    listeners.forEach((listener) => listener(sync.state));
    expect(root.querySelector<HTMLInputElement>('input[aria-label="标题"]')?.value).toBe('Local draft');
    sync.state = { ...sync.state, loading: false, conflicts: [{ id: 'conflict-1', task_id: task.id, field: 'title', current: 'Server update', proposed: 'Local draft' }], error: null };
    listeners.forEach((listener) => listener(sync.state));
    expect(root.querySelector('.conflict-panel')?.textContent).toContain('Server update');
    sync.state = { ...sync.state, conflicts: [], snapshot: { ...sync.state.snapshot!, tasks: [{ ...task, title: 'Server update', status: 'IN_PROGRESS' }] } };
    listeners.forEach((listener) => listener(sync.state));
    expect(root.querySelector('.conflict-panel')).toBeNull();
    expect(root.querySelector<HTMLSelectElement>('select[aria-label="状态"]')?.value).toBe('IN_PROGRESS');
    cleanup();
  });

  it('requires and sends a resume handler when entering waiting', async () => {
    const root = document.createElement('div');
    const onTransition = vi.fn(async () => undefined);
    const actions = { onTransition, onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave: vi.fn(async () => undefined) };
    const cleanup = TaskDetailView.mount(root, task, [{ user_id: 'user-1', member_slot: 1 }, { user_id: 'user-2', member_slot: 2 }], actions);
    root.querySelector<HTMLSelectElement>('select[aria-label="状态"]')!.value = 'WAITING';
    root.querySelector<HTMLInputElement>('input[aria-label="阻塞原因"]')!.value = '需要确认';
    root.querySelector<HTMLSelectElement>('select[aria-label="恢复负责人"]')!.value = 'user-2';
    root.querySelector<HTMLButtonElement>('button[data-action="transition"]')!.click();
    await settle();
    expect(onTransition).toHaveBeenCalledWith('WAITING', { blockedReason: '需要确认', resumeHandlerId: 'user-2' });
    cleanup();
  });

  it('populates resume-handler options from active Workspace members and keeps the current handler available', () => {
    const root = document.createElement('div');
    const currentTask = { ...task, current_handler_id: 'user-2' };
    const actions = { onTransition: vi.fn(async () => undefined), onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave: vi.fn(async () => undefined) };
    const cleanup = TaskDetailView.mount(root, currentTask, [{ user_id: 'user-1', member_slot: 1 }, { user_id: 'user-2', member_slot: 2 }], actions);

    expect(Array.from(root.querySelectorAll<HTMLSelectElement>('select[aria-label="恢复负责人"] option')).map((option) => option.value)).toEqual(['user-1', 'user-2']);
    expect(root.querySelector<HTMLSelectElement>('select[aria-label="恢复负责人"]')?.value).toBe('user-2');
    cleanup();
  });

  it('renders labels and submits the complete label array with a required quadrant', async () => {
    const root = document.createElement('div');
    const onSave = vi.fn(async () => undefined);
    const actions = { onTransition: vi.fn(async () => undefined), onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave };
    const cleanup = TaskDetailView.mount(root, task, [], actions);

    expect(root.textContent).toContain('工作');
    expect(root.textContent).toContain('婚礼');
    expect(Array.from(root.querySelectorAll<HTMLSelectElement>('select[aria-label="四象限"] option')).map((option) => option.value)).toEqual(['Q1', 'Q2', 'Q3', 'Q4']);

    const labels = root.querySelector<HTMLInputElement>('input[aria-label="标签"]')!;
    labels.value = '工作, 婚礼, 党员';
    labels.dispatchEvent(new Event('input', { bubbles: true }));
    root.querySelector<HTMLSelectElement>('select[aria-label="四象限"]')!.value = 'Q1';
    root.querySelector<HTMLButtonElement>('button[data-action="save"]')!.click();
    await settle();

    expect(onSave).toHaveBeenCalledWith({ title: 'Original', description: 'Details', quadrant: 'Q1', labels: ['工作', '婚礼', '党员'] });
    cleanup();
  });

  it('rejects a missing quadrant before invoking the save callback', async () => {
    const root = document.createElement('div');
    const onSave = vi.fn(async () => undefined);
    const actions = { onTransition: vi.fn(async () => undefined), onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave };
    const invalidTask = { ...task, quadrant: null } as unknown as TaskItem;
    const cleanup = TaskDetailView.mount(root, invalidTask, [], actions);

    root.querySelector<HTMLButtonElement>('button[data-action="save"]')!.click();
    await settle();

    expect(onSave).not.toHaveBeenCalled();
    expect(root.querySelector('.sync-error')?.textContent).toContain('四象限');
    cleanup();
  });
});

async function settle(): Promise<void> { await Promise.resolve(); await Promise.resolve(); }
