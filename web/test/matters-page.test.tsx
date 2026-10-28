import { fireEvent, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { HomeResponse, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { MattersPage } from '../src/pages/MattersPage';
import { render } from './react-test-helpers';

afterEach(() => vi.useRealTimers());

const task = (id: string, overrides: Partial<TaskItem> = {}): TaskItem => ({
  id,
  workspace_id: 'workspace-1',
  parent_task_id: null,
  title: id,
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
  created_at: '2026-09-01T00:00:00Z',
  updated_at: '2026-09-01T00:00:00Z',
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

function makeSync(tasks: TaskItem[], home?: HomeResponse): WorkspaceSyncController {
  const state: WorkspaceSyncState = {
    snapshot: {
      workspace_id: 'workspace-1',
      workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [],
      tasks,
      conflicts: [],
      cursor: 1,
      viewer_user_id: 'viewer',
      classifications: [{ id: 'classification-life', workspace_id: 'workspace-1', name: '生活', created_by: 'viewer', created_at: null }],
    } satisfies WorkspaceSnapshot,
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
    home,
  };
  return {
    get state(): WorkspaceSyncState { return state; },
    subscribe: vi.fn(() => () => undefined),
    transitionTask: vi.fn().mockResolvedValue(undefined),
    createTask: vi.fn().mockResolvedValue(undefined),
  } as unknown as WorkspaceSyncController;
}

describe('MattersPage', () => {
  it('shows completed archive history without the moment task groups', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-27T12:00:00Z'));
    const mine = task('active', { status: 'IN_PROGRESS' });
    const expired = task('expired', { status: 'BLOCKED', due_at: '2026-10-26T12:00:00Z' });
    const done = task('done', { status: 'DONE', current_handler_id: 'partner' });
    const cancelled = task('cancelled', { status: 'CANCELLED' });
    const home = {
      moment: {
        blocked: { items: [], has_more: false },
        mine: { items: [mine], has_more: false },
        other: { items: [], has_more: false },
      },
    } as unknown as HomeResponse;
    const onOpenTask = vi.fn();
    render(<MattersPage sync={makeSync([mine, expired, done, cancelled], home)} onOpenTask={onOpenTask} onCreateTask={vi.fn()} />);

    const overdue = screen.getByRole('region', { name: '已经过期' });
    const overdueToggle = within(overdue).getByRole('button', { name: '展开已经过期清单' });
    expect(overdueToggle).toHaveAttribute('aria-expanded', 'false');
    expect(overdue).toHaveTextContent('1 项');
    expect(document.querySelectorAll('[data-task-row="expired"]')).toHaveLength(0);
    fireEvent.click(overdueToggle);
    expect(within(overdue).getByRole('heading', { name: 'expired' })).toBeInTheDocument();
    expect(within(overdue).getByRole('button', { name: '收起已经过期清单' })).toHaveAttribute('aria-expanded', 'true');

    const archive = screen.getByRole('region', { name: '已完成/已归档' });
    expect(within(archive).getByRole('heading', { name: 'done' })).toBeInTheDocument();
    expect(within(archive).queryByRole('heading', { name: 'active' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'cancelled' })).not.toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row="done"]')).toHaveLength(1);
    expect(within(archive).queryByRole('button', { name: '重新开启' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: '卡住的事情' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: '我在推进' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'TA 在推进' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'active' })).not.toBeInTheDocument();
    fireEvent.click(within(archive).getByRole('button', { name: 'done' }));
    expect(onOpenTask).toHaveBeenCalledWith(done);
  });

  it('renders canonical metrics and switches views from the title menu', () => {
    const blocked = task('blocked', { status: 'BLOCKED', current_handler_id: 'partner' });
    const mine = task('mine', { status: 'IN_PROGRESS' });
    const home = {
      entry_counts: { needs_me: 2, waiting_on_other: 1, due_this_week: 3, due_soon: 4 },
      moment: {
        blocked: { items: [blocked], has_more: false },
        mine: { items: [mine], has_more: false },
        other: { items: [], has_more: false },
      },
      entries: { needs_me: { items: [], has_more: false }, waiting_on_other: { items: [], has_more: false }, due_this_week: { items: [], has_more: false }, due_soon: { items: [], has_more: false } },
    } as HomeResponse;
    render(<MattersPage sync={makeSync([blocked, mine], home)} view="moment" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('需要我处理');
    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('2');
    expect(screen.queryByRole('region', { name: '卡住的事情' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: '我在推进' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'TA 在推进' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'blocked' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'mine' })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: '此刻' }));
    expect(screen.getByRole('menuitemradio', { name: '清单' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('menuitemradio', { name: '四象限' }));
    expect(window.location.hash).toBe('#/matters/quadrant');
  });

  it('opens metric entries from canonical Home data without duplicating the moment sections', () => {
    const awaitingApproval = task('waiting-for-me', { status: 'IN_PROGRESS' });
    const home = {
      entry_counts: { needs_me: 1, waiting_on_other: 0, due_this_week: 0 },
      moment: {
        blocked: { items: [], has_more: false },
        mine: { items: [], has_more: false },
        other: { items: [], has_more: false },
      },
      entries: {
        needs_me: { items: [{ approval_request: {}, task: awaitingApproval }], has_more: false },
        waiting_on_other: { items: [], has_more: false },
        due_this_week: { items: [], has_more: false },
      },
    } as unknown as HomeResponse;
    render(<MattersPage sync={makeSync([awaitingApproval], home)} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: /需要我处理/ }));

    const entry = screen.getByRole('region', { name: '需要我处理' });
    expect(within(entry).getByRole('heading', { name: 'waiting-for-me' })).toBeInTheDocument();
    expect(within(entry).queryByRole('button', { name: '提交验收' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: '我在推进' })).not.toBeInTheDocument();
  });

  it('opens the server due-soon entry and displays its canonical tasks', () => {
    const soon = task('due-in-twelve-days', { due_at: '2026-09-13T10:00:00Z' });
    const home = {
      entry_counts: { needs_me: 0, waiting_on_other: 0, due_this_week: 0, due_soon: 1 },
      moment: {
        blocked: { items: [], has_more: false },
        mine: { items: [], has_more: false },
        other: { items: [], has_more: false },
      },
      entries: {
        needs_me: { items: [], has_more: false },
        waiting_on_other: { items: [], has_more: false },
        due_this_week: { items: [], has_more: false },
        due_soon: { items: [soon], has_more: false },
      },
    } as unknown as HomeResponse;
    render(<MattersPage sync={makeSync([soon], home)} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: /即将到期/ }));

    const entry = screen.getByRole('region', { name: '即将到期' });
    expect(within(entry).getByRole('heading', { name: 'due-in-twelve-days' })).toBeInTheDocument();
    expect(entry).toHaveTextContent('1');
  });

  it('closes the view menu on Escape and restores focus to the title', () => {
    render(<MattersPage sync={makeSync([])} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    const trigger = screen.getByRole('button', { name: '此刻' });
    fireEvent.click(trigger);
    const selectedOption = screen.getByRole('menuitemradio', { name: '清单' });
    expect(selectedOption).toHaveFocus();

    fireEvent.keyDown(selectedOption, { key: 'Escape' });

    expect(screen.queryByRole('menu', { name: '事项视图' })).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });

  it('moves focus through view options with arrow keys and closes on outside click', () => {
    render(<MattersPage sync={makeSync([])} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: '此刻' }));
    const options = screen.getAllByRole('menuitemradio');
    expect(options[0]).toHaveFocus();
    fireEvent.keyDown(options[0], { key: 'ArrowDown' });
    expect(options[1]).toHaveFocus();

    fireEvent.pointerDown(document.body);

    expect(screen.queryByRole('menu', { name: '事项视图' })).not.toBeInTheDocument();
  });

  it('keeps open task groups out of the default moment view', () => {
    const blocked = task('same', { status: 'BLOCKED' });
    const mine = task('mine');
    const other = task('other', { current_handler_id: 'partner' });
    render(<MattersPage sync={makeSync([blocked, mine, other])} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(screen.queryByRole('region', { name: '卡住的事情' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: '我在推进' })).not.toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'TA 在推进' })).not.toBeInTheDocument();
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(0);
  });

  it('filters quadrants by current handler without changing the task source', () => {
    const mine = task('mine', { quadrant: 'Q1', current_handler_id: 'viewer' });
    const theirs = task('theirs', { quadrant: 'Q1', current_handler_id: 'partner' });
    const sync = makeSync([mine, theirs]);
    render(<MattersPage sync={sync} view="quadrant" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    const q1 = screen.getByRole('region', { name: '重要且紧急' });
    expect(within(q1).getByRole('heading', { name: 'mine' })).toBeInTheDocument();
    expect(within(q1).getByRole('heading', { name: 'theirs' })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: '我负责' }));
    expect(within(q1).getByRole('heading', { name: 'mine' })).toBeInTheDocument();
    expect(within(q1).queryByRole('heading', { name: 'theirs' })).not.toBeInTheDocument();
    expect(sync.state.snapshot?.tasks).toHaveLength(2);
  });

  it('retains the quadrant owner filter while switching views in the matters page', () => {
    const sync = makeSync([task('mine', { current_handler_id: 'viewer' }), task('theirs', { current_handler_id: 'partner' })]);
    const props = { sync, onOpenTask: vi.fn(), onCreateTask: vi.fn() };
    const { rerender } = render(<MattersPage {...props} view="quadrant" />);
    fireEvent.click(screen.getByRole('button', { name: '我负责' }));

    rerender(<MattersPage {...props} view="moment" />);
    rerender(<MattersPage {...props} view="quadrant" />);

    const q1 = screen.getByRole('region', { name: '重要不紧急' });
    expect(within(q1).getByRole('heading', { name: 'mine' })).toBeInTheDocument();
    expect(within(q1).queryByRole('heading', { name: 'theirs' })).not.toBeInTheDocument();
  });

  it('shows a Monday-first month calendar and tasks for the selected date', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-24T10:00:00Z'));
    const selectedTask = task('due-on-selected-date', { due_at: '2026-09-25T18:30:00+08:00' });
    render(<MattersPage sync={makeSync([selectedTask])} view="schedule" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(screen.getByRole('heading', { name: '2026年9月' })).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: '周一' })).toBeInTheDocument();
    const dateCells = screen.getAllByRole('gridcell');
    expect(within(dateCells[0]).getByRole('button', { name: /2026年8月31日/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /2026年9月25日/ })).toHaveAttribute('data-has-tasks', 'true');
    expect(screen.queryByRole('heading', { name: 'due-on-selected-date' })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /2026年9月25日/ }));

    expect(screen.getByRole('heading', { name: 'due-on-selected-date' })).toBeInTheDocument();
  });

  it('navigates calendar months and returns the selection to today', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-24T10:00:00Z'));
    render(<MattersPage sync={makeSync([])} view="schedule" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: '下个月' }));
    expect(screen.getByRole('heading', { name: '2026年10月' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '回到今天' }));
    expect(screen.getByRole('heading', { name: '2026年9月' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '2026年9月24日' })).toHaveAttribute('aria-pressed', 'true');
  });

  it('moves calendar selection and keyboard focus by a week', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-24T10:00:00Z'));
    render(<MattersPage sync={makeSync([])} view="schedule" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);
    fireEvent.keyDown(screen.getByRole('button', { name: '2026年9月24日' }), { key: 'ArrowDown' });

    expect(screen.getByRole('heading', { name: '2026年10月' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '2026年10月1日' })).toHaveFocus();
  });
});
