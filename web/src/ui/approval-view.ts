import type { TaskApprovalRequest, TaskComment, TaskItem } from '../api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';

export type ApprovalViewHandle = () => void;

/** Renders the two approval inboxes from the sync controller's authoritative state. */
export class ApprovalView {
  static mount(root: Element, sync: WorkspaceSyncController, currentUserId: string): ApprovalViewHandle {
    let disposed = false;

    const render = (state: WorkspaceSyncState) => {
      if (disposed) return;
      const view = document.createElement('section');
      view.className = 'approval-view';
      view.setAttribute('aria-label', '任务审批');
      const approvals = state.approvals ?? state.snapshot?.approval_requests ?? [];
      const tasks = state.snapshot?.tasks ?? [];
      const comments = state.comments ?? state.snapshot?.comments ?? [];
      view.append(heading('任务审批'));
      if (state.error) view.append(message('sync-error', state.error));
      view.append(buildBox('待我审批', approvals.filter((request) => request.approver_id === currentUserId), true, tasks, comments, sync, state.loading));
      view.append(buildBox('我发起的请求', approvals.filter((request) => request.requester_id === currentUserId), false, tasks, comments, sync, state.loading));
      root.replaceChildren(view);
    };

    const unsubscribe = sync.subscribe(render);
    render(sync.state);
    return () => {
      if (disposed) return;
      disposed = true;
      unsubscribe();
      root.replaceChildren();
    };
  }
}

function buildBox(
  label: string,
  requests: TaskApprovalRequest[],
  incoming: boolean,
  tasks: TaskItem[],
  comments: TaskComment[],
  sync: WorkspaceSyncController,
  loading: boolean,
): HTMLElement {
  const box = document.createElement('section');
  box.className = incoming ? 'approval-box approval-incoming' : 'approval-box approval-outgoing';
  box.append(heading(label));
  if (requests.length === 0) {
    box.append(message('approval-empty', '暂无审批请求'));
    return box;
  }
  const list = document.createElement('div');
  list.className = 'approval-list';
  for (const request of requests) list.append(requestCard(request, incoming, tasks, comments, sync, loading));
  box.append(list);
  return box;
}

function requestCard(
  request: TaskApprovalRequest,
  incoming: boolean,
  tasks: TaskItem[],
  comments: TaskComment[],
  sync: WorkspaceSyncController,
  loading: boolean,
): HTMLElement {
  const card = document.createElement('article');
  card.className = 'approval-card';
  card.dataset.approvalId = request.id;
  const task = tasks.find((item) => item.id === request.task_id);
  const taskLabel = task ? `${task.task_number ?? task.id} ${task.title}` : request.task_id;
  card.append(
    heading(taskLabel),
    message('approval-meta', `${requestTypeLabel(request.request_type)} · ${statusLabel(request.status)}`),
    message('approval-meta', `发起人：${request.requester_id}`),
    message('approval-meta', `审批人：${request.approver_id}`),
  );
  if (Object.keys(request.proposed_changes).length > 0) {
    card.append(message('approval-changes', `建议变更：${formatChanges(request.proposed_changes)}`));
  }
  if (request.comment_id) {
    const comment = comments.find((item) => item.id === request.comment_id);
    card.append(message('approval-changes', `评论：${comment ? comment.deleted_at ? '评论已删除' : comment.body : request.comment_id}`));
  }
  if (request.rejection_reason) card.append(message('approval-reason', `说明：${request.rejection_reason}`));

  if (request.status === 'PENDING' && incoming) {
    const actions = document.createElement('div');
    actions.className = 'approval-actions';
    const approve = actionButton('批准', 'approve', request.id, loading, () => void sync.approveApproval(request.id));
    const reject = actionButton('拒绝', 'reject', request.id, loading, () => void sync.rejectApproval(request.id));
    actions.append(approve, reject);
    card.append(actions);
  } else if (request.status === 'PENDING' && !incoming) {
    const actions = document.createElement('div');
    actions.className = 'approval-actions';
    actions.append(actionButton('取消请求', 'cancel', request.id, loading, () => void sync.cancelApproval(request.id)));
    card.append(actions);
  }
  return card;
}

function actionButton(label: string, action: string, approvalId: string, disabled: boolean, handler: () => void): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = label;
  button.dataset.action = action;
  button.dataset.approvalAction = action;
  button.dataset.approvalId = approvalId;
  button.disabled = disabled;
  button.addEventListener('click', handler);
  return button;
}

function heading(value: string): HTMLHeadingElement {
  const node = document.createElement('h2');
  node.textContent = value;
  return node;
}

function message(className: string, value: string): HTMLParagraphElement {
  const node = document.createElement('p');
  node.className = className;
  node.textContent = value;
  return node;
}

function formatChanges(changes: Record<string, unknown>): string {
  return Object.entries(changes).map(([key, value]) => `${key}=${formatValue(value)}`).join(', ');
}

function formatValue(value: unknown): string {
  if (typeof value === 'string') return value;
  try { return JSON.stringify(value); } catch { return String(value); }
}

function requestTypeLabel(type: TaskApprovalRequest['request_type']): string {
  const labels: Record<TaskApprovalRequest['request_type'], string> = {
    TASK_UPDATE: '任务修改',
    QUADRANT_UPDATE: '四象限修改',
    STATUS_UPDATE: '状态修改',
    TASK_DELETE: '删除任务',
    TASK_RESTORE: '恢复任务',
    COMMENT_DELETE: '删除评论',
    ASSIGNEE_UPDATE: '协作者修改',
    HANDLER_TRANSFER: '负责人转移',
  };
  return labels[type];
}

function statusLabel(status: TaskApprovalRequest['status']): string {
  const labels: Record<TaskApprovalRequest['status'], string> = {
    PENDING: '待处理',
    APPROVED: '已批准',
    REJECTED: '已拒绝',
    CONFLICTED: '已冲突',
    CANCELLED: '已取消',
  };
  return labels[status];
}
