import { describe, expect, it, vi } from 'vitest';
import type { ActivityEvent, TaskItem } from '../src/api/types';
import { loadWorkspaceActivity } from '../src/tasks/activity-view-model';

const task = (id: string, deleted_at: string | null = null): TaskItem => ({
  id,
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: id,
  description: '',
  due_at: null,
  status: 'TODO',
  current_handler_id: 'viewer',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-01T00:00:00Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at,
  quadrant: 'Q2',
  labels: [],
});

const event = (id: string, created_at: string): ActivityEvent => ({
  kind: 'operation',
  id,
  created_at,
  operation_type: 'UPDATE',
  actor_user_id: 'viewer',
});

describe('loadWorkspaceActivity', () => {
  it('skips deleted tasks, merges newest first with an id tie-break, and caps at 50', async () => {
    const tasks = [task('task-1'), task('deleted', '2026-08-02T00:00:00Z'), task('task-2')];
    const bulk = Array.from({ length: 55 }, (_, index) => event(`bulk-${String(index).padStart(2, '0')}`, '2026-01-01T00:00:00Z'));
    const getTaskActivity = vi.fn(async (taskId: string): Promise<ActivityEvent[]> => taskId === 'task-1'
      ? [event('same-b', '2026-09-01T09:00:00Z'), event('same-a', '2026-09-01T09:00:00Z'), event('newest', '2026-09-02T09:00:00Z'), ...bulk]
      : [event('same-c', '2026-09-01T09:00:00Z')]);

    const result = await loadWorkspaceActivity(tasks, getTaskActivity);

    expect(getTaskActivity).toHaveBeenCalledTimes(2);
    expect(getTaskActivity).not.toHaveBeenCalledWith('deleted');
    expect(result.failedTaskIds).toEqual([]);
    expect(result.events).toHaveLength(50);
    expect(result.events.slice(0, 5).map((item) => item.id)).toEqual(['newest', 'same-c', 'same-b', 'same-a', 'bulk-54']);
  });

  it('keeps successful events and reports failed task ids', async () => {
    const getTaskActivity = vi.fn((taskId: string) => taskId === 'task-failed'
      ? Promise.reject(new Error('unavailable'))
      : Promise.resolve([event('successful-event', '2026-09-01T00:00:00Z')]));

    await expect(loadWorkspaceActivity([task('task-ok'), task('task-failed')], getTaskActivity)).resolves.toEqual({
      events: [event('successful-event', '2026-09-01T00:00:00Z')],
      failedTaskIds: ['task-failed'],
    });
  });

  it('does not request an empty task set', async () => {
    const getTaskActivity = vi.fn();

    await expect(loadWorkspaceActivity([], getTaskActivity)).resolves.toEqual({ events: [], failedTaskIds: [] });
    expect(getTaskActivity).not.toHaveBeenCalled();
  });

  it('runs no more than four task activity requests concurrently', async () => {
    const tasks = Array.from({ length: 10 }, (_, index) => task(`task-${index}`));
    const pending = new Map<string, () => void>();
    let active = 0;
    let maximum = 0;
    const getTaskActivity = vi.fn((taskId: string) => new Promise<ActivityEvent[]>((resolve) => {
      active += 1;
      maximum = Math.max(maximum, active);
      pending.set(taskId, () => {
        pending.delete(taskId);
        active -= 1;
        resolve([]);
      });
    }));

    const loading = loadWorkspaceActivity(tasks, getTaskActivity);
    await Promise.resolve();
    expect(getTaskActivity).toHaveBeenCalledTimes(4);
    expect(maximum).toBe(4);

    while (getTaskActivity.mock.calls.length < tasks.length) {
      for (const release of [...pending.values()]) release();
      await Promise.resolve();
      await Promise.resolve();
    }
    for (const release of [...pending.values()]) release();
    await loading;

    expect(maximum).toBe(4);
    expect(getTaskActivity).toHaveBeenCalledTimes(tasks.length);
  });
});
