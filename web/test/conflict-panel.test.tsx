import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskConflict } from '../src/tasks/task-model';
import { ConflictPanel } from '../src/components/conflicts/ConflictPanel';
import { render } from './react-test-helpers';

const conflicts: TaskConflict[] = [
  { id: 'conflict-title', task_id: 'task-1', field: '标题', base: '旧标题', current: '当前标题', proposed: '提议标题' },
  { id: 'conflict-due', task_id: 'task-1', field: '截止时间', base: null, current: '2026-09-02', proposed: '2026-09-04' },
];

describe('ConflictPanel', () => {
  it('shows each conflicting field with explicit current and proposed choices', () => {
    const onResolve = vi.fn();
    render(<ConflictPanel conflicts={conflicts} busy={false} onResolve={onResolve} />);

    expect(screen.getByRole('heading', { name: '待处理冲突' })).toBeInTheDocument();
    expect(screen.getByText('当前值：当前标题')).toBeInTheDocument();
    expect(screen.getByText('提议值：提议标题')).toBeInTheDocument();
    expect(screen.getByText('当前值：2026-09-02')).toBeInTheDocument();
    expect(screen.getByText('提议值：2026-09-04')).toBeInTheDocument();

    fireEvent.click(screen.getAllByRole('button', { name: '保留当前' })[0]);
    fireEvent.click(screen.getAllByRole('button', { name: '采用提议' })[1]);

    expect(onResolve).toHaveBeenNthCalledWith(1, 'conflict-title', 'current');
    expect(onResolve).toHaveBeenNthCalledWith(2, 'conflict-due', 'proposed');
  });

  it('disables both resolution choices while resolving', () => {
    render(<ConflictPanel conflicts={conflicts} busy onResolve={vi.fn()} />);

    expect(screen.getAllByRole('button', { name: '保留当前' }).every((button) => button.hasAttribute('disabled'))).toBe(true);
    expect(screen.getAllByRole('button', { name: '采用提议' }).every((button) => button.hasAttribute('disabled'))).toBe(true);
  });
});
