import { Check } from 'lucide-react';
import { useId, type JSX, type KeyboardEvent } from 'react';
import type { TaskItem } from '../../api/types';
import { Button } from '../ui/Button';
import { TaskMeta } from './TaskMeta';
import { TaskStatusLabel, taskStatusText } from './TaskStatusLabel';

export interface TaskRowProps {
  task: TaskItem;
  onOpen: (task: TaskItem) => void;
  onComplete: (task: TaskItem) => void;
  busy: boolean;
}

export function TaskRow({ task, onOpen, onComplete, busy }: TaskRowProps): JSX.Element {
  const titleId = useId();
  const metaId = useId();
  const completeDisabled = busy || task.status === 'DONE' || task.status === 'CANCELLED';

  const openFromKeyboard = (event: KeyboardEvent<HTMLDivElement>): void => {
    if (event.target !== event.currentTarget) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      onOpen(task);
    }
  };

  return (
    <article
      className="task-row"
      data-task-row={task.id}
    >
      <Button
        className="task-row__complete"
        tone="quiet"
        disabled={completeDisabled}
        aria-label="完成"
        title={`完成：${task.title}`}
        onClick={(event) => {
          event.stopPropagation();
          onComplete(task);
        }}
      >
        <Check aria-hidden="true" size={16} strokeWidth={2} />
        <span>完成</span>
      </Button>

      <div
        className="task-row__open task-row__body"
        role="button"
        tabIndex={0}
        aria-labelledby={titleId}
        aria-describedby={metaId}
        onClick={() => onOpen(task)}
        onKeyDown={openFromKeyboard}
      >
        <h3 className="task-row__title" id={titleId}>{task.title}</h3>
        <div id={metaId}>
          <TaskMeta task={task} />
        </div>
      </div>

      <div className="task-row__status" aria-label={`任务状态：${taskStatusText(task.status)}`}>
        <TaskStatusLabel status={task.status} />
      </div>
    </article>
  );
}
