import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { PendingApproval, TaskApprovalRequest, TaskComment, TaskItem } from '../src/api/types';
import type { TaskConflict } from '../src/tasks/task-model';
import type { TaskDetailActions } from '../src/tasks/task-detail-actions';
import type { WorkspaceSyncState } from '../src/sync/workspace-sync';
import { TaskDetailPanel } from '../src/components/tasks/TaskDetailPanel';
import { render } from './react-test-helpers';

const task: TaskItem = {
  id: 'task-1', workspace_id: 'workspace-1', parent_task_id: null, task_number: '26090001',
  title: '原始标题', description: '下一步描述', due_at: '2026-09-02T12:00:00Z', status: 'TODO',
  current_handler_id: 'viewer', blocked_reason: null, blocked_since: null, resume_handler_id: null,
  waiting_for_user_id: null, planned_start_at: null, estimated_minutes: 30, completed_at: null,
  created_by: 'viewer', created_at: '2026-08-30T08:00:00Z', updated_at: '2026-08-30T08:00:00Z',
  delay_count: 1, total_delay_minutes: 30, version: 3,
  status_version: 2, field_versions: { title: 3, description: 2, quadrant: 1, labels: 1 },
  lifecycle_version: 1, deleted_at: null, quadrant: 'Q2', labels: ['工作'], progress: null,
};

const comment: TaskComment = {
  id: 'comment-1', workspace_id: 'workspace-1', task_id: task.id, author_user_id: 'partner', body: '我会在今晚确认。', version: 1,
  deleted_at: null, deleted_by: null, created_at: '2026-09-01T08:00:00Z',
};

const approval: TaskApprovalRequest = {
  id: 'approval-1', workspace_id: 'workspace-1', task_id: task.id, comment_id: null,
  requester_id: 'partner', approver_id: 'viewer', request_type: 'TASK_UPDATE',
  proposed_changes: { title: '提议标题' }, base_field_versions: { title: 2 }, request_id: 'request-1',
  status: 'PENDING', created_at: '2026-09-01T07:00:00Z', reviewed_at: null, reviewed_by: null,
  rejection_reason: null, resolved_cursor: null,
};

function makeState(overrides: Partial<WorkspaceSyncState> = {}): WorkspaceSyncState {
  return {
    snapshot: {
      workspace_id: 'workspace-1', workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [{ user_id: 'viewer', member_slot: 1 }, { user_id: 'partner', member_slot: 2 }],
      tasks: [task], conflicts: [], cursor: 8, viewer_user_id: 'viewer', comments: [comment], approval_requests: [approval],
    },
    cursor: 8, loading: false, stale: false, error: null, conflicts: [], authRequired: false,
    comments: [comment], approvals: [approval], ...overrides,
  };
}

function makeActions(onSave = vi.fn().mockResolvedValue(undefined)): TaskDetailActions {
  return {
    onTransition: vi.fn().mockResolvedValue(undefined),
    onComment: vi.fn().mockResolvedValue(undefined),
    onDelay: vi.fn().mockResolvedValue(undefined),
    onSave,
    onDeleteComment: vi.fn().mockResolvedValue(undefined),
    onResolveConflict: vi.fn().mockResolvedValue(undefined),
    currentUserId: 'viewer',
    canWrite: true,
  };
}

