import type { TaskItem, TaskQuadrant } from '../api/types';

export type EditableTaskChanges = Pick<Partial<TaskItem>,
  | 'title'
  | 'description'
  | 'due_at'
  | 'planned_start_at'
  | 'estimated_minutes'
  | 'quadrant'
  | 'labels'
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

export const TASK_QUADRANTS: readonly TaskQuadrant[] = ['Q1', 'Q2', 'Q3', 'Q4'];
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
  const status = value.status === 'COMPLETED' ? 'DONE' : value.status;
  return { ...value, status, quadrant: value.quadrant, labels: value.labels === undefined ? [] : parseTaskLabels(value.labels) } as TaskItem;
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
