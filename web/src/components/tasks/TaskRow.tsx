import { Play, Send } from 'lucide-react';
import { useId, type JSX, type KeyboardEvent } from 'react';
import type { TaskItem } from '../../api/types';
import { Button } from '../ui/Button';
import { TaskMeta } from './TaskMeta';
import { TaskStatusLabel, taskStatusText } from './TaskStatusLabel';
import { normalizedTaskStatus } from '../../tasks/task-status';

export interface TaskRowProps {
  task: TaskItem;
  onOpen: (task: TaskItem) => void;
  onComplete: (task: TaskItem) => void;
  busy: boolean;
}

export function TaskRow({ task, onOpen, onComplete, busy }: TaskRowProps): JSX.Element {
  const titleId = useId();
  const metaId = useId();
  const action = primaryAction(task.status);

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
      {action ? (
        <Button
          className="task-row__complete"
          tone="quiet"
          disabled={busy}
          aria-label={action.label}
          title={`${action.label}：${task.title}`}
          onClick={(event) => {
            event.stopPropagation();
            onComplete(task);
          }}
        >
          <action.Icon aria-hidden="true" size={16} strokeWidth={2} />
          <span>{action.label}</span>
        </Button>
      ) : null}

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

function primaryAction(status: TaskItem['status']): { label: string; Icon: typeof Play } | null {
  switch (normalizedTaskStatus(status)) {
    case 'TODO':
      return { label: '开始', Icon: Play };
    case 'IN_PROGRESS':
      return { label: '提交验收', Icon: Send };
    default:
      return null;
  }
}
