import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskItem } from '../src/api/types';
import { FocusTask } from '../src/components/tasks/FocusTask';
import { TaskList } from '../src/components/tasks/TaskList';
import { TaskRow } from '../src/components/tasks/TaskRow';
import { render } from './react-test-helpers';

const makeTask = (overrides: Partial<TaskItem> = {}): TaskItem => ({
  id: 'task-1',
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: '准备周末晚餐',
  description: '列出需要购买的食材',
  due_at: '2026-09-01T12:00:00Z',
  status: 'TODO',
  current_handler_id: 'viewer',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: 30,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-08-30T08:00:00Z',
  updated_at: '2026-08-30T08:00:00Z',
  assignee_ids: ['viewer'],
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q2',
  labels: ['生活'],
  progress: null,
  ...overrides,
});

describe('TaskRow', () => {
  it('renders stable row hooks, readable title metadata date status, and completion control', () => {
    const task = makeTask();

    render(<TaskRow task={task} onOpen={vi.fn()} onComplete={vi.fn()} busy={false} />);

    const row = document.querySelector('[data-task-row]');
    expect(row).toHaveAttribute('data-task-row', task.id);
    expect(screen.getByRole('heading', { name: task.title })).toBeInTheDocument();
    expect(screen.getByText(/Q2/)).toBeInTheDocument();
    expect(screen.getByText('截止 2026-09-01')).toBeInTheDocument();
    expect(screen.getByText('待开始')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '完成' })).toBeEnabled();
  });

  it('opens from the row but stops completion from opening it', () => {
    const task = makeTask();
    const onOpen = vi.fn();
    const onComplete = vi.fn();

    render(<TaskRow task={task} onOpen={onOpen} onComplete={onComplete} busy={false} />);

    fireEvent.click(document.querySelector('[data-task-row]')!);
    expect(onOpen).toHaveBeenCalledWith(task);

    fireEvent.click(screen.getByRole('button', { name: '完成' }));
    expect(onComplete).toHaveBeenCalledWith(task);
    expect(onOpen).toHaveBeenCalledTimes(1);
    expect(task.status).toBe('TODO');
  });

  it('supports keyboard row opening and disables completion while busy', () => {
    const onOpen = vi.fn();
    render(<TaskRow task={makeTask()} onOpen={onOpen} onComplete={vi.fn()} busy />);

    const row = document.querySelector('[data-task-row]')!;
    expect(row).toHaveAttribute('role', 'button');
    expect(row).toHaveAttribute('tabindex', '0');
    fireEvent.keyDown(row, { key: 'Enter' });
    fireEvent.keyDown(row, { key: ' ' });
    expect(onOpen).toHaveBeenCalledTimes(2);
    expect(screen.getByRole('button', { name: '完成' })).toBeDisabled();
  });

  it('keeps waiting, due, and completed semantics in text', () => {
    const { rerender } = render(
      <TaskRow
        task={makeTask({ status: 'WAITING', blocked_reason: '等待伙伴确认', due_at: '2026-08-31T08:00:00Z' })}
        onOpen={vi.fn()}
        onComplete={vi.fn()}
        busy={false}
      />,
    );
    expect(screen.getByText('等待中')).toBeInTheDocument();
    expect(screen.getByText(/阻塞：等待伙伴确认/)).toBeInTheDocument();
    expect(screen.getByText('已过期')).toBeInTheDocument();

    rerender(<TaskRow task={makeTask({ status: 'DONE' })} onOpen={vi.fn()} onComplete={vi.fn()} busy={false} />);
    expect(screen.getByText('已完成')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '完成' })).toBeDisabled();
  });

  it('keeps long titles readable instead of trimming the task object or text', () => {
    const title = '需要保留完整内容的很长任务标题'.repeat(12);

    render(<TaskRow task={makeTask({ title })} onOpen={vi.fn()} onComplete={vi.fn()} busy={false} />);

    expect(screen.getByRole('heading', { name: title })).toHaveTextContent(title);
  });
});

describe('TaskList and FocusTask', () => {
  it('renders an empty message and forwards row actions', () => {
    const onOpen = vi.fn();
    const onComplete = vi.fn();
    const task = makeTask({ id: 'list-task' });

    const { rerender } = render(
      <TaskList tasks={[]} emptyMessage="今天没有需要处理的任务" onOpen={onOpen} onComplete={onComplete} busy={false} />,
    );
    expect(screen.getByText('今天没有需要处理的任务')).toBeInTheDocument();

    rerender(<TaskList tasks={[task]} emptyMessage="空" onOpen={onOpen} onComplete={onComplete} busy={false} />);
    fireEvent.click(document.querySelector('[data-task-row]')!);
    expect(onOpen).toHaveBeenCalledWith(task);
  });

  it('gives focus work one pale-green component and the exact continue action', () => {
    const task = makeTask({ status: 'IN_PROGRESS', progress: 40 });
    const onContinue = vi.fn();

    render(<FocusTask task={task} onContinue={onContinue} busy={false} />);

    const focus = document.querySelector('[data-focus-task]');
    expect(focus).toHaveClass('focus-task');
    expect(focus).toHaveTextContent(task.title);
    expect(focus).toHaveTextContent('进行中');
    expect(focus).toHaveTextContent('进度 40%');
    fireEvent.click(screen.getByRole('button', { name: '继续处理' }));
    expect(onContinue).toHaveBeenCalledWith(task);
  });

  it('disables the focus action while busy', () => {
    render(<FocusTask task={makeTask({ status: 'IN_PROGRESS' })} onContinue={vi.fn()} busy />);

    expect(screen.getByRole('button', { name: '继续处理' })).toBeDisabled();
  });
});
