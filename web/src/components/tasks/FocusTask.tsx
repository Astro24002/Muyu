import { ArrowRight } from 'lucide-react';
import type { JSX } from 'react';
import type { TaskItem } from '../../api/types';
import { Button } from '../ui/Button';
import { TaskMeta } from './TaskMeta';
import { TaskStatusLabel } from './TaskStatusLabel';

export interface FocusTaskProps {
  task: TaskItem;
  onContinue: (task: TaskItem) => void;
  busy: boolean;
}

export function FocusTask({ task, onContinue, busy }: FocusTaskProps): JSX.Element {
  return (
    <article className="focus-task" data-focus-task>
      <div className="focus-task__body">
        <p className="focus-task__eyebrow">继续上次的任务</p>
        <h2 className="focus-task__title">{task.title}</h2>
        {task.description ? <p className="focus-task__description">{task.description}</p> : null}
        <TaskMeta task={task} className="focus-task__meta" />
        <TaskStatusLabel status={task.status} />
      </div>
      <Button
        className="focus-task__action"
        tone="primary"
        disabled={busy}
        onClick={() => onContinue(task)}
      >
        <span>继续处理</span>
        <ArrowRight aria-hidden="true" size={16} strokeWidth={2} />
      </Button>
    </article>
  );
}
