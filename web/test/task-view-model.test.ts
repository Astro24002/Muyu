import { describe, expect, it } from 'vitest';
import { deriveTaskSummary, filterMyTasks, groupTasksByStatus } from '../src/tasks/task-view-model';
import { parseTaskItem, parseTaskLabels } from '../src/tasks/task-model';
import type { TaskItem } from '../src/api/types';

const task = (id: string, status: TaskItem['status'], due_at: string | null, current_handler_id = 'u1'): TaskItem => ({ id, workspace_id: 'w', parent_task_id: null, title: id, description: '', due_at, status, current_handler_id, blocked_reason: status === 'WAITING' ? '原因' : null, blocked_since: null, resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: null, completed_at: null, created_by: 'u1', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z', delay_count: 0, total_delay_minutes: 0, version: 1, status_version: 1, field_versions: { quadrant: 1, labels: 1 }, lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: [] });

describe('task projections', () => {
  it('keeps all five status groups and filters by current handler', () => {
    const tasks = [task('todo', 'TODO', null), task('waiting', 'WAITING', null, 'u2'), task('done', 'DONE', null)];
    expect(Object.keys(groupTasksByStatus(tasks))).toEqual(['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED']);
    expect(filterMyTasks(tasks, 'u1').map((item) => item.id)).toEqual(['todo', 'done']);
  });

  it('excludes a task owned by the other member from my tasks', () => {
    const tasks = [task('mine', 'TODO', null, 'u1'), task('other', 'TODO', null, 'u2')];

    expect(filterMyTasks(tasks, 'u1').map((item) => item.id)).toEqual(['mine']);
  });

  it('does not count completed tasks as overdue', () => {
    const now = new Date('2026-08-26T00:00:00Z');
    const tasks = [task('late', 'IN_PROGRESS', '2026-08-25T00:00:00Z'), task('done', 'DONE', '2026-08-25T00:00:00Z'), task('soon', 'TODO', '2026-08-26T12:00:00Z')];
    expect(deriveTaskSummary(tasks, now)).toMatchObject({ overdue: 1, dueSoon: 1 });
  });

  it('parses string labels and rejects missing or null quadrants from the wire', () => {
    const raw = { ...task('wire', 'TODO', null), labels: [' 工作 ', '工作', '婚礼'], quadrant: 'Q1' };
    expect(parseTaskItem(raw)).toMatchObject({ quadrant: 'Q1', labels: ['工作', '婚礼'] });
    expect(parseTaskItem({ ...raw, labels: undefined })).toMatchObject({ labels: [] });
    expect(() => parseTaskItem({ ...raw, quadrant: undefined })).toThrow();
    expect(() => parseTaskItem({ ...raw, quadrant: null })).toThrow();
    expect(() => parseTaskItem({ ...raw, labels: null })).toThrow();
  });

  it('normalizes the legacy COMPLETED status at the wire boundary', () => {
    const parsed = parseTaskItem({ ...task('legacy', 'DONE', null), status: 'COMPLETED' });

    expect(parsed.status).toBe('DONE');
  });

  it('enforces the task label count, length, and aggregate limits', () => {
    expect(() => parseTaskLabels([''])).toThrow();
    expect(() => parseTaskLabels(['a'.repeat(33)])).toThrow();
    expect(parseTaskLabels(['😀'.repeat(32)])).toHaveLength(1);
    expect(() => parseTaskLabels(['😀'.repeat(33)])).toThrow();
    expect(() => parseTaskLabels(Array.from({ length: 11 }, (_, index) => `l${index}`))).toThrow();
    expect(() => parseTaskLabels(['a'.repeat(32), 'b'.repeat(32), 'c'.repeat(32), 'd'.repeat(32), 'e'.repeat(32), 'f'.repeat(32), 'g'.repeat(32), 'h'.repeat(32), 'i'.repeat(32), 'j'.repeat(32), 'k'])).toThrow();
  });
});
