import { Check, CircleX, Clock3, X } from 'lucide-react';
import { useId, useState, type JSX } from 'react';
import type { TaskApprovalRequest, TaskItem } from '../../api/types';
import { statusLabel as taskStatusLabel } from '../../tasks/task-status';
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
  memberLabel?: (userId: string) => string;
}

export function ApprovalRequestRow({
  request,
  task,
  incoming,
  busy,
  onApprove,
  onReject,
  onCancel,
  memberLabel = fallbackMemberLabel,
}: ApprovalRequestRowProps): JSX.Element {
  const reasonId = useId();
  const [rejectionReason, setRejectionReason] = useState('');
  const isPending = request.status === 'PENDING';
  const isReviewSubmission = isTaskReviewSubmission(request);
  const subject = approvalSubject(request, task);
  const changes = approvalChanges(request, memberLabel);
  const requester = memberLabel(request.requester_id);
  const approver = memberLabel(request.approver_id);
  const relationLabel = incoming ? `${requester}提出 · 等待我确认` : `我提出 · 等待${approver}确认`;
  const relationPerson = incoming ? requester : '我';

  return (
    <article className="approval-request-row" data-approval-id={request.id}>
      <div className="approval-request-row__content">
        <div className="approval-request-row__heading">
          <div className="approval-request-row__type">
            <span className="approval-request-row__type-label">{requestTypeLabel(request, isReviewSubmission)}</span>
            <span className="approval-request-row__request-id">审批请求</span>
          </div>
          <StatusBadge status={request.status}>{statusLabel(request.status)}</StatusBadge>
        </div>

        <h3 className="approval-request-row__title">
          {task?.task_number ? (
            <>
              <span className="approval-request-row__task-number">{task.task_number}</span>
              <span className="approval-request-row__task-title">{task.title}</span>
            </>
          ) : subject}
        </h3>

        <dl className="approval-request-row__details">
          <div className="approval-request-row__detail" data-approval-field="subject">
            <dt>审批事项</dt>
            <dd>{requestTypeLabel(request, isReviewSubmission)}<span className="approval-request-row__detail-separator">·</span>{subject}</dd>
          </div>
          <div className="approval-request-row__detail" data-approval-field="relation">
            <dt>协作关系</dt>
            <dd className="approval-request-row__person">
              <span className="approval-request-row__avatar" aria-hidden="true">{initialOf(relationPerson)}</span>
              <span>{relationLabel}</span>
            </dd>
          </div>
          <div className="approval-request-row__detail approval-request-row__detail--changes" data-approval-field="changes">
            <dt>变更内容</dt>
            <dd>
              {changes.length > 0 ? (
                <ul className="approval-request-row__change-list">
                  {changes.map((change) => (
                    <li key={change.key}>
                      <span className="approval-request-row__change-key">{change.label}</span>
                      <span className="approval-request-row__change-value">{change.value}</span>
                    </li>
                  ))}
                </ul>
              ) : <span className="approval-request-row__empty-change">无需填写具体字段</span>}
            </dd>
          </div>
        </dl>

        <p className="approval-request-row__meta approval-request-row__created-at">
          <Clock3 aria-hidden="true" size={13} />
          发起于 {formatDate(request.created_at)}
        </p>

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

interface ApprovalChange {
  key: string;
  label: string;
  value: string;
}

const CHANGE_LABELS: Record<string, string> = {
  title: '任务标题',
  description: '任务描述',
  due_at: '截止时间',
  planned_start_at: '计划开始',
  estimated_minutes: '预计用时',
  quadrant: '四象限',
  labels: '分类',
  current_handler_id: '任务负责人',
  handler_user_id: '任务负责人',
  target_status: '目标状态',
  status: '任务状态',
  blocked_reason: '阻塞原因',
  resume_handler_id: '恢复负责人',
  waiting_for_user_id: '等待对象',
  review_rejection_reason: '退回原因',
  name: '分类名称',
};

const QUADRANT_LABELS: Record<string, string> = {
  Q1: 'Q1 重要且紧急',
  Q2: 'Q2 重要不紧急',
  Q3: 'Q3 紧急不重要',
  Q4: 'Q4 不重要不紧急',
};

function approvalSubject(request: TaskApprovalRequest, task?: TaskItem | null): string {
  if (request.request_type === 'CLASSIFICATION_CREATE') {
    const name = typeof request.proposed_changes.name === 'string' ? request.proposed_changes.name : '未命名分类';
    return `新建分类「${name}」`;
  }
  if (task) {
    const number = task.task_number ? `${task.task_number} · ` : '';
    return `${number}${task.title}`;
  }
  if (request.request_type === 'COMMENT_DELETE') return '删除任务评论';
  if (request.request_type === 'TASK_DELETE') return '删除任务';
  if (request.request_type === 'TASK_RESTORE') return '恢复任务';
  return '协作请求';
}

function approvalChanges(
  request: TaskApprovalRequest,
  memberLabel: (userId: string) => string,
): ApprovalChange[] {
  const reviewSubmission = isTaskReviewSubmission(request);
  const entries = Object.entries(request.proposed_changes ?? {})
    .filter(([key]) => key !== 'review_submission');
  if (entries.length === 0) {
    return request.request_type === 'TASK_DELETE' ? [{ key: 'action', label: '操作', value: '删除任务' }]
      : request.request_type === 'TASK_RESTORE' ? [{ key: 'action', label: '操作', value: '恢复任务' }]
        : request.request_type === 'COMMENT_DELETE' ? [{ key: 'action', label: '操作', value: '删除评论' }]
          : [];
  }
  return entries.map(([key, value]) => ({
    key,
    label: CHANGE_LABELS[key] ?? humanizeKey(key),
    value: formatChangeValue(key, value, memberLabel, reviewSubmission),
  }));
}

function formatChangeValue(
  key: string,
  value: unknown,
  memberLabel: (userId: string) => string,
  reviewSubmission = false,
): string {
  if (value === null || value === undefined || value === '') return '清空';
  if (key === 'quadrant' && typeof value === 'string') return QUADRANT_LABELS[value] ?? value;
  if (key === 'target_status' || key === 'status') {
    return reviewSubmission ? '待验收' : taskStatusLabel(String(value));
  }
  if (key === 'current_handler_id' || key === 'handler_user_id' || key === 'resume_handler_id' || key === 'waiting_for_user_id') {
    return typeof value === 'string' ? memberLabel(value) : formatValue(value);
  }
  if (key === 'labels' && Array.isArray(value)) return value.length > 0 ? value.join('、') : '清空分类';
  if (key === 'due_at' || key === 'planned_start_at') return typeof value === 'string' ? formatDate(value) : formatValue(value);
  if (key === 'estimated_minutes' && typeof value === 'number') return `${value} 分钟`;
  return formatValue(value);
}

function formatDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(date);
}

function humanizeKey(key: string): string {
  return key.replace(/_/g, ' ');
}

function initialOf(label: string): string {
  return Array.from(label.trim())[0] ?? '?';
}

function fallbackMemberLabel(userId: string): string {
  return userId ? `成员 ${userId.slice(0, 6)}` : '未命名成员';
}

function requestTypeLabel(request: TaskApprovalRequest, reviewSubmission = false): string {
  const type = request.request_type;
  if (reviewSubmission) return '任务验收';
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
  return labels[type] ?? '其他协作请求';
}

function isTaskReviewSubmission(request: TaskApprovalRequest): boolean {
  return request.request_type === 'STATUS_UPDATE'
    && request.proposed_changes?.review_submission === true
    && request.proposed_changes?.target_status === 'DONE';
}

function statusLabel(status: TaskApprovalRequest['status']): string {
  const labels: Record<TaskApprovalRequest['status'], string> = {
    PENDING: '待处理',
    APPROVED: '已批准',
    REJECTED: '已拒绝',
    CONFLICTED: '已失效',
    CANCELLED: '已撤回',
  };
  return labels[status] ?? '未知状态';
}
