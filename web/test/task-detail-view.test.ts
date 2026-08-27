import { describe, expect, it, vi } from 'vitest';
import type { TaskItem } from '../src/api/types';
import { TaskDetailView } from '../src/ui/task-detail-view';

const task: TaskItem = { id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, title: 'Original', description: 'Details', due_at: null, status: 'TODO', current_handler_id: 'user-1', blocked_reason: null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'user-1', created_at: '2026-08-26T00:00:00Z', updated_at: '2026-08-26T00:00:00Z', assignee_ids: ['user-1'], delay_count: 0, total_delay_minutes: 0, version: 3, status_version: 2, field_versions: { title: 3, description: 2 }, lifecycle_version: 1, deleted_at: null };

describe('TaskDetailView', () => {
  it('saves edited fields and exposes status, comment, delay and conflict actions', async () => {
    const root = document.createElement('div');
    const actions = { onTransition: vi.fn(async () => undefined), onComment: vi.fn(async () => undefined), onDelay: vi.fn(async () => undefined), onSave: vi.fn(async () => undefined), conflicts: [{ id: 'conflict-1', task_id: task.id, field: 'title', current: 'Server', proposed: 'Local' }] };
    const cleanup = TaskDetailView.mount(root, task, [], actions);
    const title = root.querySelector<HTMLInputElement>('input[aria-label="标题"]')!;
    title.value = 'Updated';
    root.querySelector<HTMLButtonElement>('button[data-action="save"]')!.click();
    await Promise.resolve();
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
});

async function settle(): Promise<void> { await Promise.resolve(); await Promise.resolve(); }
