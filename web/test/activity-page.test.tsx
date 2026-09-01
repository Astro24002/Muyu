import { fireEvent, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { ActivityEvent, TaskItem } from '../src/api/types';
import { ActivityPage } from '../src/pages/ActivityPage';
import { render } from './react-test-helpers';

const makeTask = (id: string, title: string): TaskItem => ({
  id,
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title,
  description: '',
  due_at: null,
  status: 'TODO',
  current_handler_id: 'viewer',
  blocked_reason: null,
  blocked_since: null,
  resume_handler_id: null,
  waiting_for_user_id: null,
  planned_start_at: null,
  estimated_minutes: null,
  completed_at: null,
  created_by: 'viewer',
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-01T00:00:00Z',
  assignee_ids: [],
  delay_count: 0,
  total_delay_minutes: 0,
  version: 1,
  status_version: 1,
  field_versions: {},
  lifecycle_version: 1,
  deleted_at: null,
  quadrant: 'Q2',
  labels: [],
});

const taskOne = makeTask('task-1', '整理周末晚餐');
const taskTwo = makeTask('task-2', '准备会议材料');
const activity = (id: string, body = '更新完成'): ActivityEvent => ({
  kind: 'operation',
  id,
  created_at: '2026-09-01T09:30:00Z',
  operation_type: 'UPDATE',
  actor_user_id: 'viewer',
  body,
  request_id: 'request-secret',
  cursor: 99,
  version: 4,
  token: 'token-secret',
  cookie: 'cookie-secret',
  proof: 'proof-secret',
  digest: 'digest-secret',
});

describe('ActivityPage', () => {
  afterEach(() => {
    window.location.hash = '';
  });

  it('renders task titles and safe activity details without internal fields', async () => {
    const getTaskActivity = vi.fn().mockResolvedValue([activity('event-1')]);

    render(<ActivityPage tasks={[taskOne]} getTaskActivity={getTaskActivity} workspaceKey="workspace-1" />);

    expect(screen.getByRole('heading', { name: '动态' })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText(taskOne.title)).toBeInTheDocument());
    expect(screen.getByText('更新任务')).toBeInTheDocument();
    expect(screen.getByText(/操作者：viewer/)).toBeInTheDocument();
    expect(document.body.textContent).not.toContain('request-secret');
    expect(document.body.textContent).not.toMatch(/cursor|version|token-secret|cookie-secret|proof-secret|digest-secret/i);
  });

  it('shows partial failures and retries the activity load', async () => {
    const getTaskActivity = vi.fn()
      .mockResolvedValueOnce([activity('event-1', '第一次加载')])
      .mockRejectedValueOnce(new Error('temporary'))
      .mockResolvedValueOnce([activity('event-2', '重试成功')])
      .mockResolvedValueOnce([]);

    render(<ActivityPage tasks={[taskOne, taskTwo]} getTaskActivity={getTaskActivity} workspaceKey="workspace-1" />);

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('部分动态暂时无法加载'));
    expect(screen.getByText(taskOne.title)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '重试' }));
    await waitFor(() => expect(screen.getByText('重试成功')).toBeInTheDocument());
    expect(getTaskActivity).toHaveBeenCalledTimes(4);
  });

  it('renders a useful empty state without requesting activity for no tasks', async () => {
    const getTaskActivity = vi.fn();

    render(<ActivityPage tasks={[]} getTaskActivity={getTaskActivity} workspaceKey="workspace-1" />);

    expect(await screen.findByText('还没有可展示的动态')).toBeInTheDocument();
    expect(getTaskActivity).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: '回到今天' })).toBeInTheDocument();
  });

  it('fences a previous session response after the workspace key changes', async () => {
    let resolveOld!: (events: ActivityEvent[]) => void;
    const oldResponse = new Promise<ActivityEvent[]>((resolve) => { resolveOld = resolve; });
    const getTaskActivity = vi.fn()
      .mockReturnValueOnce(oldResponse)
      .mockResolvedValueOnce([activity('new-event', '新会话动态')]);
    const { rerender } = render(
      <ActivityPage tasks={[taskOne]} getTaskActivity={getTaskActivity} workspaceKey="session-old" />,
    );

    await waitFor(() => expect(getTaskActivity).toHaveBeenCalledWith(taskOne.id));
    rerender(<ActivityPage tasks={[taskTwo]} getTaskActivity={getTaskActivity} workspaceKey="session-new" />);
    await waitFor(() => expect(getTaskActivity).toHaveBeenCalledWith(taskTwo.id));
    resolveOld([activity('old-event', '旧会话动态')]);

    await waitFor(() => expect(screen.getByText('新会话动态')).toBeInTheDocument());
    expect(screen.queryByText('旧会话动态')).not.toBeInTheDocument();
  });
});
