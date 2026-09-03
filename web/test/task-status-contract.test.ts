import { describe, expect, it } from 'vitest';
import type { TaskItem, TaskStatus } from '../src/api/types';
import { statusLabel } from '../src/tasks/task-status';
import { parseTaskItem } from '../src/tasks/task-model';
import { TASK_STATUSES } from '../src/tasks/task-view-model';

const displayStatusLabel = (status: string): string => statusLabel(status as TaskStatus);

const task = (status: string): Record<string, unknown> => ({
  id: 'task-contract',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: 'Contract task',
  description: '',
  due_at: null,
  status,
  current_handler_id: 'user-1',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'user-1',
  created_at: '2026-09-02T00:00:00Z',
  updated_at: '2026-09-02T00:00:00Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q1',
  labels: [],
});

describe('six-state task status contract', () => {
  it('exposes exactly the six canonical internal statuses', () => {
    expect(TASK_STATUSES as readonly string[]).toEqual([
      'TODO',
      'IN_PROGRESS',
      'BLOCKED',
      'REVIEW',
      'DONE',
      'CANCELLED',
    ]);
  });

  it('maps every internal status to the approved Chinese label', () => {
    expect(displayStatusLabel('TODO')).toBe('待进行');
    expect(displayStatusLabel('IN_PROGRESS')).toBe('进行中');
    expect(displayStatusLabel('BLOCKED')).toBe('阻塞中');
    expect(displayStatusLabel('REVIEW')).toBe('待验收');
    expect(displayStatusLabel('DONE')).toBe('已完成');
    expect(displayStatusLabel('CANCELLED')).toBe('已取消');
  });

  it.each([
    ['WAITING', 'BLOCKED'],
    ['COMPLETED', 'DONE'],
  ])('normalizes legacy %s when reading a task snapshot', (legacyStatus, canonicalStatus) => {
    expect(parseTaskItem(task(legacyStatus) as TaskItem).status).toBe(canonicalStatus);
  });
});
