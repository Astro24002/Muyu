import { describe, expect, it } from 'vitest';
import type { TaskApprovalRequest, TaskItem } from '../src/api/types';
import { deriveTodayModel } from '../src/tasks/task-view-model';

const makeTask = (overrides: Partial<TaskItem> = {}): TaskItem => ({
  id: 'task-1',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: '任务',
  description: '下一步',
  due_at: null,
  status: 'TODO',
  current_handler_id: 'partner',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-08-30T08:00:00Z',
  updated_at: '2026-08-30T08:00:00Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q2',
  labels: [],
  progress: null,
  ...overrides,
});

const makeApproval = (overrides: Partial<TaskApprovalRequest> = {}): TaskApprovalRequest => ({
  id: 'approval-1',
  workspace_id: 'workspace-1',
  task_id: 'task-1',
  comment_id: null,
  requester_id: 'partner',
  approver_id: 'viewer',
  request_type: 'TASK_UPDATE',
  proposed_changes: {},
  base_field_versions: {},
  request_id: 'request-1',
  status: 'PENDING',
  created_at: '2026-08-30T08:00:00Z',
  reviewed_at: null,
  reviewed_by: null,
  rejection_reason: null,
  resolved_cursor: null,
  ...overrides,
});

describe('deriveTodayModel', () => {
  const now = new Date('2026-08-31T12:00:00Z');

  it('ignores deleted tasks and selects the latest current-user in-progress task', () => {
    const tasks = [
      makeTask({ id: 'deleted-focus', status: 'IN_PROGRESS', current_handler_id: 'viewer', updated_at: '2026-08-31T11:59:00Z', deleted_at: '2026-08-31T12:00:00Z' }),
      makeTask({ id: 'focus-old', status: 'IN_PROGRESS', current_handler_id: 'viewer', updated_at: '2026-08-31T10:00:00Z' }),
      makeTask({ id: 'focus-new', status: 'IN_PROGRESS', current_handler_id: 'viewer', updated_at: '2026-08-31T11:00:00Z' }),
      makeTask({ id: 'focus-not-owned', status: 'IN_PROGRESS', current_handler_id: 'partner', updated_at: '2026-08-31T09:00:00Z' }),
      makeTask({ id: 'other-focus', status: 'IN_PROGRESS', current_handler_id: 'partner', updated_at: '2026-08-31T23:00:00Z' }),
    ];

    const model = deriveTodayModel(tasks, [], 'viewer', now);

    expect(model.focus?.id).toBe('focus-new');
    expect(model.next.map((task) => task.id)).toEqual(['focus-not-owned', 'focus-old', 'other-focus']);
    expect(model.next).not.toContain(tasks[0]);
  });

  it('uses the task id as a deterministic tie-breaker for focus', () => {
    const tasks = [
      makeTask({ id: 'focus-b', status: 'IN_PROGRESS', current_handler_id: 'viewer', updated_at: '2026-08-31T11:00:00Z' }),
      makeTask({ id: 'focus-a', status: 'IN_PROGRESS', current_handler_id: 'viewer', updated_at: '2026-08-31T11:00:00Z' }),
    ];

    expect(deriveTodayModel(tasks, [], 'viewer', now).focus?.id).toBe('focus-a');
  });

  it('sorts next by due date, puts undated tasks last, and caps the list at eight', () => {
    const tasks = [
      makeTask({ id: 'no-due', due_at: null }),
      makeTask({ id: 'due-later', due_at: '2026-09-05T09:00:00Z' }),
      makeTask({ id: 'waiting', status: 'WAITING', due_at: '2026-08-20T09:00:00Z' }),
      makeTask({ id: 'due-soon', due_at: '2026-09-01T09:00:00Z' }),
      makeTask({ id: 'done', status: 'DONE', due_at: '2026-08-01T09:00:00Z' }),
      makeTask({ id: 'cancelled', status: 'CANCELLED', due_at: '2026-08-02T09:00:00Z' }),
      makeTask({ id: 'overdue', due_at: '2026-08-01T09:00:00Z' }),
      ...Array.from({ length: 8 }, (_, index) => makeTask({ id: `extra-${index}`, due_at: `2026-09-${String(index + 2).padStart(2, '0')}T09:00:00Z` })),
    ];

    const model = deriveTodayModel(tasks, [], 'viewer', now);

    expect(model.next.map((task) => task.id)).toEqual([
      'overdue',
      'due-soon',
      'extra-0',
      'extra-1',
      'extra-2',
      'due-later',
      'extra-3',
      'extra-4',
    ]);
    expect(model.next).not.toContainEqual(expect.objectContaining({ id: 'waiting' }));
    expect(model.next).not.toContainEqual(expect.objectContaining({ id: 'done' }));
    expect(model.next).not.toContainEqual(expect.objectContaining({ id: 'cancelled' }));
  });

  it('returns waiting tasks and only pending approvals addressed to the viewer', () => {
    const waiting = makeTask({ id: 'waiting', status: 'WAITING' });
    const tasks = [waiting, makeTask({ id: 'todo' })];
    const approvals = [
      makeApproval({ id: 'incoming-pending' }),
      makeApproval({ id: 'outgoing-pending', requester_id: 'viewer', approver_id: 'partner' }),
      makeApproval({ id: 'other-incoming', approver_id: 'other-user' }),
      makeApproval({ id: 'already-approved', status: 'APPROVED' }),
    ];

    const model = deriveTodayModel(tasks, approvals, 'viewer', now);

    expect(model.waiting).toEqual([waiting]);
    expect(model.pendingApprovals.map((approval) => approval.id)).toEqual(['incoming-pending']);
  });

  it('returns a null focus when the viewer has no active in-progress task', () => {
    const tasks = [
      makeTask({ id: 'partner-progress', status: 'IN_PROGRESS', current_handler_id: 'partner' }),
      makeTask({ id: 'finished', status: 'DONE', current_handler_id: 'viewer' }),
    ];

    expect(deriveTodayModel(tasks, [], 'viewer', now).focus).toBeNull();
  });

  it('does not mutate task or approval inputs', () => {
    const tasks = [
      makeTask({ id: 'b', due_at: '2026-09-02T00:00:00Z' }),
      makeTask({ id: 'a', due_at: '2026-09-01T00:00:00Z' }),
    ];
    const approvals = [makeApproval({ id: 'approval-b' }), makeApproval({ id: 'approval-a' })];
    const originalTaskOrder = tasks.map((task) => task.id);
    const originalApprovalOrder = approvals.map((approval) => approval.id);

    deriveTodayModel(tasks, approvals, 'viewer', now);

    expect(tasks.map((task) => task.id)).toEqual(originalTaskOrder);
    expect(approvals.map((approval) => approval.id)).toEqual(originalApprovalOrder);
  });
});
