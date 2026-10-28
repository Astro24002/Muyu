import type { JSX } from 'react';
import type { TaskItem } from '../../api/types';
import { TaskRow } from './TaskRow';

export interface TaskListProps {
  tasks: TaskItem[];
  emptyMessage: string;
  onOpen: (task: TaskItem) => void;
  onComplete: (task: TaskItem) => void;
  busy: boolean;
  showPrimaryAction?: boolean;
}

export function TaskList({ tasks, emptyMessage, onOpen, onComplete, busy, showPrimaryAction = true }: TaskListProps): JSX.Element {
  if (tasks.length === 0) {
    return <p className="task-list__empty" data-task-list-empty role="status">{emptyMessage}</p>;
  }

  return (
    <div className="task-list" data-task-list>
      {tasks.map((task) => (
        <TaskRow key={task.id} task={task} onOpen={onOpen} onComplete={onComplete} busy={busy} showPrimaryAction={showPrimaryAction} />
      ))}
    </div>
  );
}
