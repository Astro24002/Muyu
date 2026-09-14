import { describe, expect, it, vi } from 'vitest';
import type { HomeResponse, TaskApprovalRequest, TaskItem } from '../src/api/types';
import { deriveTodayModel } from '../src/tasks/task-view-model';
import { WorkspaceSyncController } from '../src/sync/workspace-sync';

const task = (id: string, status: TaskItem['status'] = 'TODO', workspaceId = 'workspace-1'): TaskItem => ({
  id,
  workspace_id: workspaceId,
  parent_task_id: null,
  title: id,
  description: '',
  due_at: null,
  status,
  current_handler_id: status === 'REVIEW' ? 'partner' : 'viewer',
  blocked_reason: status === 'BLOCKED' ? '等待确认' : null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  reviewer_user_id: status === 'REVIEW' ? 'viewer' : null,
  review_submitted_at: null,
  reviewed_at: null,
  review_rejection_reason: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-09-14T00:00:00Z',
  updated_at: '2026-09-14T00:00:00Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q2',
  labels: [],
});

const approval = (id: string, taskId: string | null = 'canonical-mine'): TaskApprovalRequest => ({
  id,
  workspace_id: 'workspace-1',
  task_id: taskId,
  comment_id: null,
  requester_id: 'partner',
  approver_id: 'viewer',
  request_type: taskId === 'canonical-review' ? 'STATUS_UPDATE' : taskId === null ? 'CLASSIFICATION_CREATE' : 'TASK_UPDATE',
  proposed_changes: taskId === 'canonical-review' ? { target_status: 'DONE', review_submission: true } : {},
  base_field_versions: {},
  request_id: `${id}-request`,
  status: 'PENDING',
  created_at: '2026-09-14T00:00:00Z',
  reviewed_at: null,
  reviewed_by: null,
  rejection_reason: null,
  resolved_cursor: null,
});

function canonicalHome(): HomeResponse {
  return {
    viewer_user_id: 'viewer',
    as_of: '2026-09-14T10:00:00Z',
    week: {
      timezone: 'UTC',
      start: '2026-09-14T00:00:00Z',
      end: '2026-09-21T00:00:00Z',
    },
    entry_counts: { needs_me: 2, waiting_on_other: 1, due_this_week: 3 },
    // Deliberately disagree with the deprecated fields to prove the model
    // uses canonical sections when both projections are present.
    current_tasks: { items: [task('legacy-current')], has_more: false },
    blocked_tasks: { items: [task('legacy-blocked', 'BLOCKED')], has_more: false },
    review_tasks: { items: [task('legacy-review', 'REVIEW')], has_more: false },
    pending_approval_count: 0,
    moment: {
      blocked: { items: [task('canonical-blocked', 'BLOCKED')], has_more: false },
      mine: { items: [task('canonical-mine', 'IN_PROGRESS')], has_more: true },
      other: { items: [task('canonical-other')], has_more: false },
      all_tasks_has_more: false,
    },
    entries: {
      needs_me: {
        items: [
          { approval_request: approval('task-approval', null), task: null },
          { approval_request: approval('review-approval', 'canonical-review'), task: task('canonical-review', 'REVIEW') },
        ],
        has_more: false,
      },
      waiting_on_other: {
        items: [{ approval_request: { ...approval('outgoing', null), requester_id: 'viewer', approver_id: 'partner' }, task: null }],
        has_more: false,
      },
      due_this_week: { items: [task('canonical-due')], has_more: false },
    },
  };
}

describe('canonical Home projection', () => {
  it('uses canonical moment, entries, and counts over deprecated aliases', () => {
    const home = canonicalHome();
    const model = deriveTodayModel([], [], 'viewer', new Date('2026-09-14T10:00:00Z'), home);

    expect(model.current.map((item) => item.id)).toEqual(['canonical-mine']);
    expect(model.currentHasMore).toBe(true);
    expect(model.blocked.map((item) => item.id)).toEqual(['canonical-blocked']);
    expect(model.review.map((item) => item.id)).toEqual(['canonical-review']);
    expect(model.pendingApprovals.map((item) => item.id)).toEqual(['task-approval', 'review-approval']);
    expect(model.pendingApprovalCount).toBe(2);
  });

  it('normalizes canonical Home-only payloads and preserves the last projection on refresh failure', async () => {
    const snapshot = {
      workspace_id: 'workspace-1',
      workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [],
      tasks: [task('snapshot-task')],
      conflicts: [],
      cursor: 5,
      classifications: [],
    };
    const home = canonicalHome();
    delete home.current_tasks;
    delete home.blocked_tasks;
    delete home.review_tasks;
    delete home.pending_approval_count;
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue(snapshot),
      getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-1', cursor: 5, changes: [] }),
      getHome: vi.fn().mockResolvedValue(home),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();

    expect(controller.state.home?.viewer_user_id).toBe('viewer');
    expect(controller.state.home?.moment?.mine?.items.map((item) => item.id)).toEqual(['canonical-mine']);
    expect(controller.state.home?.entries?.needs_me.items).toHaveLength(2);

    api.getHome.mockRejectedValueOnce(new Error('offline'));
    await controller.loadSnapshot();

    expect(controller.state.home?.moment?.mine?.items.map((item) => item.id)).toEqual(['canonical-mine']);
    expect(controller.state.stale).toBe(true);
    expect(controller.state.error).toBe('无法加载首页，请检查网络后重试。');
  });

  it('rejects a canonical entry task from another workspace', async () => {
    const home = canonicalHome();
    const invalid = {
      ...home,
      entries: {
        ...home.entries!,
        needs_me: {
          ...home.entries!.needs_me,
          items: [{ approval_request: approval('foreign-task', 'foreign-task'), task: task('foreign-task', 'TODO', 'workspace-foreign') }],
        },
      },
    };
    const snapshot = {
      workspace_id: 'workspace-1',
      workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [],
      tasks: [task('snapshot-task')],
      conflicts: [],
      cursor: 5,
      classifications: [],
    };
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue(snapshot),
      getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-1', cursor: 5, changes: [] }),
      getHome: vi.fn().mockResolvedValue(invalid),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();

    expect(controller.state.home).toBeUndefined();
    expect(controller.state.stale).toBe(true);
    expect(controller.state.error).toBe('无法加载首页，请检查网络后重试。');
  });

  it('rejects a canonical approval entry with a task id but no task snapshot', async () => {
    const home = canonicalHome();
    const invalid = {
      ...home,
      entries: {
        ...home.entries!,
        needs_me: {
          ...home.entries!.needs_me,
          items: [{ approval_request: approval('missing-task'), task: null }],
        },
      },
    };
    const snapshot = {
      workspace_id: 'workspace-1',
      workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [],
      tasks: [task('snapshot-task')],
      conflicts: [],
      cursor: 5,
      classifications: [],
    };
    const api = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValue(snapshot),
      getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-1', cursor: 5, changes: [] }),
      getHome: vi.fn().mockResolvedValue(invalid),
    };
    const controller = new WorkspaceSyncController(api as never);

    await controller.loadSnapshot();

    expect(controller.state.home).toBeUndefined();
    expect(controller.state.stale).toBe(true);
    expect(controller.state.error).toBe('无法加载首页，请检查网络后重试。');
  });
});
