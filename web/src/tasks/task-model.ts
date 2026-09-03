import type { CanonicalTaskStatus, TaskItem, TaskQuadrant } from '../api/types';

export type EditableTaskChanges = Pick<Partial<TaskItem>,
  | 'title'
  | 'description'
  | 'due_at'
  | 'planned_start_at'
  | 'estimated_minutes'
  | 'quadrant'
  | 'labels'
  | 'progress'
  | 'current_handler_id'
>;

export interface TaskConflict {
  id: string;
  workspace_id?: string;
  task_id: string;
  field: string;
  base?: unknown;
  current?: unknown;
  proposed?: unknown;
  status?: string;
  proposed_payload?: unknown;
  base_version?: number;
  current_version?: number;
  base_status_version?: number;
  current_status_version?: number;
  reviewer_user_id?: string | null;
  review_submitted_at?: string | null;
  reviewed_at?: string | null;
  review_rejection_reason?: string | null;
  blocked_reason?: string | null;
  blocked_since?: string | null;
  resume_handler_id?: string | null;
  waiting_for_user_id?: string | null;
  field_versions?: Record<string, number>;
  status_version?: number;
  lifecycle_version?: number;
  current_snapshot?: unknown;
  [key: string]: unknown;
}

export const TASK_QUADRANTS: readonly TaskQuadrant[] = ['Q1', 'Q2', 'Q3', 'Q4'];
// Read-only compatibility for snapshots produced before the six-state
// migration. New requests must use canonical statuses.
export const LEGACY_STATUS_MAP = { WAITING: 'BLOCKED', COMPLETED: 'DONE' } as const;
export const TASK_STATUS_TRANSITIONS: Readonly<Record<CanonicalTaskStatus, readonly CanonicalTaskStatus[]>> = {
  TODO: ['IN_PROGRESS', 'BLOCKED', 'CANCELLED'],
  IN_PROGRESS: ['BLOCKED', 'REVIEW', 'CANCELLED'],
  BLOCKED: ['IN_PROGRESS', 'CANCELLED'],
  REVIEW: ['DONE', 'IN_PROGRESS', 'CANCELLED'],
  DONE: ['TODO', 'IN_PROGRESS', 'CANCELLED'],
  CANCELLED: ['TODO', 'IN_PROGRESS'],
};
const MAX_TASK_LABELS = 10;
const MAX_TASK_LABEL_LENGTH = 32;
const MAX_TASK_LABEL_CHARS = 320;

/**
 * Keep the Web boundary tolerant of older or malformed payloads while only
 * exposing the fields the rest of the app can safely use.
 */
export function parseTaskItem(value: unknown): TaskItem {
  if (!isRecord(value)) throw new Error('任务数据格式无效。');
  if (!isTaskQuadrant(value.quadrant)) throw new Error('任务必须设置有效四象限。');
  const status = normalizeTaskStatus(value.status);
  return { ...value, status, quadrant: value.quadrant, labels: value.labels === undefined ? [] : parseTaskLabels(value.labels) } as TaskItem;
}

export function normalizeTaskStatus(value: unknown): unknown {
  if (value === 'WAITING' || value === 'COMPLETED') return LEGACY_STATUS_MAP[value];
  return value;
}

export function isCanonicalTaskStatus(value: unknown): value is CanonicalTaskStatus {
  return value === 'TODO'
    || value === 'IN_PROGRESS'
    || value === 'BLOCKED'
    || value === 'REVIEW'
    || value === 'DONE'
    || value === 'CANCELLED';
}

export function taskTransitionTargets(task: Pick<TaskItem, 'status' | 'current_handler_id' | 'reviewer_user_id'>, actorUserId?: string | null): CanonicalTaskStatus[] {
  const currentStatus = normalizeTaskStatus(task.status);
  if (!isCanonicalTaskStatus(currentStatus)) return [];
  return TASK_STATUS_TRANSITIONS[currentStatus].filter((targetStatus) => {
    if (currentStatus !== 'REVIEW' || (targetStatus !== 'DONE' && targetStatus !== 'IN_PROGRESS')) return true;
    return Boolean(
      actorUserId
      && actorUserId === task.reviewer_user_id
      && actorUserId !== task.current_handler_id,
    );
  });
}

export function isTaskTransitionAllowed(
  task: Pick<TaskItem, 'status' | 'current_handler_id' | 'reviewer_user_id'>,
  targetStatus: unknown,
  actorUserId?: string | null,
): targetStatus is CanonicalTaskStatus {
  return isCanonicalTaskStatus(targetStatus)
    && taskTransitionTargets(task, actorUserId).includes(targetStatus);
}

export function parseTaskLabels(value: unknown): string[] {
  if (!Array.isArray(value)) throw new Error('任务标签必须是字符串数组。');
  const labels: string[] = [];
  const seen = new Set<string>();
  let totalChars = 0;
  for (const item of value) {
    if (typeof item !== 'string') throw new Error('任务标签必须是字符串数组。');
    const label = item.trim();
    const key = label.toLocaleLowerCase();
    if (!label) throw new Error('任务标签不能为空。');
    if (unicodeLength(label) > MAX_TASK_LABEL_LENGTH) throw new Error(`单个任务标签不能超过 ${MAX_TASK_LABEL_LENGTH} 个字符。`);
    if (seen.has(key)) continue;
    if (labels.length >= MAX_TASK_LABELS) throw new Error(`任务最多添加 ${MAX_TASK_LABELS} 个标签。`);
    totalChars += unicodeLength(label);
    if (totalChars > MAX_TASK_LABEL_CHARS) throw new Error(`任务标签总长度不能超过 ${MAX_TASK_LABEL_CHARS} 个字符。`);
    seen.add(key);
    labels.push(label);
  }
  return labels;
}

export function parseTaskLabelsInput(value: string): string[] {
  if (!value.trim()) return [];
  return parseTaskLabels(value.split(/[,，\n]/));
}

export function isTaskQuadrant(value: unknown): value is TaskQuadrant {
  return typeof value === 'string' && TASK_QUADRANTS.includes(value as TaskQuadrant);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === 'object' && !Array.isArray(value));
}

function unicodeLength(value: string): number {
  return Array.from(value).length;
}

export function upsertTask(tasks: TaskItem[], task: TaskItem): TaskItem[] {
  const index = tasks.findIndex((item) => item.id === task.id);
  if (task.deleted_at !== null) return tasks.filter((item) => item.id !== task.id);
  if (index === -1) return [...tasks, task];
  return tasks.map((item) => item.id === task.id ? task : item);
}
