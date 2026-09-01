import { X } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type JSX } from 'react';
import type { TaskApprovalRequest, TaskComment, TaskItem } from '../../api/types';
import type { WorkspaceSyncState } from '../../sync/workspace-sync';
import type { TaskConflict } from '../../tasks/task-model';
import type { TaskDetailActions } from '../../ui/task-detail-view';
import { Button } from '../ui/Button';
import { IconButton } from '../ui/IconButton';
import { TaskTimeline, type ActivityEvent } from './TaskTimeline';
import { TaskEditForm, type TaskMember } from './TaskEditForm';
import { ConflictPanel } from '../conflicts/ConflictPanel';

export interface TaskDetailPanelProps {
  task: TaskItem;
  members: TaskMember[];
  syncState: WorkspaceSyncState;
  actions: TaskDetailActions;
  onClose: () => void;
  activity?: ActivityEvent[];
}

type PanelAction = 'comment' | 'delay' | 'delete-comment' | 'conflict';

export function TaskDetailPanel({ task, members, syncState, actions, onClose, activity = [] }: TaskDetailPanelProps): JSX.Element {
  const dialogRef = useRef<HTMLElement>(null);
  const busyRef = useRef<Set<PanelAction>>(new Set());
  const [busyActions, setBusyActions] = useState<Set<PanelAction>>(() => new Set());
  const [error, setError] = useState<string | null>(null);
  const [commentBody, setCommentBody] = useState('');
  const [newDueAt, setNewDueAt] = useState('');
  const [delayReason, setDelayReason] = useState('NO_TIME');
  const [delayNote, setDelayNote] = useState('');

  const mode = typeof window !== 'undefined' && window.innerWidth < 1024 ? 'bottom-sheet' : 'drawer';
  const canWrite = actions.canWrite !== false;
  const comments = useMemo(() => getTaskComments(task.id, syncState, actions), [actions, syncState, task.id]);
  const approvals = useMemo(() => getTaskApprovals(task.id, syncState), [syncState, task.id]);
  const conflicts = useMemo(() => syncState.conflicts.filter((item) => item.task_id === task.id), [syncState.conflicts, task.id]);

  useEffect(() => {
    dialogRef.current?.focus();
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const setActionBusy = (action: PanelAction, busy: boolean): void => {
    if (busy) busyRef.current.add(action);
    else busyRef.current.delete(action);
    setBusyActions(new Set(busyRef.current));
  };

  const run = useCallback((action: PanelAction, operation: () => Promise<unknown>, onSuccess?: (value: unknown) => void): void => {
    if (busyRef.current.has(action)) return;
    setActionBusy(action, true);
    setError(null);
    void Promise.resolve()
      .then(operation)
      .then((value) => onSuccess?.(value))
      .catch((cause: unknown) => setError(errorMessage(cause)))
      .finally(() => setActionBusy(action, false));
  }, []);

  const addComment = (): void => {
    const body = commentBody.trim();
    if (!body || !canWrite) return;
    run('comment', () => actions.onComment(body), (value) => {
      setCommentBody('');
      if (isPendingApproval(value)) setError('评论已提交，等待负责人审批');
    });
  };

  const submitDelay = (): void => {
    if (!newDueAt || !canWrite || !isOwner(task, actions)) return;
    const date = new Date(newDueAt);
    if (!Number.isFinite(date.getTime())) {
      setError('请输入有效的新截止时间。');
      return;
    }
    run('delay', () => actions.onDelay(date.toISOString(), delayReason, delayNote.trim() || undefined), (value) => {
      setNewDueAt('');
      setDelayNote('');
      if (isPendingApproval(value)) setError('延期已提交，等待负责人审批');
    });
  };

  const resolveConflict = (conflictId: string, resolution: 'current' | 'proposed'): void => {
    if (!actions.onResolveConflict) return;
    run('conflict', () => actions.onResolveConflict!(conflictId, resolution));
  };

  const deleteComment = (comment: TaskComment): void => {
    if (!actions.onDeleteComment || !canDeleteComment(comment, task, actions)) return;
    run('delete-comment', () => actions.onDeleteComment!(comment.id, comment.version), (value) => {
      if (isPendingApproval(value)) setError('评论删除已提交，等待作者审批');
    });
  };

  return (
    <section
      className="task-detail-panel"
      data-panel-mode={mode}
      role="dialog"
      aria-label="任务详情"
      aria-modal="false"
      tabIndex={-1}
      ref={dialogRef}
    >
      <header className="task-detail-panel__header">
        <div className="task-detail-panel__heading">
          <p className="task-detail-panel__eyebrow">{task.task_number ? `任务编号：${task.task_number}` : '任务详情'}</p>
          <h2>{task.title}</h2>
        </div>
        <IconButton label="关闭任务详情" icon={<X size={18} strokeWidth={2} />} onClick={onClose} />
      </header>

      <div className="task-detail-panel__scroll">
        <div className="task-detail-panel__metadata">
          <span>负责人：{task.current_handler_id}</span>
          <span>{isOwner(task, actions) ? '当前用户是任务负责人' : '协作成员，修改将提交审批'}</span>
          {syncState.stale ? <span className="task-detail-panel__stale">内容可能不是最新</span> : null}
        </div>

        <TaskEditForm task={task} members={members} actions={actions} canWrite={canWrite} />

        {approvals.length > 0 ? (
          <section className="task-detail-section task-detail-approvals" aria-labelledby="task-detail-approvals-heading">
            <h3 id="task-detail-approvals-heading">审批</h3>
            <div className="task-detail-list">
              {approvals.map((approval) => <ApprovalSummary key={approval.id} approval={approval} />)}
            </div>
          </section>
        ) : (
          <section className="task-detail-section task-detail-approvals" aria-labelledby="task-detail-approvals-heading">
            <h3 id="task-detail-approvals-heading">审批</h3>
            <p className="task-detail-empty">暂无待处理审批</p>
          </section>
        )}

        <section className="task-detail-section task-detail-comments" aria-labelledby="task-detail-comments-heading">
          <h3 id="task-detail-comments-heading">评论</h3>
          {comments.length === 0 ? <p className="task-detail-empty">暂无评论</p> : (
            <div className="task-detail-list">
              {comments.map((comment) => (
                <article className={comment.deleted_at ? 'task-comment task-comment--deleted' : 'task-comment'} key={comment.id}>
                  <div className="task-comment__body">{comment.deleted_at ? '评论已删除' : comment.body}</div>
                  <div className="task-comment__meta">
                    <span>作者：{comment.author_user_id}</span>
                    {comment.deleted_at ? <span>删除时间：{comment.deleted_at}</span> : null}
                    {!comment.deleted_at && canDeleteComment(comment, task, actions) ? (
                      <Button
                        tone="quiet"
                        disabled={busyActions.has('delete-comment')}
                        onClick={() => deleteComment(comment)}
                      >
                        删除评论
                      </Button>
                    ) : null}
                  </div>
                </article>
              ))}
            </div>
          )}
          <div className="task-detail-inline-form">
            <label className="task-detail-field">
              <span>添加评论</span>
              <textarea
                aria-label="评论输入"
                value={commentBody}
                disabled={!canWrite}
                onChange={(event) => setCommentBody(event.target.value)}
              />
            </label>
            <Button tone="neutral" disabled={!canWrite || busyActions.has('comment') || !commentBody.trim()} onClick={addComment}>
              {busyActions.has('comment') ? '添加中…' : '添加评论'}
            </Button>
          </div>
        </section>

        <section className="task-detail-section task-detail-delay" aria-labelledby="task-detail-delay-heading">
          <h3 id="task-detail-delay-heading">延期</h3>
          <div className="task-detail-inline-form">
            <label className="task-detail-field">
              <span>新日期</span>
              <input
                aria-label="新截止时间"
                type="datetime-local"
                value={newDueAt}
                disabled={!canWrite || !isOwner(task, actions)}
                onChange={(event) => setNewDueAt(event.target.value)}
              />
            </label>
            <label className="task-detail-field">
              <span>原因</span>
              <select aria-label="延期原因" value={delayReason} disabled={!canWrite || !isOwner(task, actions)} onChange={(event) => setDelayReason(event.target.value)}>
                {delayReasons.map((reason) => <option key={reason} value={reason}>{reason}</option>)}
              </select>
            </label>
            <label className="task-detail-field">
              <span>说明</span>
              <input aria-label="延期说明" type="text" value={delayNote} disabled={!canWrite || !isOwner(task, actions)} onChange={(event) => setDelayNote(event.target.value)} />
            </label>
            <Button tone="neutral" disabled={!canWrite || !isOwner(task, actions) || busyActions.has('delay') || !newDueAt} onClick={submitDelay}>
              {busyActions.has('delay') ? '提交中…' : '提交延期'}
            </Button>
          </div>
        </section>

        {conflicts.length > 0 ? (
          <ConflictPanel conflicts={conflicts} busy={busyActions.has('conflict')} onResolve={resolveConflict} />
        ) : null}

        <TaskTimeline events={activity} />

        {error ? <p className="task-detail-error task-detail-error--panel" role="alert">{error}</p> : null}
        {syncState.error ? <p className="task-detail-error task-detail-error--sync" role="alert">{syncState.error}</p> : null}
      </div>
    </section>
  );
}

const delayReasons = ['NO_TIME', 'TOO_LARGE', 'NOT_WILLING', 'FORGOT', 'WAITING_PARTNER', 'INTERRUPTED', 'OTHER'];

function getTaskComments(taskId: string, syncState: WorkspaceSyncState, actions: TaskDetailActions): TaskComment[] {
  const source = actions.comments ?? syncState.comments ?? syncState.snapshot?.comments ?? [];
  return source.filter((comment) => comment.task_id === taskId).sort((left, right) => (left.created_at ?? '').localeCompare(right.created_at ?? ''));
}

function getTaskApprovals(taskId: string, syncState: WorkspaceSyncState): TaskApprovalRequest[] {
  const source = syncState.approvals ?? syncState.snapshot?.approval_requests ?? [];
  return source.filter((approval) => approval.task_id === taskId && approval.status === 'PENDING');
}

function isOwner(task: TaskItem, actions: TaskDetailActions): boolean {
  return !actions.currentUserId || actions.currentUserId === task.current_handler_id;
}

function canDeleteComment(comment: TaskComment, task: TaskItem, actions: TaskDetailActions): boolean {
  const viewerId = actions.currentUserId ?? task.current_handler_id;
  return actions.canWrite !== false
    && Boolean(actions.onDeleteComment)
    && (comment.author_user_id === viewerId || task.current_handler_id === viewerId);
}

function errorMessage(cause: unknown): string {
  return cause instanceof Error ? cause.message : '操作失败，请重试。';
}

function isPendingApproval(value: unknown): value is { pending: true } {
  return Boolean(value && typeof value === 'object' && 'pending' in value && (value as { pending?: unknown }).pending === true);
}

function displayApprovalValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '未设置';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function ApprovalSummary({ approval }: { approval: TaskApprovalRequest }): JSX.Element {
  const changes = Object.entries(approval.proposed_changes)
    .map(([field, value]) => `${field}：${displayApprovalValue(value)}`)
    .join('，');
  return (
    <article className="task-approval-summary">
      <strong>{approval.requester_id} 提议更新</strong>
      <span>{changes || '有一项待确认的任务变更'}</span>
    </article>
  );
}
