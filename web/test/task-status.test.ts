import { describe, expect, it } from 'vitest';
import { statusLabel, statusTone } from '../src/tasks/task-status';

describe('task status presentation', () => {
  it.each([
    ['TODO', '待进行', 'neutral'],
    ['IN_PROGRESS', '进行中', 'active'],
    ['BLOCKED', '阻塞中', 'blocked'],
    ['REVIEW', '待验收', 'review'],
    ['DONE', '已完成', 'success'],
    ['CANCELLED', '已取消', 'cancelled'],
  ])('maps %s to the shared Chinese label and tone', (status, label, tone) => {
    expect(statusLabel(status)).toBe(label);
    expect(statusTone(status)).toBe(tone);
  });

  it('normalizes legacy values without exposing their English names', () => {
    expect(statusLabel('WAITING')).toBe('阻塞中');
    expect(statusLabel('COMPLETED')).toBe('已完成');
    expect(statusLabel('UNKNOWN')).toBe('未知状态');
  });
});
