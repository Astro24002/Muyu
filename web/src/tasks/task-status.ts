import type { CanonicalTaskStatus, TaskStatus } from '../api/types';
import { isCanonicalTaskStatus, normalizeTaskStatus } from './task-model';

export const TASK_STATUS_LABELS: Readonly<Record<CanonicalTaskStatus, string>> = {
  TODO: '待进行',
  IN_PROGRESS: '进行中',
  BLOCKED: '阻塞中',
  REVIEW: '待验收',
  DONE: '已完成',
  CANCELLED: '已取消',
};

export type TaskStatusTone = 'neutral' | 'active' | 'blocked' | 'review' | 'success' | 'cancelled';

const TASK_STATUS_TONES: Readonly<Record<CanonicalTaskStatus, TaskStatusTone>> = {
  TODO: 'neutral',
  IN_PROGRESS: 'active',
  BLOCKED: 'blocked',
  REVIEW: 'review',
  DONE: 'success',
  CANCELLED: 'cancelled',
};

export function normalizedTaskStatus(status: TaskStatus | string): CanonicalTaskStatus | undefined {
  const normalized = normalizeTaskStatus(status);
  return isCanonicalTaskStatus(normalized) ? normalized : undefined;
}

export function statusLabel(status: TaskStatus | string): string {
  const normalized = normalizedTaskStatus(status);
  return normalized ? TASK_STATUS_LABELS[normalized] : '未知状态';
}

export function statusTone(status: TaskStatus | string): TaskStatusTone {
  const normalized = normalizedTaskStatus(status);
  return normalized ? TASK_STATUS_TONES[normalized] : 'neutral';
}
