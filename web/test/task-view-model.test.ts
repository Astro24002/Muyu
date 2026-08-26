import { describe, expect, it } from 'vitest';
import { deriveTaskSummary, filterMyTasks, groupTasksByStatus } from '../src/tasks/task-view-model';
import type { TaskItem } from '../src/api/types';

const task = (id: string, status: TaskItem['status'], due_at: string | null, assignee_ids = ['u1'], current_handler_id = 'u2'): TaskItem => ({ id, workspace_id: 'w', parent_task_id: null, title: id, description: '', due_at, status, current_handler_id, blocked_reason: status === 'WAITING' ? '原因' : null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'u1', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z', assignee_ids, delay_count: 0, total_delay_minutes: 0, version: 1, status_version: 1, field_versions: {}, lifecycle_version: 1, deleted_at: null });

describe('task projections', () => {
  it('keeps all five status groups and filters handler or assignee matches', () => {
    const tasks = [task('todo', 'TODO', null), task('waiting', 'WAITING', null, ['u2']), task('done', 'DONE', null)];
    expect(Object.keys(groupTasksByStatus(tasks))).toEqual(['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED']);
    expect(filterMyTasks(tasks, 'u1').map((item) => item.id)).toEqual(['todo', 'done']);
  });

  it('does not count completed tasks as overdue', () => {
    const now = new Date('2026-08-26T00:00:00Z');
    const tasks = [task('late', 'IN_PROGRESS', '2026-08-25T00:00:00Z'), task('done', 'DONE', '2026-08-25T00:00:00Z'), task('soon', 'TODO', '2026-08-26T12:00:00Z')];
    expect(deriveTaskSummary(tasks, now)).toMatchObject({ overdue: 1, dueSoon: 1 });
  });
});
