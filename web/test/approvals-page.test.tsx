import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskApprovalRequest, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { ApprovalsPage } from '../src/pages/ApprovalsPage';
import { render } from './react-test-helpers';

const task: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26090001',
  title: '整理周末晚餐', description: '列出需要购买的食材', due_at: '2026-09-02T12:00:00Z',
  status: 'TODO', current_handler_id: 'viewer', blocked_reason: null, blocked_since: null,
  resume_handler_id: null, waiting_for_user_id: null, planned_start_at: null, estimated_minutes: 30,
  completed_at: null, created_by: 'viewer', created_at: '2026-08-30T08:00:00Z',
  updated_at: '2026-08-30T08:00:00Z', delay_count: 0,
  total_delay_minutes: 0, version: 2, status_version: 1, field_versions: { title: 2 },
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: ['生活'], progress: null,
};

const incoming: TaskApprovalRequest = {
  id: 'approval-incoming', workspace_id: 'workspace-1', task_id: task.id, comment_id: null,
  requester_id: 'partner', approver_id: 'viewer', request_type: 'TASK_UPDATE',
  proposed_changes: { title: '伙伴提出的新标题' }, base_field_versions: { title: 1 },
  request_id: 'request-incoming', status: 'PENDING', created_at: '2026-09-01T08:00:00Z',
  reviewed_at: null, reviewed_by: null, rejection_reason: null, resolved_cursor: null,
};

const outgoing: TaskApprovalRequest = {
  ...incoming,
  id: 'approval-outgoing', requester_id: 'viewer', approver_id: 'partner',
  request_id: 'request-outgoing', proposed_changes: { description: '我提出的描述' },
};

function makeSnapshot(approvalRequests: TaskApprovalRequest[] = [incoming, outgoing]): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [
      { user_id: 'viewer', display_name: '林木', member_slot: 1 },
      { user_id: 'partner', display_name: '溪岸', member_slot: 2 },
    ],
    tasks: [task], conflicts: [], cursor: 8, viewer_user_id: 'viewer', comments: [],
    approval_requests: approvalRequests,
  };
}

function makeSync(approvals: TaskApprovalRequest[] = [incoming, outgoing]): {
  sync: WorkspaceSyncController;
  update: (next: Partial<WorkspaceSyncState>) => void;
  approve: ReturnType<typeof vi.fn>;
  reject: ReturnType<typeof vi.fn>;
  cancel: ReturnType<typeof vi.fn>;
} {
  let state: WorkspaceSyncState = {
    snapshot: makeSnapshot(approvals), cursor: 8, loading: false, stale: false,
    error: null, conflicts: [], authRequired: false, approvals,
  };
  const listeners = new Set<(next: WorkspaceSyncState) => void>();
  const approve = vi.fn<(...args: [string]) => Promise<unknown>>().mockResolvedValue(undefined);
  const reject = vi.fn<(...args: [string, string?]) => Promise<unknown>>().mockResolvedValue(undefined);
  const cancel = vi.fn<(...args: [string]) => Promise<unknown>>().mockResolvedValue(undefined);
  const sync = {
    get state(): WorkspaceSyncState { return state; },
    subscribe(listener: (next: WorkspaceSyncState) => void): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    approveApproval: approve,
    rejectApproval: reject,
    cancelApproval: cancel,
  } as unknown as WorkspaceSyncController;
  return {
    sync,
    update: (next) => {
      state = { ...state, ...next };
      listeners.forEach((listener) => listener(state));
    },
    approve,
    reject,
    cancel,
  };
}

