import { useEffect, useRef, useState, type FormEvent, type JSX } from 'react';
import type { AppliedTaskWriteResult } from '../../api/client';
import type { CanonicalTaskStatus, TaskItem, TaskStatus } from '../../api/types';
import type { TaskDetailActions } from '../../tasks/task-detail-actions';
import { isCanonicalTaskStatus, isTaskQuadrant, isTaskTransitionAllowed, normalizeTaskStatus, parseTaskLabels, parseTaskLabelsInput, taskTransitionTargets, TASK_QUADRANTS, type EditableTaskChanges } from '../../tasks/task-model';
import { Button } from '../ui/Button';

export interface TaskMember {
  user_id: string;
  member_slot: number;
  membership_status?: string;
  status?: string;
}

export interface TaskEditFormProps {
  task: TaskItem;
  members: TaskMember[];
  actions: Pick<TaskDetailActions, 'onSave' | 'onTransition' | 'currentUserId'>;
  canWrite?: boolean;
}

type DraftField = 'title' | 'description' | 'status' | 'currentHandler' | 'dueAt' | 'quadrant' | 'labels' | 'blockedReason' | 'resumeHandler' | 'reviewRejectionReason' | 'progress';

interface TaskDraft {
  title: string;
  description: string;
  status: TaskStatus;
  currentHandler: string;
  dueAt: string;
  quadrant: TaskItem['quadrant'] | '';
  labels: string;
  blockedReason: string;
  resumeHandler: string;
  reviewRejectionReason: string;
  progress: string;
}

const progressValues = [20, 40, 60, 80];

