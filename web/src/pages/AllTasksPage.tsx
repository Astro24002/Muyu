import { useCallback, useMemo, useState, type JSX } from 'react';
import type { TaskItem } from '../api/types';
import { useWorkspaceState } from '../app/use-external-state';
import { SyncStatus } from '../components/status/SyncStatus';
import { TaskComposer, type CreateTaskHandler } from '../components/tasks/TaskComposer';
import { TaskFilters, EMPTY_TASK_FILTERS, type TaskFilterValues } from '../components/tasks/TaskFilters';
import { TaskList } from '../components/tasks/TaskList';
import { SectionHeading } from '../components/ui/SectionHeading';
import { normalizedTaskStatus } from '../tasks/task-status';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

type TaskScope = 'open' | 'all' | 'blocked' | 'review' | 'transfer' | 'done';

export interface AllTasksPageProps {
  sync: WorkspaceSyncController;
  onOpenTask: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
  readOnly?: boolean;
}

export function AllTasksPage({ sync, onOpenTask, onCreateTask, readOnly = false }: AllTasksPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [filters, setFilters] = useState<TaskFilterValues>(EMPTY_TASK_FILTERS);
  const [query, setQuery] = useState('');
  const [scope, setScope] = useState<TaskScope>('open');
  const sourceTasks = useMemo(() => (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at), [state.snapshot?.tasks]);
  const viewerId = state.snapshot?.viewer_user_id ?? '';
  const memberNames = useMemo(() => new Map((state.snapshot?.members ?? []).map((member) => [member.user_id, member.display_name ?? member.user_id])), [state.snapshot?.members]);
  const transferTaskIds = useMemo(() => new Set((state.snapshot?.approval_requests ?? [])
    .filter((request) => request.status === 'PENDING' && request.request_type === 'HANDLER_TRANSFER' && request.task_id)
    .map((request) => request.task_id as string)), [state.snapshot?.approval_requests]);
  const tasks = useMemo(() => applyFilters(sourceTasks, filters, query, scope, viewerId, memberNames, transferTaskIds), [filters, memberNames, query, scope, sourceTasks, transferTaskIds, viewerId]);
  const busy = state.loading || state.stale || state.authRequired;
  const completeTask = useCallback((task: TaskItem): void => {
    if (busy || readOnly) return;
    const targetStatus = normalizedTaskStatus(task.status) === 'TODO' ? 'IN_PROGRESS' : 'REVIEW';
    void sync.transitionTask(task.id, targetStatus);
  }, [busy, readOnly, sync]);

  return (
    <main className="all-tasks-page" data-all-tasks-page>
      <header className="all-tasks-page__intro" data-all-tasks-section="intro">
        <h1>全部事情</h1>
        <p>把所有行动放在一条清晰的列表里。</p>
      </header>

      <div className="all-tasks-page__sync" data-all-tasks-section="sync">
        <SyncStatus loading={state.loading} stale={state.stale} error={state.error} />
      </div>

      {!readOnly ? <section className="all-tasks-page__section all-tasks-page__composer" data-all-tasks-section="composer">
        <TaskComposer sync={sync} onCreateTask={onCreateTask} />
      </section> : null}

      <section className="all-tasks-page__section" data-all-tasks-section="filters">
        <div className="all-tasks-page__search-controls">
          <label className="all-tasks-page__search-field">
            <span>搜索</span>
            <input
              type="search"
              aria-label="搜索全部事情"
              placeholder="搜索名称、分类、负责人或下一步"
              value={query}
              disabled={busy}
              onChange={(event) => setQuery(event.target.value)}
            />
          </label>
          <label className="all-tasks-page__scope-field">
            <span>任务范围</span>
            <select aria-label="任务范围" value={scope} disabled={busy} onChange={(event) => setScope(event.target.value as TaskScope)}>
              <option value="open">未完成</option>
              <option value="all">全部</option>
              <option value="blocked">阻塞</option>
              <option value="review">验收</option>
              <option value="transfer">接棒</option>
              <option value="done">完成</option>
            </select>
          </label>
        </div>
        <TaskFilters value={filters} onChange={setFilters} disabled={busy} />
      </section>

      <section className="all-tasks-page__section" data-all-tasks-section="list">
        <SectionHeading>任务列表</SectionHeading>
        <TaskList
          tasks={tasks}
          emptyMessage={sourceTasks.length === 0 ? '还没有任务，记下一件事开始吧。' : '没有符合筛选条件的任务'}
          onOpen={onOpenTask}
          onComplete={completeTask}
          busy={busy || readOnly}
          showPrimaryAction={!readOnly}
        />
      </section>
    </main>
  );
}

function applyFilters(
  tasks: TaskItem[],
  filters: TaskFilterValues,
  query: string,
  scope: TaskScope,
  viewerId: string,
  memberNames: Map<string, string>,
  transferTaskIds: Set<string>,
): TaskItem[] {
  const labelQuery = filters.label.trim().toLocaleLowerCase();
  const searchQuery = query.trim().toLocaleLowerCase();

  return tasks.filter((task) => {
    const status = normalizedTaskStatus(task.status);
    if (filters.status && status !== filters.status) return false;
    if (filters.quadrant && task.quadrant !== filters.quadrant) return false;
    if (filters.owner === 'mine' && task.current_handler_id !== viewerId) return false;
    if (filters.owner === 'other' && task.current_handler_id === viewerId) return false;
    if (labelQuery && !task.labels.some((label) => label.toLocaleLowerCase().includes(labelQuery))) return false;
    if (searchQuery) {
      const searchable = [task.title, ...task.labels, memberNames.get(task.current_handler_id) ?? task.current_handler_id, task.next_step_text ?? ''];
      if (!searchable.some((value) => value.toLocaleLowerCase().includes(searchQuery))) return false;
    }
    if (scope === 'open' && !['TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW'].includes(status ?? '')) return false;
    if (scope === 'blocked' && status !== 'BLOCKED') return false;
    if (scope === 'review' && status !== 'REVIEW') return false;
    if (scope === 'transfer' && !transferTaskIds.has(task.id)) return false;
    if (scope === 'done' && status !== 'DONE') return false;
    return true;
  });
}
