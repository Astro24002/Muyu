import type { TaskItem, TaskStatus } from '../api/types';

export const TASK_STATUSES: TaskStatus[] = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];

export function filterMyTasks(tasks: TaskItem[], userId: string): TaskItem[] {
  return tasks.filter((task) => task.current_handler_id === userId);
}

export function groupTasksByStatus(tasks: TaskItem[]): Record<TaskStatus, TaskItem[]> {
  const groups = Object.fromEntries(TASK_STATUSES.map((status) => [status, [] as TaskItem[]])) as Record<TaskStatus, TaskItem[]>;
  for (const task of tasks) if (groups[task.status]) groups[task.status].push(task);
  return groups;
}

export function deriveTaskSummary(tasks: TaskItem[], now = new Date()) {
  const cutoff = now.getTime() + 24 * 60 * 60 * 1000;
  const active = tasks.filter((task) => task.status !== 'DONE' && task.status !== 'CANCELLED');
  return {
    mine: tasks.length,
    blocked: tasks.filter((task) => task.status === 'WAITING').length,
    dueSoon: active.filter((task) => { const due = task.due_at ? Date.parse(task.due_at) : NaN; return due >= now.getTime() && due <= cutoff; }).length,
    overdue: active.filter((task) => task.due_at !== null && Date.parse(task.due_at) < now.getTime()).length,
    openConflicts: 0,
  };
}
