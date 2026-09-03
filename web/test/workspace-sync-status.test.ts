import { describe, expect, it, vi } from 'vitest';
import type { TaskItem } from '../src/api/types';
import { WorkspaceSyncController } from '../src/sync/workspace-sync';

const task = (status: string): Record<string, unknown> => ({
  id: `task-${status.toLowerCase()}`,
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: 'Sync task',
  description: '',
  due_at: null,
  status,
  current_handler_id: 'user-1',
  blocked_reason: status === 'WAITING' || status === 'BLOCKED' ? '等待确认' : null,
  blocked_since: status === 'WAITING' || status === 'BLOCKED' ? '2026-09-02T10:00:00.000Z' : null,
  resume_handler_id: status === 'WAITING' || status === 'BLOCKED' ? 'user-1' : null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  reviewer_user_id: status === 'REVIEW' ? 'user-2' : null,
  review_submitted_at: status === 'REVIEW' ? '2026-09-02T11:00:00.000Z' : null,
  reviewed_at: null,
  review_rejection_reason: null,
  created_by: 'user-1',
  created_at: '2026-09-02T00:00:00.000Z',
  updated_at: '2026-09-02T11:00:00.000Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 3,
  status_version: 3,
  field_versions: { title: 1 },
  lifecycle_version: 3,
  deleted_at: null,
  quadrant: 'Q1',
  labels: [],
});

function snapshot(status: string) {
  const item = task(status);
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [],
    tasks: [item],
    conflicts: [],
    cursor: 5,
  };
}

describe('workspace sync six-state status boundary', () => {
  it('normalizes retired statuses while reading snapshots and changes', async () => {
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue({
        ...snapshot('WAITING'),
        tasks: [{ ...task('WAITING'), id: 'task-blocked' }, { ...task('COMPLETED'), id: 'task-done' }],
      }),
      getWorkspaceChanges: vi.fn().mockResolvedValue({
        workspace_id: 'workspace-1',
        cursor: 7,
        changes: [{
          cursor: 6,
          resource_type: 'task',
          resource_id: 'task-blocked',
          action: 'UPDATED',
          operation_id: null,
          resource: { ...task('WAITING'), id: 'task-blocked' },
        }, {
          cursor: 7,
          resource_type: 'task',
          resource_id: 'task-done',
          action: 'UPDATED',
          operation_id: null,
          resource: { ...task('COMPLETED'), id: 'task-done' },
        }],
      }),
      transitionTask: vi.fn(),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    expect(controller.state.snapshot?.tasks.map((item) => item.status)).toEqual(['BLOCKED', 'DONE']);

    await controller.pull();
    expect(controller.state.snapshot?.tasks.map((item) => item.status)).toEqual(['BLOCKED', 'DONE']);
  });

  it('preserves blocked and review metadata when applying canonical resources', async () => {
    const review = task('REVIEW') as TaskItem;
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue({
        ...snapshot('REVIEW'),
        tasks: [review],
        conflicts: [{
          id: 'conflict-1',
          task_id: review.id,
          field: 'status',
          base: 'IN_PROGRESS',
          current: 'REVIEW',
          proposed_payload: {
            target_status: 'IN_PROGRESS',
            review_rejection_reason: '补充截图',
          },
          status: 'OPEN',
          base_version: 2,
          current_version: 3,
          field_versions: { title: 1 },
          status_version: 3,
          lifecycle_version: 3,
        }],
      }),
      getWorkspaceChanges: vi.fn().mockResolvedValue({
        workspace_id: 'workspace-1',
        cursor: 6,
        changes: [{
          cursor: 6,
          resource_type: 'task',
          resource_id: review.id,
          action: 'UPDATED',
          operation_id: null,
          resource: { ...review, review_rejection_reason: '补充截图', status_version: 4 },
        }],
      }),
      transitionTask: vi.fn(),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    await controller.pull();

    expect(controller.state.snapshot?.tasks[0]).toMatchObject({
      status: 'REVIEW',
      reviewer_user_id: 'user-2',
      review_submitted_at: '2026-09-02T11:00:00.000Z',
      review_rejection_reason: '补充截图',
      status_version: 4,
      lifecycle_version: 3,
      field_versions: { title: 1 },
    });
    expect(controller.state.conflicts[0]).toMatchObject({
      id: 'conflict-1',
      proposed: {
        target_status: 'IN_PROGRESS',
        review_rejection_reason: '补充截图',
      },
      proposed_payload: {
        target_status: 'IN_PROGRESS',
        review_rejection_reason: '补充截图',
      },
      field_versions: { title: 1 },
      status_version: 3,
      lifecycle_version: 3,
    });
  });

  it('does not emit retired statuses in transition requests', async () => {
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue({ ...snapshot('TODO'), tasks: [task('TODO')] }),
      getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-1', cursor: 5, changes: [] }),
      transitionTask: vi.fn(),
    };
    const controller = new WorkspaceSyncController(api as never);
    await controller.loadSnapshot();

    await controller.transitionTask('task-todo', 'WAITING');

    expect(api.transitionTask).not.toHaveBeenCalled();
    expect(controller.state.error).toBe('无法更新任务状态，请检查网络后重试。');
  });

  it('merges task conflicts from cursor changes and removes them when resolved', async () => {
    let pullCount = 0;
    const openConflict = {
      id: 'conflict-1',
      task_id: 'task-todo',
      field: 'status',
      base: 'TODO',
      current: 'IN_PROGRESS',
      proposed: 'BLOCKED',
      proposed_payload: { target_status: 'BLOCKED', blocked_reason: '等待资料' },
      status: 'OPEN',
      base_version: 1,
      current_version: 2,
      current_snapshot: {
        ...task('BLOCKED'),
        id: 'task-todo',
        status: 'BLOCKED',
        blocked_reason: '等待资料',
        status_version: 2,
        lifecycle_version: 2,
      },
      field_versions: { title: 1 },
      status_version: 2,
      lifecycle_version: 2,
    };
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue({ ...snapshot('TODO'), tasks: [task('TODO')], conflicts: [] }),
      getWorkspaceChanges: vi.fn().mockImplementation(async () => {
        pullCount += 1;
        return pullCount === 1
          ? {
              workspace_id: 'workspace-1',
              cursor: 6,
              changes: [{
                cursor: 6,
                resource_type: 'task_conflict',
                resource_id: 'conflict-1',
                action: 'CREATED',
                operation_id: null,
                resource: openConflict,
              }],
            }
          : {
              workspace_id: 'workspace-1',
              cursor: 7,
              changes: [{
                cursor: 7,
                resource_type: 'task_conflict',
                resource_id: 'conflict-1',
                action: 'UPDATED',
                operation_id: null,
                resource: { ...openConflict, status: 'RESOLVED' },
              }],
            };
      }),
      transitionTask: vi.fn(),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();
    await controller.pull();

    expect(controller.state.cursor).toBe(6);
    expect(controller.state.conflicts).toHaveLength(1);
    expect(controller.state.conflicts[0]).toMatchObject({
      id: 'conflict-1',
      status: 'OPEN',
      current_snapshot: expect.objectContaining({ status: 'BLOCKED', blocked_reason: '等待资料' }),
    });

    await controller.pull();

    expect(controller.state.cursor).toBe(7);
    expect(controller.state.conflicts).toEqual([]);
  });
});
