import type { TaskItem } from '../api/types';

export type EditableTaskChanges = Pick<Partial<TaskItem>,
  | 'title'
  | 'description'
  | 'due_at'
  | 'planned_start_at'
  | 'estimated_minutes'
  | 'quadrant'
  | 'progress'
  | 'assignee_ids'
  | 'current_handler_id'
>;

export interface TaskConflict {
  id: string;
  task_id: string;
  field: string;
  base?: unknown;
  current?: unknown;
  proposed?: unknown;
  status?: string;
}

export function upsertTask(tasks: TaskItem[], task: TaskItem): TaskItem[] {
  const index = tasks.findIndex((item) => item.id === task.id);
  if (task.deleted_at !== null) return tasks.filter((item) => item.id !== task.id);
  if (index === -1) return [...tasks, task];
  return tasks.map((item) => item.id === task.id ? task : item);
}
