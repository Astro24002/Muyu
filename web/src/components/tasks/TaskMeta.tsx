import type { JSX } from 'react';
import type { TaskItem } from '../../api/types';
import { normalizedTaskStatus } from '../../tasks/task-status';

export interface TaskMetaProps {
  task: TaskItem;
  now?: Date;
  className?: string;
}

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1000;

export function TaskMeta({ task, now = new Date(), className }: TaskMetaProps): JSX.Element {
  const dueState = getDueState(task, now);
  const labels = task.labels.length > 0 ? `标签：${task.labels.join('、')}` : null;
  const progress = normalizedTaskStatus(task.status) === 'IN_PROGRESS' && task.progress !== null && task.progress !== undefined
    ? `进度 ${task.progress}%`
    : null;

  return (
    <div className={['task-meta', className].filter(Boolean).join(' ')} data-task-meta>
      <span>负责人：{task.current_handler_id}</span>
      <span>四象限：{task.quadrant}</span>
      {labels ? <span>{labels}</span> : null}
      {progress ? <span>{progress}</span> : null}
      <time className="task-meta__date" data-task-date={task.due_at ?? undefined} dateTime={task.due_at ?? undefined}>
        {task.due_at ? `截止 ${formatTaskDate(task.due_at)}` : '未设置截止时间'}
      </time>
      {dueState ? <span className={`task-meta__due task-meta__due--${dueState}`}>{dueState === 'overdue' ? '已过期' : '临期'}</span> : null}
      {normalizedTaskStatus(task.status) === 'BLOCKED' ? <span>阻塞：{task.blocked_reason ?? '未说明'}</span> : null}
    </div>
  );
}

export function formatTaskDate(value: string): string {
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return value;
  return new Date(timestamp).toISOString().slice(0, 10);
}

function getDueState(task: TaskItem, now: Date): 'overdue' | 'soon' | null {
  const status = normalizedTaskStatus(task.status);
  if (!task.due_at || status === 'DONE' || status === 'CANCELLED') return null;
  const due = Date.parse(task.due_at);
  const current = now.getTime();
  if (!Number.isFinite(due) || !Number.isFinite(current)) return null;
  if (due < current) return 'overdue';
  if (due <= current + DAY_IN_MILLISECONDS) return 'soon';
  return null;
}
