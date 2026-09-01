import type { JSX } from 'react';
import type { TaskStatus } from '../../api/types';

export interface TaskStatusLabelProps {
  status: TaskStatus;
  className?: string;
}

const STATUS_LABELS: Record<TaskStatus, string> = {
  TODO: '待开始',
  IN_PROGRESS: '进行中',
  WAITING: '等待中',
  DONE: '已完成',
  CANCELLED: '已取消',
};

export function TaskStatusLabel({ status, className }: TaskStatusLabelProps): JSX.Element {
  return (
    <span
      className={['task-status-label', `task-status-label--${status.toLowerCase()}`, className].filter(Boolean).join(' ')}
      data-task-status={status}
    >
      {STATUS_LABELS[status]}
    </span>
  );
}

export function taskStatusText(status: TaskStatus): string {
  return STATUS_LABELS[status];
}
