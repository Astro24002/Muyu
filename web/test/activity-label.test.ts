import { describe, expect, it } from 'vitest';
import { activityLabel } from '../src/tasks/activity-label';

describe('activityLabel', () => {
  it.each([
    ['CREATED', '创建任务'],
    ['UPDATED', '更新任务'],
    ['STATUS_CHANGED', '更新状态'],
    ['HANDLER_CHANGED', '转移负责人'],
    ['DELETED', '删除任务'],
    ['RESTORED', '恢复任务'],
    ['COMMENTED', '添加评论'],
    ['DELAYED', '延期任务'],
    ['CONFLICT_CREATED', '产生冲突'],
    ['CONFLICT_RESOLVED', '解决冲突'],
    ['UPDATE', '更新任务'],
    ['TRANSITION', '更新状态'],
  ])('maps the FastAPI operation %s to %s', (operation, label) => {
    expect(activityLabel(operation)).toBe(label);
  });

  it('keeps unknown operation values visible for diagnostics', () => {
    expect(activityLabel('FUTURE_OPERATION')).toBe('FUTURE_OPERATION');
  });
});