export function TaskEditForm({ task, members, actions, canWrite = true }: TaskEditFormProps): JSX.Element {
  const [draft, setDraft] = useState<TaskDraft>(() => createDraft(task));
  const [error, setError] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<'save' | 'transition' | null>(null);
  const dirtyFields = useRef<Set<DraftField>>(new Set());
  const draftRef = useRef<TaskDraft>(draft);
  const busyActionRef = useRef<'save' | 'transition' | null>(null);
  const actorUserId = actions.currentUserId;

  useEffect(() => {
    setDraft((current) => {
      const next = createDraft(task);
      preserveDirtyFields(next, current, dirtyFields.current);
      draftRef.current = next;
      return next;
    });
  }, [task]);

  const updateDraft = <K extends DraftField>(field: K, value: TaskDraft[K]): void => {
    dirtyFields.current.add(field);
    setDraft((current) => {
      const next = { ...current, [field]: value };
      draftRef.current = next;
      return next;
    });
  };

  const run = (action: 'save' | 'transition', operation: () => Promise<unknown>, onSuccess?: (value: unknown) => void): void => {
    if (busyActionRef.current !== null || !canWrite) return;
    busyActionRef.current = action;
    setBusyAction(action);
    setError(null);
    void Promise.resolve()
      .then(operation)
      .then((value) => onSuccess?.(value))
      .catch((cause: unknown) => setError(errorMessage(cause)))
      .finally(() => {
        busyActionRef.current = null;
        setBusyAction(null);
      });
  };

  const save = (): void => {
    const activeHandlerIds = getActiveHandlerIds(members);
    if (draft.currentHandler !== task.current_handler_id && !activeHandlerIds.has(draft.currentHandler)) {
      setError('请选择有效的负责人。');
      return;
    }
    if (!isTaskQuadrant(draft.quadrant)) {
      setError('请选择有效四象限。');
      return;
    }

    let labels: string[];
    try {
      labels = draft.labels.trim() === '' ? [] : parseTaskLabelsInput(draft.labels);
    } catch (cause) {
      setError(errorMessage(cause));
      return;
    }

    const changes: EditableTaskChanges = {
      title: draft.title.trim(),
      description: draft.description,
    };
    if (draft.dueAt !== toDateTimeLocalValue(task.due_at)) {
      changes.due_at = draft.dueAt === '' ? null : toIsoDate(draft.dueAt);
    }
    if (draft.currentHandler !== task.current_handler_id) changes.current_handler_id = draft.currentHandler;
    if (draft.quadrant !== task.quadrant) changes.quadrant = draft.quadrant;

    const currentLabels = safeLabels(task.labels);
    if (labels.length !== currentLabels.length || labels.some((value, index) => value !== currentLabels[index])) {
      changes.labels = labels;
    }
    if (task.status === 'IN_PROGRESS' && Number(draft.progress) !== (task.progress ?? 20)) {
      changes.progress = Number(draft.progress);
    }

    const submittedDraft = draft;
    const submittedFields = fieldsForChanges(changes).filter((field) => dirtyFields.current.has(field));
    run('save', () => actions.onSave(changes), (value) => {
      if (isPendingApproval(value)) {
        setError('等待负责人审批');
      } else if (isAppliedWriteResult(value, task.id)) {
        clearDirtyFields(dirtyFields.current, draftRef.current, submittedDraft, submittedFields);
      } else {
        setError('保存未确认，请检查同步状态后重试。');
      }
    });
  };

  const transition = (): void => {
    const activeHandlerIds = getActiveHandlerIds(members);
    const taskStatus = normalizeTaskStatus(task.status);
    if (!isTaskTransitionAllowed(task, draft.status, actorUserId)) {
      setError('当前用户不能执行该状态操作。');
      return;
    }
    const isBlockedRecovery = taskStatus === 'BLOCKED' && draft.status === 'IN_PROGRESS';
    const isReviewReturn = taskStatus === 'REVIEW' && draft.status === 'IN_PROGRESS';
    if (draft.status === 'BLOCKED' && (!draft.blockedReason.trim() || !draft.resumeHandler)) {
      setError('进入阻塞状态需要阻塞原因和恢复负责人。');
      return;
    }
    if (isReviewReturn && !draft.reviewRejectionReason.trim()) {
      setError('退回待验收任务需要填写退回原因。');
      return;
    }
    if ((draft.status === 'BLOCKED' || isBlockedRecovery) && !activeHandlerIds.has(draft.resumeHandler)) {
      setError('请选择有效的恢复负责人。');
      return;
    }

    const payload = {
      ...(draft.blockedReason.trim() ? { blockedReason: draft.blockedReason.trim() } : {}),
      ...(draft.resumeHandler && (draft.status === 'BLOCKED' || isBlockedRecovery)
        ? { resumeHandlerId: draft.resumeHandler }
        : {}),
      ...(isReviewReturn ? { reviewRejectionReason: draft.reviewRejectionReason.trim() } : {}),
    };
    const submittedDraft = draft;
    const submittedFields: DraftField[] = ['status'];
    if ('blockedReason' in payload) submittedFields.push('blockedReason');
    if ('resumeHandlerId' in payload) submittedFields.push('resumeHandler');
    if ('reviewRejectionReason' in payload) submittedFields.push('reviewRejectionReason');
    const dirtySubmittedFields = submittedFields.filter((field) => dirtyFields.current.has(field));

    run('transition', () => Object.keys(payload).length === 0
      ? actions.onTransition(draft.status)
      : actions.onTransition(draft.status, payload), (value) => {
      if (isPendingApproval(value)) {
        setError('等待负责人审批');
      } else if (isAppliedWriteResult(value, task.id)) {
        clearDirtyFields(dirtyFields.current, draftRef.current, submittedDraft, dirtySubmittedFields);
      } else {
        setError('状态更新未确认，请检查同步状态后重试。');
      }
    });
  };

  const onSubmit = (event: FormEvent<HTMLFormElement>): void => {
    event.preventDefault();
    save();
  };

  const handlerOptions = getHandlerOptions(task, members, [draft.currentHandler, draft.resumeHandler]);
  const taskStatus = normalizeTaskStatus(task.status);
  const currentStatus = isCanonicalTaskStatus(taskStatus) ? taskStatus : undefined;
  const transitionStatuses = taskTransitionTargets(task, actorUserId);
  const transitionDisabled = !canWrite || busyAction !== null;
  const showBlockedFields = draft.status === 'BLOCKED' || taskStatus === 'BLOCKED';
  const showReviewReturnReason = taskStatus === 'REVIEW' && draft.status === 'IN_PROGRESS';
  const showProgress = draft.status === 'IN_PROGRESS' || task.status === 'IN_PROGRESS';

  return (
    <form className="task-edit-form" onSubmit={onSubmit}>
      <div className="task-edit-form__priority" aria-label="任务重点字段">
        <label className="task-detail-field">
          <span>标题</span>
          <input
            aria-label="标题"
            type="text"
            value={draft.title}
            disabled={!canWrite}
            onChange={(event) => updateDraft('title', event.target.value)}
          />
        </label>

        <label className="task-detail-field">
          <span>描述</span>
          <textarea
            aria-label="描述"
            value={draft.description}
            disabled={!canWrite}
            onChange={(event) => updateDraft('description', event.target.value)}
          />
        </label>

        <div className="task-edit-form__row">
          <label className="task-detail-field">
            <span>状态</span>
            <select
              aria-label="状态"
              value={draft.status}
              disabled={!canWrite}
              onChange={(event) => updateDraft('status', event.target.value as TaskStatus)}
            >
              {currentStatus ? <option value={currentStatus} disabled>{statusLabel(currentStatus)}</option> : null}
              {transitionStatuses.map((status) => <option key={status} value={status}>{statusLabel(status)}</option>)}
            </select>
          </label>
        </div>

        <label className="task-detail-field">
          <span>负责人</span>
          <select
            aria-label="负责人"
            value={draft.currentHandler}
            disabled={!canWrite}
            onChange={(event) => updateDraft('currentHandler', event.target.value)}
          >
            {handlerOptions.map((option) => (
              <option key={option.id} value={option.id} disabled={!option.active}>{option.id}</option>
            ))}
          </select>
        </label>

        <label className="task-detail-field">
          <span>截止</span>
          <input
            aria-label="截止时间"
            type="datetime-local"
            value={draft.dueAt}
            disabled={!canWrite}
            onChange={(event) => updateDraft('dueAt', event.target.value)}
          />
          <small className="task-detail-field__hint">{task.due_at ? `已设 ${formatDueDate(task.due_at)}` : '尚未设置'}</small>
        </label>
      </div>

      <div className="task-edit-form__secondary">
        <label className="task-detail-field">
          <span>四象限</span>
          <select
            aria-label="四象限"
            value={draft.quadrant}
            disabled={!canWrite}
            onChange={(event) => updateDraft('quadrant', event.target.value as TaskDraft['quadrant'])}
          >
            <option value="">未设置</option>
            {TASK_QUADRANTS.map((quadrant) => <option key={quadrant} value={quadrant}>{quadrant}</option>)}
          </select>
        </label>

        <label className="task-detail-field">
          <span>标签</span>
          <input
            aria-label="标签"
            type="text"
            value={draft.labels}
            disabled={!canWrite}
            onChange={(event) => updateDraft('labels', event.target.value)}
          />
        </label>

          {showBlockedFields ? (
          <>
            <label className="task-detail-field">
              <span>阻塞原因</span>
              <input
                aria-label="阻塞原因"
                type="text"
                value={draft.blockedReason}
                disabled={!canWrite}
                onChange={(event) => updateDraft('blockedReason', event.target.value)}
              />
            </label>
            <label className="task-detail-field">
              <span>恢复负责人</span>
              <select
                aria-label="恢复负责人"
                value={draft.resumeHandler}
                disabled={!canWrite}
                onChange={(event) => updateDraft('resumeHandler', event.target.value)}
              >
                <option value="">请选择</option>
                {handlerOptions.map((option) => (
                  <option key={option.id} value={option.id} disabled={!option.active}>{option.id}</option>
                ))}
              </select>
            </label>
          </>
        ) : null}

        {showProgress ? (
          <label className="task-detail-field">
            <span>进度</span>
            <select
              aria-label="进度"
              value={draft.progress}
              disabled={!canWrite}
              onChange={(event) => updateDraft('progress', event.target.value)}
            >
              {progressValues.map((value) => <option key={value} value={value}>{value}%</option>)}
            </select>
          </label>
        ) : null}

        {showReviewReturnReason ? (
          <label className="task-detail-field">
            <span>退回原因</span>
            <input
              aria-label="退回原因"
              type="text"
              value={draft.reviewRejectionReason}
              disabled={!canWrite}
              onChange={(event) => updateDraft('reviewRejectionReason', event.target.value)}
            />
          </label>
        ) : null}
      </div>

      <div className="task-edit-form__actions">
        <Button tone="primary" type="submit" disabled={!canWrite || busyAction !== null}>
          {busyAction === 'save' ? '保存中…' : '保存'}
        </Button>
        <Button tone="neutral" type="button" disabled={transitionDisabled} onClick={transition}>
          {busyAction === 'transition' ? '更新中…' : '更新状态'}
        </Button>
      </div>
      {error ? <p className="task-detail-error" role="alert">{error}</p> : null}
    </form>
  );
}

