import type { CanonicalTaskStatus, TaskApprovalRequest, TaskItem, TaskStatus } from '../api/types';
import { isCanonicalTaskStatus, normalizeTaskStatus } from './task-model';

export const TASK_STATUSES: CanonicalTaskStatus[] = ['TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW', 'DONE', 'CANCELLED'];

export interface TodayModel {
  focus: TaskItem | null;
  next: TaskItem[];
  blocked: TaskItem[];
  pendingApprovals: TaskApprovalRequest[];
}

export function filterMyTasks(tasks: TaskItem[], userId: string): TaskItem[] {
  return tasks.filter((task) => task.current_handler_id === userId);
}

export function groupTasksByStatus(tasks: TaskItem[]): Record<CanonicalTaskStatus, TaskItem[]> {
  const groups = Object.fromEntries(TASK_STATUSES.map((status) => [status, [] as TaskItem[]])) as Record<CanonicalTaskStatus, TaskItem[]>;
  for (const task of tasks) {
    const status = normalizeTaskStatus(task.status);
    if (isCanonicalTaskStatus(status)) groups[status].push(task);
  }
  return groups;
}

export function deriveTaskSummary(tasks: TaskItem[], now = new Date()) {
  const cutoff = now.getTime() + 24 * 60 * 60 * 1000;
  const active = tasks.filter((task) => !isTerminalTask(task.status));
  return {
    mine: tasks.length,
    blocked: tasks.filter((task) => isBlockedStatus(task.status)).length,
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

  const blocked = visibleTasks.filter((task) => isBlockedStatus(task.status));
  const next = visibleTasks
    .filter((task) => task.id !== focusId && !isBlockedStatus(task.status) && !isTerminalTask(task.status))
    .sort(compareDueDates)
    .slice(0, 8);
  const pendingApprovals = approvals.filter((approval) => approval.status === 'PENDING' && approval.approver_id === viewerId);

  return { focus, next, blocked, pendingApprovals };
}

function belongsToViewer(task: TaskItem, viewerId: string): boolean {
  return task.current_handler_id === viewerId;
}

function isTerminalTask(status: TaskStatus): boolean {
  const normalized = normalizeTaskStatus(status);
  return normalized === 'DONE' || normalized === 'CANCELLED';
}

function isBlockedStatus(status: unknown): boolean {
  return status === 'BLOCKED' || status === 'WAITING';
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
