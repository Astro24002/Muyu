import type { JSX } from 'react';
import type { TaskStatus } from '../../api/types';
import { normalizedTaskStatus, statusLabel, statusTone } from '../../tasks/task-status';

export interface TaskStatusLabelProps {
  status: TaskStatus;
  className?: string;
}

export function TaskStatusLabel({ status, className }: TaskStatusLabelProps): JSX.Element {
  const displayStatus = normalizedTaskStatus(status);
  const tone = statusTone(status);
  return (
    <span
      className={['task-status-label', `task-status-label--${tone}`, className].filter(Boolean).join(' ')}
      data-task-status={displayStatus ?? 'UNKNOWN'}
    >
      {taskStatusText(status)}
    </span>
  );
}

export const taskStatusText = statusLabel;