function createDraft(task: TaskItem): TaskDraft {
  return {
    title: task.title,
    description: task.description,
    status: normalizeTaskStatus(task.status) as TaskStatus,
    currentHandler: task.current_handler_id,
    dueAt: toDateTimeLocalValue(task.due_at),
    quadrant: isTaskQuadrant(task.quadrant) ? task.quadrant : '',
    labels: safeLabels(task.labels).join(', '),
    blockedReason: task.blocked_reason ?? '',
    resumeHandler: task.resume_handler_id ?? task.current_handler_id,
    reviewRejectionReason: '',
    progress: String(task.progress ?? 20),
  };
}

function preserveDirtyFields(next: TaskDraft, current: TaskDraft, dirtyFields: Set<DraftField>): void {
  if (dirtyFields.has('title')) next.title = current.title;
  if (dirtyFields.has('description')) next.description = current.description;
  if (dirtyFields.has('status')) next.status = current.status;
  if (dirtyFields.has('currentHandler')) next.currentHandler = current.currentHandler;
  if (dirtyFields.has('dueAt')) next.dueAt = current.dueAt;
  if (dirtyFields.has('quadrant')) next.quadrant = current.quadrant;
  if (dirtyFields.has('labels')) next.labels = current.labels;
  if (dirtyFields.has('blockedReason')) next.blockedReason = current.blockedReason;
  if (dirtyFields.has('resumeHandler')) next.resumeHandler = current.resumeHandler;
  if (dirtyFields.has('reviewRejectionReason')) next.reviewRejectionReason = current.reviewRejectionReason;
  if (dirtyFields.has('progress')) next.progress = current.progress;
}

