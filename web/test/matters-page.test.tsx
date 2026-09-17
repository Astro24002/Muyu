import { fireEvent, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { HomeResponse, TaskItem, WorkspaceSnapshot } from '../src/api/types';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { MattersPage } from '../src/pages/MattersPage';
import { render } from './react-test-helpers';

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
  it('renders canonical metrics and switches views from the title menu', () => {
    const blocked = task('blocked', { status: 'BLOCKED', current_handler_id: 'partner' });
    const mine = task('mine', { status: 'IN_PROGRESS' });
    const home = {
      entry_counts: { needs_me: 2, waiting_on_other: 1, due_this_week: 3 },
      moment: {
        blocked: { items: [blocked], has_more: false },
        mine: { items: [mine], has_more: false },
        other: { items: [], has_more: false },
      },
      entries: { needs_me: { items: [], has_more: false }, waiting_on_other: { items: [], has_more: false }, due_this_week: { items: [], has_more: false } },
    } as HomeResponse;
    render(<MattersPage sync={makeSync([blocked, mine], home)} view="moment" onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('需要我处理');
    expect(screen.getByLabelText('事项入口指标')).toHaveTextContent('2');
    expect(screen.getByRole('heading', { name: 'blocked' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'mine' })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: '切换视图' }));
    expect(screen.getByRole('menuitemradio', { name: '清单' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('menuitemradio', { name: '四象限' }));
    expect(window.location.hash).toBe('#/matters/quadrant');
  });

  it('deduplicates fallback tasks with blocked priority across the three sections', () => {
    const blocked = task('same', { status: 'BLOCKED' });
    const mine = task('mine');
    const other = task('other', { current_handler_id: 'partner' });
    render(<MattersPage sync={makeSync([blocked, mine, other])} onOpenTask={vi.fn()} onCreateTask={vi.fn()} />);

    expect(document.querySelectorAll('[data-task-row="same"]')).toHaveLength(1);
    expect(document.querySelectorAll('[data-task-row]')).toHaveLength(3);
    expect(screen.getByRole('heading', { name: 'same' })).toBeInTheDocument();
  });
});
