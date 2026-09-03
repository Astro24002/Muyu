import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { TaskItem } from '../src/api/types';
import { TaskEditForm } from '../src/components/tasks/TaskEditForm';

const reviewTask: TaskItem = {
  id: 'task-review',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: 'Review task',
  description: '',
  due_at: null,
  status: 'REVIEW',
  current_handler_id: 'owner',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  reviewer_user_id: 'reviewer',
  review_submitted_at: '2026-09-03T00:00:00.000Z',
  reviewed_at: null,
  review_rejection_reason: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'owner',
  created_at: '2026-09-03T00:00:00.000Z',
  updated_at: '2026-09-03T00:00:00.000Z',
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 3,
  field_versions: { title: 1 },
  lifecycle_version: 3,
  deleted_at: null,
  quadrant: 'Q1',
  labels: [],
};

const members = [
  { user_id: 'owner', member_slot: 1 },
  { user_id: 'reviewer', member_slot: 2 },
];

function actions(
  onTransition = vi.fn().mockResolvedValue({ ...reviewTask, cursor: 4 }),
  currentUserId?: string,
) {
  return { onSave: vi.fn().mockResolvedValue(undefined), onTransition, currentUserId };
}

describe('TaskEditForm review actions', () => {
  afterEach(cleanup);

  it('allows the current handler to submit in-progress work for review', () => {
    render(
      <TaskEditForm
        task={{ ...reviewTask, status: 'IN_PROGRESS', reviewer_user_id: null }}
        members={members}
        actions={actions(undefined, 'owner')}
      />,
    );

    const optionValues = screen.getAllByRole('option').map((option) => option.getAttribute('value'));
    expect(optionValues).toContain('REVIEW');
    expect(optionValues).not.toContain('DONE');

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'REVIEW' } });
    expect(screen.getByRole('button', { name: '提交验收' })).toBeTruthy();
  });

  it('does not offer acceptance or return to the current handler', () => {
    render(<TaskEditForm task={reviewTask} members={members} actions={actions(undefined, 'owner')} />);

    const optionValues = screen.getAllByRole('option').map((option) => option.getAttribute('value'));
    expect(optionValues).not.toContain('DONE');
    expect(optionValues).not.toContain('IN_PROGRESS');
    expect(optionValues).toContain('CANCELLED');
  });

  it('labels reviewer actions as accept and return', () => {
    render(<TaskEditForm task={reviewTask} members={members} actions={actions(undefined, 'reviewer')} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'DONE' } });
    expect(screen.getByRole('button', { name: '通过验收' })).toBeTruthy();

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    expect(screen.getByRole('button', { name: '退回修改' })).toBeTruthy();
  });

  it('requires a reviewer return reason and sends it with the transition', async () => {
    const onTransition = vi.fn().mockResolvedValue({ ...reviewTask, status: 'IN_PROGRESS', cursor: 4 });
    render(<TaskEditForm task={reviewTask} members={members} actions={actions(onTransition, 'reviewer')} />);

    fireEvent.change(screen.getByLabelText('状态'), { target: { value: 'IN_PROGRESS' } });
    fireEvent.click(screen.getByRole('button', { name: '退回修改' }));
    expect(onTransition).not.toHaveBeenCalled();
    expect(screen.getByRole('alert').textContent).toContain('退回待验收任务需要填写退回原因');

    fireEvent.change(screen.getByLabelText('退回原因'), { target: { value: '请补充验收材料' } });
    fireEvent.click(screen.getByRole('button', { name: '退回修改' }));

    await waitFor(() => {
      expect(onTransition).toHaveBeenCalledWith('IN_PROGRESS', { reviewRejectionReason: '请补充验收材料' });
    });
  });
});