function clearDirtyFields(
  dirtyFields: Set<DraftField>,
  currentDraft: TaskDraft,
  submittedDraft: TaskDraft,
  fields: DraftField[],
): void {
  for (const field of fields) {
    if (Object.is(currentDraft[field], submittedDraft[field])) dirtyFields.delete(field);
  }
}

function fieldsForChanges(changes: EditableTaskChanges): DraftField[] {
  const fields: DraftField[] = [];
  if ('title' in changes) fields.push('title');
  if ('description' in changes) fields.push('description');
  if ('due_at' in changes) fields.push('dueAt');
  if ('current_handler_id' in changes) fields.push('currentHandler');
  if ('quadrant' in changes) fields.push('quadrant');
  if ('labels' in changes) fields.push('labels');
  if ('progress' in changes) fields.push('progress');
  return fields;
}

interface HandlerOption {
  id: string;
  active: boolean;
}

function getHandlerOptions(task: TaskItem, members: TaskMember[], draftHandlerIds: string[]): HandlerOption[] {
  const activeIds = [...getActiveHandlerIds(members)];
  const candidates = [...activeIds, task.current_handler_id, task.resume_handler_id ?? '', ...draftHandlerIds];
  return [...new Set(candidates.filter(Boolean))].map((id) => ({
    id,
    active: activeIds.includes(id),
  }));
}

function getActiveHandlerIds(members: TaskMember[]): Set<string> {
  return new Set(members.filter(isActiveMember).map((member) => member.user_id));
}

function isActiveMember(member: TaskMember): boolean {
  const status = member.membership_status ?? member.status;
  return status === undefined || status === 'ACTIVE';
}

function safeLabels(value: unknown): string[] {
  try {
    return value === undefined ? [] : parseTaskLabels(value);
  } catch {
    return [];
  }
}

function toDateTimeLocalValue(value: string | null): string {
  if (!value) return '';
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return value.slice(0, 16);
  const date = new Date(timestamp);
  const pad = (part: number): string => String(part).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function toIsoDate(value: string): string {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : value;
}

function formatDueDate(value: string): string {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString().slice(0, 10) : value;
}

function statusLabel(status: TaskStatus): string {
  const labels: Record<CanonicalTaskStatus, string> = {
    TODO: '待进行',
    IN_PROGRESS: '进行中',
    BLOCKED: '阻塞中',
    REVIEW: '待验收',
    DONE: '已完成',
    CANCELLED: '已取消',
  };
  return labels[status as CanonicalTaskStatus] ?? status;
}

function errorMessage(cause: unknown): string {
  return cause instanceof Error ? cause.message : '操作失败，请重试。';
}

function isPendingApproval(value: unknown): value is { pending: true } {
  return Boolean(value && typeof value === 'object' && 'pending' in value && (value as { pending?: unknown }).pending === true);
}

function isAppliedWriteResult(value: unknown, taskId: string): value is AppliedTaskWriteResult {
  if (!value || typeof value !== 'object') return false;
  const result = value as { id?: unknown; cursor?: unknown; pending?: unknown };
  return result.pending !== true
    && result.id === taskId
    && typeof result.cursor === 'number'
    && Number.isFinite(result.cursor);
}
