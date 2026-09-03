import type { JSX } from 'react';
import type { CanonicalTaskStatus, TaskStatus } from '../../api/types';
import { isCanonicalTaskStatus, normalizeTaskStatus } from '../../tasks/task-model';

export interface TaskStatusLabelProps {
  status: TaskStatus;
  className?: string;
}

const STATUS_LABELS: Record<CanonicalTaskStatus, string> = {
  TODO: '待进行',
  IN_PROGRESS: '进行中',
  BLOCKED: '阻塞中',
  REVIEW: '待验收',
  DONE: '已完成',
  CANCELLED: '已取消',
};

export function TaskStatusLabel({ status, className }: TaskStatusLabelProps): JSX.Element {
  const normalized = normalizeTaskStatus(status);
  const displayStatus = isCanonicalTaskStatus(normalized) ? normalized : status;
  return (
    <span
      className={['task-status-label', `task-status-label--${displayStatus.toLowerCase()}`, className].filter(Boolean).join(' ')}
      data-task-status={displayStatus}
    >
      {taskStatusText(status)}
    </span>
  );
}

export function taskStatusText(status: TaskStatus): string {
  const normalized = normalizeTaskStatus(status);
  return isCanonicalTaskStatus(normalized)
    ? STATUS_LABELS[normalized]
    : String(normalized);
}