describe('TaskDetailPanel', () => {
  it('renders the task in a desktop drawer with priority fields and detail sections', () => {
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1280 });
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={makeActions()} onClose={vi.fn()} />);

    const panel = screen.getByRole('dialog', { name: '任务详情' });
    expect(panel).toHaveAttribute('data-panel-mode', 'drawer');
    expect(screen.getByRole('heading', { name: '原始标题' })).toBeInTheDocument();
    expect(screen.getByLabelText('描述')).toHaveValue('下一步描述');
    expect(screen.getByLabelText(/负责人/)).toHaveValue('viewer');
    expect(screen.getByText('待进行')).toBeInTheDocument();
    expect(screen.getByText(/截止/)).toBeInTheDocument();
    expect(screen.getByText('评论')).toBeInTheDocument();
    expect(screen.getByText('延期')).toBeInTheDocument();
    expect(screen.getByText('审批')).toBeInTheDocument();
    expect(screen.getByText('活动')).toBeInTheDocument();
    expect(screen.getByText('我会在今晚确认。')).toBeInTheDocument();
  });

  it('uses a full-width bottom sheet below the desktop breakpoint', () => {
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 800 });
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={makeActions()} onClose={vi.fn()} />);

    expect(screen.getByRole('dialog', { name: '任务详情' })).toHaveAttribute('data-panel-mode', 'bottom-sheet');
  });

  it('keeps the edit draft when saving fails and preserves the existing action contracts', async () => {
    const onSave = vi.fn().mockRejectedValue(new Error('保存失败'));
    const actions = makeActions(onSave);
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '本地修改' } });
    fireEvent.change(screen.getByLabelText('描述'), { target: { value: '更新后的下一步' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('保存失败'));
    expect(onSave).toHaveBeenCalledWith({ title: '本地修改', description: '更新后的下一步' });
    expect(screen.getByLabelText('标题')).toHaveValue('本地修改');
    expect(screen.getByLabelText('描述')).toHaveValue('更新后的下一步');
  });

  it('sends only changed fields when the task owner edits a task', async () => {
    const onSave = vi.fn().mockResolvedValue({ ...task, title: '只改标题', cursor: 4 });
    const actions = makeActions(onSave);
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '只改标题' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(onSave).toHaveBeenCalledWith({ title: '只改标题' }));
  });

  it('does not allow an existing task deadline to be cleared', async () => {
    const onSave = vi.fn().mockResolvedValue({ ...task, cursor: 4 });
    const actions = makeActions(onSave);
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('截止时间'), { target: { value: '' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('截止时间不能为空');
  });

  it('sends only the changed quadrant when the viewer is not the task owner', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const actions = { ...makeActions(onSave), currentUserId: 'partner' };
    const state = makeState();
    render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q1' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(onSave).toHaveBeenCalledWith({ quadrant: 'Q1' }));
  });

  it('blocks mixed special and regular changes in a non-owner approval request', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const actions = { ...makeActions(onSave), currentUserId: 'partner' };
    const state = makeState();
    render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '新标题' } });
    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q1' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('四象限或负责人变更需要单独提交审批');
  });

  it('delegates status, comment, delay, comment deletion and close actions', async () => {
    const onClose = vi.fn();
    const actions = makeActions();
    render(<TaskDetailPanel task={task} members={makeState().snapshot!.members} syncState={makeState()} actions={actions} onClose={onClose} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '更新状态' }));
    fireEvent.change(screen.getByLabelText('评论输入'), { target: { value: '补充说明' } });
    fireEvent.click(screen.getByRole('button', { name: '添加评论' }));
    fireEvent.change(screen.getByLabelText('新截止时间'), { target: { value: '2026-09-04T10:30' } });
    fireEvent.click(screen.getByRole('button', { name: '提交延期' }));
    fireEvent.click(screen.getByRole('button', { name: '删除评论' }));
    fireEvent.click(screen.getByRole('button', { name: '关闭任务详情' }));
    await waitFor(() => expect(actions.onComment).toHaveBeenCalledWith('补充说明'));

    expect(actions.onTransition).toHaveBeenCalledWith('IN_PROGRESS');
    expect(actions.onDelay).toHaveBeenCalledWith('2026-09-04T10:30:00.000Z', expect.any(String), undefined);
    expect(actions.onDeleteComment).toHaveBeenCalledWith(comment.id, comment.version);
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('keeps a local field draft while a reconciled task arrives from sync', () => {
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={makeActions()} onClose={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '仍在编辑' } });

    const serverTask = { ...task, title: '服务器标题', status: 'IN_PROGRESS' as const };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={makeActions()} onClose={vi.fn()} />);

    expect(screen.getByLabelText('标题')).toHaveValue('仍在编辑');
    expect(screen.getByLabelText('状态')).toHaveValue('IN_PROGRESS');
  });

  it('clears saved field dirtiness so a later server rerender can update the field', async () => {
    const onSave = vi.fn().mockResolvedValue({ ...task, title: '本地修改', cursor: 4 });
    const actions = makeActions(onSave);
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '本地修改' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledWith({ title: '本地修改' }));

    const serverTask = { ...task, title: '服务器标题', version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    await waitFor(() => expect(screen.getByLabelText('标题')).toHaveValue('服务器标题'));
  });

  it('keeps saved fields dirty while the controller returns a pending approval', async () => {
    const pending: PendingApproval = { pending: true, approval_request: approval, cursor: 4 };
    const onSave = vi.fn().mockResolvedValue(pending);
    const actions = makeActions(onSave);
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '等待审批标题' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('等待负责人审批'));

    const serverTask = { ...task, title: '服务器标题', version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('标题')).toHaveValue('等待审批标题');
  });

  it('keeps saved fields dirty when the controller reports failure with undefined', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const actions = makeActions(onSave);
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '未确认标题' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    await waitFor(() => expect(onSave).toHaveBeenCalled());

    const serverTask = { ...task, title: '服务器标题', version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('标题')).toHaveValue('未确认标题');
  });

  it('clears status dirtiness after an applied transition', async () => {
    const onTransition = vi.fn().mockResolvedValue({ ...task, status: 'IN_PROGRESS', cursor: 4 });
    const actions = { ...makeActions(), onTransition };
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '更新状态' }));
    await waitFor(() => expect(onTransition).toHaveBeenCalledWith('IN_PROGRESS'));

    const serverTask = { ...task, status: 'DONE' as const, version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    await waitFor(() => expect(screen.getByLabelText('状态')).toHaveValue('DONE'));
  });

  it('keeps a status draft dirty while a transition is awaiting approval', async () => {
    const pending: PendingApproval = { pending: true, approval_request: approval, cursor: 4 };
    const onTransition = vi.fn().mockResolvedValue(pending);
    const actions = { ...makeActions(), onTransition };
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '更新状态' }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('等待负责人审批'));

    const serverTask = { ...task, status: 'DONE' as const, version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('状态')).toHaveValue('IN_PROGRESS');
  });

  it('keeps a status draft dirty when a transition resolves without an applied result', async () => {
    const onTransition = vi.fn().mockResolvedValue(undefined);
    const actions = { ...makeActions(), onTransition };
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '更新状态' }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('状态更新未确认'));

    const serverTask = { ...task, status: 'DONE' as const, version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('状态')).toHaveValue('IN_PROGRESS');
  });

  it('preserves a field edited again while its previous save is pending', async () => {
    let resolveSave!: (value: TaskItem & { cursor: number }) => void;
    const onSave = vi.fn().mockReturnValue(new Promise<TaskItem & { cursor: number }>((resolve) => { resolveSave = resolve; }));
    const actions = makeActions(onSave);
    const state = makeState();
    const { rerender } = render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '第一次修改' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    await waitFor(() => expect(onSave).toHaveBeenCalledWith({ title: '第一次修改' }));

    fireEvent.change(screen.getByLabelText('标题'), { target: { value: '提交后再次修改' } });
    resolveSave({ ...task, title: '第一次修改', cursor: 4 });
    await waitFor(() => expect(screen.getByRole('button', { name: '保存' })).not.toHaveTextContent('保存中'));

    const serverTask = { ...task, title: '服务器标题', version: 4 };
    rerender(<TaskDetailPanel task={serverTask} members={state.snapshot!.members} syncState={makeState({ snapshot: { ...state.snapshot!, tasks: [serverTask] } })} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('标题')).toHaveValue('提交后再次修改');
  });

  it('closes on Escape', () => {
    const onClose = vi.fn();
    const state = makeState();
    render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={makeActions()} onClose={onClose} />);

    fireEvent.keyDown(document, { key: 'Escape' });

    expect(onClose).toHaveBeenCalledOnce();
  });

  it('disables every write control when the task is not writable', () => {
    const conflicts: TaskConflict[] = [
      { id: 'conflict-title', task_id: task.id, field: '标题', base: '旧标题', current: '当前标题', proposed: '提议标题' },
    ];
    const state = makeState({ conflicts });
    const actions = { ...makeActions(), canWrite: false };
    render(<TaskDetailPanel task={task} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    for (const label of ['标题', '描述', '状态', '负责人', '截止时间', '四象限', '标签', '评论输入', '新截止时间', '延期原因', '延期说明']) {
      expect(screen.getByLabelText(label)).toBeDisabled();
    }
    expect(screen.getByRole('button', { name: '保存' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '更新状态' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '添加评论' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '提交延期' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '保留当前' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '采用提议' })).toBeDisabled();
  });

  it('keeps a revoked current handler visible as a disabled option', () => {
    const revokedTask = { ...task, current_handler_id: 'revoked-user' };
    const state = makeState({
      snapshot: {
        ...makeState().snapshot!,
        members: [...makeState().snapshot!.members, { user_id: 'revoked-user', member_slot: 3, membership_status: 'REVOKED' }],
        tasks: [revokedTask],
      },
    });

    render(<TaskDetailPanel task={revokedTask} members={state.snapshot!.members} syncState={state} actions={makeActions()} onClose={vi.fn()} />);

    expect(screen.getByLabelText('负责人')).toHaveValue('revoked-user');
    for (const option of screen.getAllByRole('option', { name: 'revoked-user' })) {
      expect(option).toBeDisabled();
    }
    expect(screen.getByRole('option', { name: 'viewer' })).not.toBeDisabled();
  });

  it('blocks recovery while the stored resume handler is no longer active', () => {
    const blockedTask = {
      ...task,
      status: 'BLOCKED' as const,
      resume_handler_id: 'revoked-user',
      blocked_reason: '等待确认',
    };
    const onTransition = vi.fn().mockResolvedValue(undefined);
    const actions = { ...makeActions(), onTransition };
    const state = makeState({
      snapshot: {
        ...makeState().snapshot!,
        members: [...makeState().snapshot!.members, { user_id: 'revoked-user', member_slot: 3, membership_status: 'REVOKED' }],
        tasks: [blockedTask],
      },
    });

    render(<TaskDetailPanel task={blockedTask} members={state.snapshot!.members} syncState={state} actions={actions} onClose={vi.fn()} />);

    expect(screen.getByLabelText('恢复负责人')).toHaveValue('revoked-user');
    for (const option of screen.getAllByRole('option', { name: 'revoked-user' })) {
      expect(option).toBeDisabled();
    }
    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '更新状态' }));

    expect(onTransition).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('请选择有效的恢复负责人');
  });

  it('does not submit a dirty current handler after that member is revoked', async () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    const actions = makeActions(onSave);
    const state = makeState();
    const { rerender } = render(
      <TaskDetailPanel
        task={task}
        members={state.snapshot!.members}
        syncState={state}
        actions={actions}
        onClose={vi.fn()}
      />,
    );

    fireEvent.change(screen.getByLabelText('负责人'), { target: { value: 'partner' } });
    const revokedTask = { ...task, version: 4 };
    const revokedState = makeState({
      snapshot: {
        ...state.snapshot!,
        members: [
          { user_id: 'viewer', member_slot: 1 },
          { user_id: 'partner', member_slot: 2, membership_status: 'REVOKED' },
        ],
        tasks: [revokedTask],
      },
    });
    rerender(
      <TaskDetailPanel
        task={revokedTask}
        members={revokedState.snapshot!.members}
        syncState={revokedState}
        actions={actions}
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByLabelText('负责人')).toHaveValue('partner');
    expect(screen.getByRole('option', { name: 'partner' })).toBeDisabled();
    fireEvent.click(screen.getByRole('button', { name: '保存' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('请选择有效的负责人'));
    expect(onSave).not.toHaveBeenCalled();
  });
});
