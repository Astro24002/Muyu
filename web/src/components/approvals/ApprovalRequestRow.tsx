import { Check, CircleX, X } from 'lucide-react';
import { useId, useState, type JSX } from 'react';
import type { TaskApprovalRequest, TaskItem } from '../../api/types';
import { Button } from '../ui/Button';
import { StatusBadge } from '../ui/StatusBadge';

export interface ApprovalRequestRowProps {
  request: TaskApprovalRequest;
  task?: TaskItem | null;
  incoming: boolean;
  busy: boolean;
  onApprove: (approvalId: string) => void | Promise<void>;
  onReject: (approvalId: string, reason?: string) => void | Promise<void>;
  onCancel: (approvalId: string) => void | Promise<void>;
}

export function ApprovalRequestRow({
  request,
  task,
  incoming,
  busy,
  onApprove,
  onReject,
  onCancel,
}: ApprovalRequestRowProps): JSX.Element {
  const reasonId = useId();
  const [rejectionReason, setRejectionReason] = useState('');
  const isPending = request.status === 'PENDING';
  const taskLabel = request.request_type === 'CLASSIFICATION_CREATE'
    ? `新建分类：${typeof request.proposed_changes.name === 'string' ? request.proposed_changes.name : '未命名分类'}`
    : incoming
      ? task?.title || request.task_id || '协作请求'
      : task?.task_number ? `任务 ${task.task_number}` : `任务 ${request.task_id || '协作请求'}`;

  return (
    <article className="approval-request-row" data-approval-id={request.id}>
      <div className="approval-request-row__content">
        <div className="approval-request-row__heading">
          <h3 className="approval-request-row__title">{taskLabel}</h3>
          <StatusBadge status={request.status}>{statusLabel(request.status)}</StatusBadge>
        </div>

        <p className="approval-request-row__meta">
          {requestTypeLabel(request.request_type)} · 发起人：{request.requester_id} · 审批人：{request.approver_id}
        </p>
        <p className="approval-request-row__meta">创建时间：{request.created_at}</p>

        {Object.keys(request.proposed_changes).length > 0 ? (
          <p className="approval-request-row__changes">
            建议变更：
            {Object.entries(request.proposed_changes).map(([key, value], index) => (
              <span key={key}>
                {index > 0 ? ', ' : null}
                <span className="approval-request-row__change-key">{key}=</span>
                <span className="approval-request-row__change-value">{formatValue(value)}</span>
              </span>
            ))}
          </p>
        ) : null}

        {request.comment_id ? (
          <p className="approval-request-row__meta">关联评论：{request.comment_id}</p>
        ) : null}

        {request.status === 'CONFLICTED' ? (
          <p className="approval-request-row__notice approval-request-row__notice--conflict">
            版本冲突，变更未应用
          </p>
        ) : null}
        {request.rejection_reason ? (
          <p className="approval-request-row__notice">说明：{request.rejection_reason}</p>
        ) : null}
      </div>

      {incoming && isPending ? (
        <div className="approval-request-row__reason">
          <label htmlFor={reasonId}>拒绝原因</label>
          <textarea
            id={reasonId}
            value={rejectionReason}
            rows={2}
            disabled={busy}
            onChange={(event) => setRejectionReason(event.target.value)}
          />
        </div>
      ) : null}

      {isPending && incoming ? (
        <div className="approval-request-row__actions">
          <Button
            tone="primary"
            disabled={busy}
            data-action="approve"
            data-approval-action="approve"
            data-approval-id={request.id}
            onClick={() => void onApprove(request.id)}
          >
            <Check aria-hidden="true" size={16} strokeWidth={2} />
            <span>批准</span>
          </Button>
          <Button
            tone="danger"
            disabled={busy}
            data-action="reject"
            data-approval-action="reject"
            data-approval-id={request.id}
            onClick={() => void onReject(request.id, rejectionReason.trim() || undefined)}
          >
            <X aria-hidden="true" size={16} strokeWidth={2} />
            <span>拒绝</span>
          </Button>
        </div>
      ) : null}

      {isPending && !incoming ? (
        <div className="approval-request-row__actions">
          <Button
            tone="neutral"
            disabled={busy}
            data-action="cancel"
            data-approval-action="cancel"
            data-approval-id={request.id}
            onClick={() => void onCancel(request.id)}
          >
            <CircleX aria-hidden="true" size={16} strokeWidth={2} />
            <span>取消请求</span>
          </Button>
        </div>
      ) : null}

      {busy && isPending ? (
        <span className="approval-request-row__busy" role="status" aria-live="polite">正在处理</span>
      ) : null}
    </article>
  );
}

function formatValue(value: unknown): string {
  if (typeof value === 'string') return value;
  try {
    const serialized = JSON.stringify(value);
    return serialized === undefined ? String(value) : serialized;
  } catch {
    return String(value);
  }
}

function requestTypeLabel(type: TaskApprovalRequest['request_type']): string {
  const labels: Record<TaskApprovalRequest['request_type'], string> = {
    TASK_UPDATE: '任务修改',
    QUADRANT_UPDATE: '四象限修改',
    STATUS_UPDATE: '状态修改',
    TASK_DELETE: '删除任务',
    TASK_RESTORE: '恢复任务',
    COMMENT_DELETE: '删除评论',
    HANDLER_TRANSFER: '负责人转移',
    CLASSIFICATION_CREATE: '新建分类',
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
