import { useCallback, useMemo, useState, type JSX } from 'react';
import type { TaskItem } from '../api/types';
import { useWorkspaceState } from '../app/use-external-state';
import { SyncStatus } from '../components/status/SyncStatus';
import { TaskComposer, type CreateTaskHandler } from '../components/tasks/TaskComposer';
import { TaskFilters, EMPTY_TASK_FILTERS, type TaskFilterValues } from '../components/tasks/TaskFilters';
import { TaskList } from '../components/tasks/TaskList';
import { SectionHeading } from '../components/ui/SectionHeading';
import { filterMyTasks } from '../tasks/task-view-model';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface AllTasksPageProps {
  sync: WorkspaceSyncController;
  onOpenTask: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
}

export function AllTasksPage({ sync, onOpenTask, onCreateTask }: AllTasksPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [filters, setFilters] = useState<TaskFilterValues>(EMPTY_TASK_FILTERS);
  const sourceTasks = (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at);
  const viewerId = state.snapshot?.viewer_user_id ?? '';
  const tasks = useMemo(() => applyFilters(sourceTasks, filters, viewerId), [filters, sourceTasks, viewerId]);
  const busy = state.loading || state.stale || state.authRequired;
  const completeTask = useCallback((task: TaskItem): void => {
    if (busy) return;
    void sync.transitionTask(task.id, 'DONE');
  }, [busy, sync]);

  return (
    <main className="all-tasks-page" data-all-tasks-page>
      <header className="all-tasks-page__intro" data-all-tasks-section="intro">
        <h1>所有任务</h1>
        <p>把所有行动放在一条清晰的列表里。</p>
      </header>

      <div className="all-tasks-page__sync" data-all-tasks-section="sync">
        <SyncStatus loading={state.loading} stale={state.stale} error={state.error} />
      </div>

      <section className="all-tasks-page__section all-tasks-page__composer" data-all-tasks-section="composer">
        <TaskComposer sync={sync} onCreateTask={onCreateTask} />
      </section>

      <section className="all-tasks-page__section" data-all-tasks-section="filters">
        <TaskFilters value={filters} onChange={setFilters} />
      </section>

      <section className="all-tasks-page__section" data-all-tasks-section="list">
        <SectionHeading>任务列表</SectionHeading>
        <TaskList
          tasks={tasks}
          emptyMessage={sourceTasks.length === 0 ? '还没有任务，记下一件事开始吧。' : '没有符合筛选条件的任务'}
          onOpen={onOpenTask}
          onComplete={completeTask}
          busy={busy}
        />
      </section>
    </main>
  );
}

function applyFilters(tasks: TaskItem[], filters: TaskFilterValues, viewerId: string): TaskItem[] {
  const labelQuery = filters.label.trim().toLocaleLowerCase();
  const ownedTasks = filters.myOnly ? new Set(filterMyTasks(tasks, viewerId).map((task) => task.id)) : null;

  return tasks.filter((task) => {
    if (filters.status && task.status !== filters.status) return false;
    if (filters.quadrant && task.quadrant !== filters.quadrant) return false;
    if (ownedTasks && !ownedTasks.has(task.id)) return false;
    if (labelQuery && !task.labels.some((label) => label.toLocaleLowerCase().includes(labelQuery))) return false;
    return true;
  });
}