describe('ApprovalsPage', () => {
  it('shows incoming and outgoing request rows with the pending count and action hierarchy', () => {
    const fake = makeSync();
    render(<ApprovalsPage sync={fake.sync} />);

    expect(screen.getByRole('heading', { name: '审批' })).toBeInTheDocument();
    expect(screen.getByText('需要我确认')).toBeInTheDocument();
    expect(screen.getByText('等待对方确认')).toBeInTheDocument();
    expect(screen.getAllByText('整理周末晚餐')).toHaveLength(2);
    expect(screen.getByText(/待确认.*1/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '批准' })).toHaveClass('ui-button--primary');
    expect(screen.getByRole('button', { name: '拒绝' })).toHaveClass('ui-button--danger');
    expect(screen.getByRole('button', { name: '取消请求' })).toHaveClass('ui-button--neutral');
  });

  it('disables the row actions while an approval action is pending', async () => {
    const fake = makeSync();
    let resolveApprove!: () => void;
    fake.approve.mockReturnValue(new Promise<void>((resolve) => { resolveApprove = resolve; }));
    render(<ApprovalsPage sync={fake.sync} />);

    fireEvent.click(screen.getByRole('button', { name: '批准' }));

    expect(fake.approve).toHaveBeenCalledWith(incoming.id);
    expect(screen.getByRole('button', { name: '批准' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '拒绝' })).toBeDisabled();
    resolveApprove();
    await waitFor(() => expect(screen.getByRole('button', { name: '批准' })).not.toBeDisabled());
  });

  it('renders human-readable approval subject, requester, and changes', () => {
    const fake = makeSync();
    render(<ApprovalsPage sync={fake.sync} />);

    expect(screen.getAllByText('审批事项')).toHaveLength(2);
    expect(screen.getAllByText('协作关系')).toHaveLength(2);
    expect(screen.getAllByText('变更内容')).toHaveLength(2);
    expect(screen.getByText('溪岸提出 · 等待我确认')).toBeInTheDocument();
    expect(screen.getAllByText('任务标题')).toHaveLength(1);
    expect(screen.queryByText('partner')).not.toBeInTheDocument();
    expect(screen.queryByText('viewer')).not.toBeInTheDocument();
  });

  it('keeps the rejection reason and request row when rejecting fails', async () => {
    const fake = makeSync();
    fake.reject.mockRejectedValue(new Error('网络不可用'));
    render(<ApprovalsPage sync={fake.sync} />);
    const reason = screen.getByRole('textbox', { name: '拒绝原因' });

    fireEvent.change(reason, { target: { value: '请先补充截止时间' } });
    fireEvent.click(screen.getByRole('button', { name: '拒绝' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('网络不可用'));
    expect(reason).toHaveValue('请先补充截止时间');
    expect(screen.getByText('伙伴提出的新标题')).toBeInTheDocument();
  });

  it('keeps a pending request and its rejection input after an approval action fails', async () => {
    const fake = makeSync();
    fake.reject.mockResolvedValue(undefined);
    render(<ApprovalsPage sync={fake.sync} />);
    const reason = screen.getByRole('textbox', { name: '拒绝原因' });

    fireEvent.change(reason, { target: { value: '请补充验收结果' } });
    fireEvent.click(screen.getByRole('button', { name: '拒绝' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('审批未确认'));
    expect(screen.getAllByText('待处理')).toHaveLength(2);
    expect(reason).toHaveValue('请补充验收结果');
    expect(screen.getByRole('button', { name: '批准' })).not.toBeDisabled();
  });

  it('re-renders from sync state after approval instead of removing the request locally', async () => {
    const fake = makeSync();
    fake.approve.mockImplementation(async () => {
      const approved = { ...incoming, status: 'APPROVED' as const, reviewed_at: '2026-09-01T09:00:00Z', reviewed_by: 'viewer' };
      fake.update({ approvals: [approved, outgoing], snapshot: makeSnapshot([approved, outgoing]) });
    });
    render(<ApprovalsPage sync={fake.sync} />);

    fireEvent.click(screen.getByRole('button', { name: '批准' }));

    await waitFor(() => expect(screen.getByText('已批准')).toBeInTheDocument());
    expect(screen.queryByRole('button', { name: '批准' })).not.toBeInTheDocument();
  });

  it('explains conflicted requests and preserves rows on sync errors and empty boxes', () => {
    const conflicted = { ...incoming, status: 'CONFLICTED' as const };
    const fake = makeSync([conflicted]);
    fake.update({ error: '同步失败，当前内容可能不是最新。' });
    render(<ApprovalsPage sync={fake.sync} />);

    expect(screen.getByRole('alert')).toHaveTextContent('同步失败');
    expect(screen.getByText(/版本冲突/)).toBeInTheDocument();
    expect(screen.getByText('暂无审批请求')).toBeInTheDocument();
    expect(screen.getByText('伙伴提出的新标题')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '批准' })).not.toBeInTheDocument();
  });
});
