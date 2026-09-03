import type { CanonicalTaskStatus, HomeResponse, TaskApprovalRequest, TaskItem, TaskStatus } from '../api/types';
import { isCanonicalTaskStatus, normalizeTaskStatus } from './task-model';

export const TASK_STATUSES: CanonicalTaskStatus[] = ['TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW', 'DONE', 'CANCELLED'];

export interface TodayModel {
  focus: TaskItem | null;
  next: TaskItem[];
  blocked: TaskItem[];
  review: TaskItem[];
  pendingApprovals: TaskApprovalRequest[];
  pendingApprovalCount: number;
  currentHasMore: boolean;
  blockedHasMore: boolean;
  reviewHasMore: boolean;
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
  home?: HomeResponse | null,
): TodayModel {
  if (home) return deriveAuthoritativeTodayModel(home);

  const visibleTasks = tasks.filter((task) => !task.deleted_at);
  const current = visibleTasks
    .filter((task) => belongsToViewer(task, viewerId) && isCurrentStatus(task.status))
    .sort((left, right) => compareActionTasks(left, right, now))
    .slice(0, 5);
  const focus = current.find((task) => normalizeTaskStatus(task.status) === 'IN_PROGRESS') ?? null;
  const focusId = focus?.id;
  const blocked = visibleTasks
    .filter((task) => belongsToViewer(task, viewerId) && isBlockedStatus(task.status))
    .sort((left, right) => compareBlockedTasks(left, right, now))
    .slice(0, 3);
  const review = visibleTasks
    .filter((task) => task.reviewer_user_id === viewerId && normalizeTaskStatus(task.status) === 'REVIEW')
    .sort((left, right) => compareActionTasks(left, right, now))
    .slice(0, 3);
  const next = current.filter((task) => task.id !== focusId);
  const pendingApprovals = approvals.filter((approval) => approval.status === 'PENDING' && approval.approver_id === viewerId);

  return {
    focus,
    next,
    blocked,
    review,
    pendingApprovals,
    pendingApprovalCount: pendingApprovals.length,
    currentHasMore: false,
    blockedHasMore: false,
    reviewHasMore: false,
  };
}

function deriveAuthoritativeTodayModel(home: HomeResponse): TodayModel {
  const current = home.current_tasks.items;
  const focus = current.find((task) => normalizeTaskStatus(task.status) === 'IN_PROGRESS') ?? null;
  const focusId = focus?.id;

  return {
    focus,
    next: current.filter((task) => task.id !== focusId),
    blocked: home.blocked_tasks.items,
    review: home.review_tasks.items,
    pendingApprovals: [],
    pendingApprovalCount: home.pending_approval_count,
    currentHasMore: home.current_tasks.has_more,
    blockedHasMore: home.blocked_tasks.has_more,
    reviewHasMore: home.review_tasks.has_more,
  };
}

function belongsToViewer(task: TaskItem, viewerId: string): boolean {
  return task.current_handler_id === viewerId;
}

function isTerminalTask(status: TaskStatus): boolean {
  const normalized = normalizeTaskStatus(status);
  return normalized === 'DONE' || normalized === 'CANCELLED';
}

function isCurrentStatus(status: TaskStatus): boolean {
  const normalized = normalizeTaskStatus(status);
  return normalized === 'TODO' || normalized === 'IN_PROGRESS';
}

function isBlockedStatus(status: unknown): boolean {
  return status === 'BLOCKED' || status === 'WAITING';
}

function compareUpdatedTasks(left: TaskItem, right: TaskItem): number {
  const leftUpdated = timestamp(left.updated_at) ?? Number.NEGATIVE_INFINITY;
  const rightUpdated = timestamp(right.updated_at) ?? Number.NEGATIVE_INFINITY;
  const updatedDifference = rightUpdated - leftUpdated;
  return updatedDifference || compareIds(left.id, right.id);
}

function compareActionTasks(left: TaskItem, right: TaskItem, now: Date): number {
  return compareDueUrgency(left, right, now) || compareUpdatedTasks(left, right);
}

function compareBlockedTasks(left: TaskItem, right: TaskItem, now: Date): number {
  const urgency = compareDueUrgency(left, right, now);
  if (urgency) return urgency;
  const leftBlocked = timestamp(left.blocked_since);
  const rightBlocked = timestamp(right.blocked_since);
  if (leftBlocked === null && rightBlocked !== null) return 1;
  if (leftBlocked !== null && rightBlocked === null) return -1;
  if (leftBlocked !== null && rightBlocked !== null && leftBlocked !== rightBlocked) return leftBlocked - rightBlocked;
  return compareUpdatedTasks(left, right);
}

function compareDueUrgency(left: TaskItem, right: TaskItem, now: Date): number {
  const leftDue = timestamp(left.due_at);
  const rightDue = timestamp(right.due_at);
  const leftBucket = dueBucket(leftDue, now);
  const rightBucket = dueBucket(rightDue, now);
  if (leftBucket !== rightBucket) return leftBucket - rightBucket;
  if (leftDue !== null && rightDue !== null && leftDue !== rightDue) return leftDue - rightDue;
  return 0;
}

function dueBucket(due: number | null, now: Date): number {
  if (due === null) return 2;
  return due < now.getTime() ? 0 : 1;
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
