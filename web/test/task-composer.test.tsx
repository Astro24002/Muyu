import { act, fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { TaskItem, WorkspaceClassification, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { TaskComposer } from '../src/components/tasks/TaskComposer';
import { render } from './react-test-helpers';

describe('TaskComposer', () => {
  it('expands into the requested fields and creates a normalized task through sync', async () => {
    const { sync } = createFakeSync();

    render(<TaskComposer sync={sync} />);

    fireEvent.click(screen.getByRole('button', { name: '记下一件事' }));
    expect(screen.getByLabelText('任务标题')).toBeInTheDocument();
    expect(screen.getByLabelText('下一步描述')).toBeInTheDocument();
    expect(screen.getByLabelText('四象限')).toBeInTheDocument();
    expect(screen.getByRole('group', { name: '分类' })).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('任务标题'), { target: { value: '  写周报  ' } });
    fireEvent.change(screen.getByLabelText('下一步描述'), { target: { value: '先列出本周完成事项' } });
    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q1' } });
    fireEvent.click(screen.getByRole('radio', { name: '工作' }));
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));

    await waitFor(() => expect(sync.createTask).toHaveBeenCalledWith('写周报', '先列出本周完成事项', 'Q1', ['工作']));
    expect(screen.getByLabelText('任务标题')).toHaveValue('');
    expect(screen.getByLabelText('下一步描述')).toHaveValue('');
    expect(screen.getByLabelText('四象限')).toHaveValue('');
    expect(screen.getByRole('radio', { name: '工作' })).not.toBeChecked();
  });

  it('reports title and quadrant validation at the form and does not submit invalid drafts', () => {
    const { sync } = createFakeSync();

    render(<TaskComposer sync={sync} />);
    fireEvent.click(screen.getByRole('button', { name: '记下一件事' }));
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));
    expect(screen.getByRole('alert')).toHaveTextContent('请输入任务标题。');
    expect(sync.createTask).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText('任务标题'), { target: { value: '有标题' } });
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));
    expect(screen.getByRole('alert')).toHaveTextContent('请选择四象限。');
    expect(sync.createTask).not.toHaveBeenCalled();
  });

  it('does not submit when the workspace has no approved classifications', () => {
    const { sync } = createFakeSync(makeSnapshot([]));

    render(<TaskComposer sync={sync} />);
    fireEvent.click(screen.getByRole('button', { name: '记下一件事' }));
    fireEvent.change(screen.getByLabelText('任务标题'), { target: { value: '没有分类的任务' } });
    fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q1' } });
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));

    expect(screen.getByRole('group', { name: '分类' })).toHaveTextContent('暂无已批准分类，请先创建分类。');
    expect(screen.getByRole('alert')).toHaveTextContent('请选择一个已批准分类。');
    expect(sync.createTask).not.toHaveBeenCalled();
  });

  it('disables the expanded form while sync is busy, stale, or unauthorized', () => {
    const fake = createFakeSync();
    render(<TaskComposer sync={fake.sync} />);
    fireEvent.click(screen.getByRole('button', { name: '记下一件事' }));

    for (const statePatch of [{ loading: true }, { loading: false, stale: true }, { stale: false, authRequired: true }] as const) {
      act(() => fake.setState({ ...fake.sync.state, ...statePatch }));
      expect(screen.getByRole('button', { name: '创建任务' })).toBeDisabled();
    }
  });

  it('keeps every field when task creation fails', async () => {
    const fake = createFakeSync();
    fake.sync.createTask = vi.fn().mockRejectedValue(new Error('网络不可用')) as never;

    render(<TaskComposer sync={fake.sync} />);
    fillDraft();
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('网络不可用'));
    expect(screen.getByLabelText('任务标题')).toHaveValue('保留这份草稿');
    expect(screen.getByLabelText('下一步描述')).toHaveValue('网络恢复后继续');
    expect(screen.getByLabelText('四象限')).toHaveValue('Q2');
    expect(screen.getByRole('radio', { name: '工作' })).toBeChecked();
  });

  it('keeps the draft when the sync controller handles a network error in state', async () => {
    const fake = createFakeSync();
    fake.sync.createTask = vi.fn(async () => {
      fake.setState({ ...fake.sync.state, error: '无法创建任务，请检查网络后重试。' });
    }) as never;

    render(<TaskComposer sync={fake.sync} />);
    fillDraft();
    fireEvent.click(screen.getByRole('button', { name: '创建任务' }));

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('无法创建任务，请检查网络后重试。'));
    expect(screen.getByLabelText('任务标题')).toHaveValue('保留这份草稿');
  });
});

function fillDraft(): void {
  fireEvent.click(screen.getByRole('button', { name: '记下一件事' }));
  fireEvent.change(screen.getByLabelText('任务标题'), { target: { value: '保留这份草稿' } });
  fireEvent.change(screen.getByLabelText('下一步描述'), { target: { value: '网络恢复后继续' } });
  fireEvent.change(screen.getByLabelText('四象限'), { target: { value: 'Q2' } });
  fireEvent.click(screen.getByRole('radio', { name: '工作' }));
}

function createFakeSync(snapshot = makeSnapshot()): {
  sync: WorkspaceSyncController;
  setState: (state: WorkspaceSyncState) => void;
} {
  let current: WorkspaceSyncState = {
    snapshot,
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
  };
  const listeners = new Set<(state: WorkspaceSyncState) => void>();
  const sync = {
    get state(): WorkspaceSyncState { return current; },
    subscribe: vi.fn((listener: (state: WorkspaceSyncState) => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    }),
    createTask: vi.fn().mockResolvedValue(undefined),
    transitionTask: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;

  return {
    sync,
    setState: (state) => {
      current = state;
      for (const listener of listeners) listener(current);
    },
  };
}

function makeSnapshot(classifications: WorkspaceClassification[] = [
  { id: 'classification-work', workspace_id: 'workspace-1', name: '工作', created_by: 'viewer', created_at: null },
]): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-1',
    workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
    members: [],
    tasks: [],
    conflicts: [],
    cursor: 1,
    viewer_user_id: 'viewer',
    classifications,
  };
}
