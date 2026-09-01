import type { TaskApprovalRequest, TaskItem, TaskStatus } from '../api/types';

export const TASK_STATUSES: TaskStatus[] = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];

export interface TodayModel {
  focus: TaskItem | null;
  next: TaskItem[];
  waiting: TaskItem[];
  pendingApprovals: TaskApprovalRequest[];
}

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

export function deriveTodayModel(
  tasks: TaskItem[],
  approvals: TaskApprovalRequest[],
  viewerId: string,
  now: Date,
): TodayModel {
  // `now` is part of the selector contract so date-aware sections can evolve
  // without reading a clock. The current grouping only needs absolute dates.
  void now;

  const visibleTasks = tasks.filter((task) => !task.deleted_at);
  const focus = [...visibleTasks]
    .filter((task) => task.status === 'IN_PROGRESS' && belongsToViewer(task, viewerId))
    .sort(compareFocusTasks)[0] ?? null;
  const focusId = focus?.id;

  const waiting = visibleTasks.filter((task) => task.status === 'WAITING');
  const next = visibleTasks
    .filter((task) => task.id !== focusId && task.status !== 'WAITING' && !isTerminalTask(task.status))
    .sort(compareDueDates)
    .slice(0, 8);
  const pendingApprovals = approvals.filter((approval) => approval.status === 'PENDING' && approval.approver_id === viewerId);

  return { focus, next, waiting, pendingApprovals };
}

function belongsToViewer(task: TaskItem, viewerId: string): boolean {
  return task.current_handler_id === viewerId;
}

function isTerminalTask(status: TaskStatus): boolean {
  return status === 'DONE' || status === 'CANCELLED';
}

function compareFocusTasks(left: TaskItem, right: TaskItem): number {
  const leftUpdated = timestamp(left.updated_at) ?? Number.NEGATIVE_INFINITY;
  const rightUpdated = timestamp(right.updated_at) ?? Number.NEGATIVE_INFINITY;
  const updatedDifference = rightUpdated - leftUpdated;
  return updatedDifference || compareIds(left.id, right.id);
}

function compareDueDates(left: TaskItem, right: TaskItem): number {
  const leftDue = timestamp(left.due_at);
  const rightDue = timestamp(right.due_at);
  if (leftDue === null && rightDue !== null) return 1;
  if (leftDue !== null && rightDue === null) return -1;
  if (leftDue !== null && rightDue !== null && leftDue !== rightDue) return leftDue - rightDue;
  return compareIds(left.id, right.id);
}

function timestamp(value: string | null): number | null {
  if (value === null) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function compareIds(left: string, right: string): number {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}
