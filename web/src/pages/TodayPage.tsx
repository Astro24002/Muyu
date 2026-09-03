import { useCallback, type JSX } from 'react';
import type { TaskItem } from '../api/types';
import { useWorkspaceState } from '../app/use-external-state';
import { InlineApprovalNotice } from '../components/approvals/InlineApprovalNotice';
import { TaskComposer, type CreateTaskHandler } from '../components/tasks/TaskComposer';
import { TaskList } from '../components/tasks/TaskList';
import { SectionHeading } from '../components/ui/SectionHeading';
import { SyncStatus } from '../components/status/SyncStatus';
import { navigate } from '../app/routes';
import { deriveTodayModel } from '../tasks/task-view-model';
import { normalizedTaskStatus } from '../tasks/task-status';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface TodayPageProps {
  sync: WorkspaceSyncController;
  onOpenTask: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
}

export function TodayPage({ sync, onOpenTask, onCreateTask }: TodayPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const tasks = (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at);
  const viewerId = state.snapshot?.viewer_user_id ?? '';
  const approvals = state.approvals ?? state.snapshot?.approval_requests ?? [];
  const model = deriveTodayModel(tasks, approvals, viewerId, new Date(), state.home);
  const busy = state.loading || state.stale || state.authRequired;
  const completeTask = useCallback((task: TaskItem): void => {
    if (busy) return;
    const targetStatus = normalizedTaskStatus(task.status) === 'TODO' ? 'IN_PROGRESS' : 'REVIEW';
    void sync.transitionTask(task.id, targetStatus);
  }, [busy, sync]);

  return (
    <main className="today-page" data-today-page>
      <header className="today-page__intro" data-today-section="intro">
        <p className="today-page__date" data-testid="today-date">{formatTodayDate(new Date())}</p>
        <h1>今天，先让一件事向前走</h1>
        <p className="today-page__copy">不用清空列表，完成真正重要的一步就好</p>
      </header>

      <div className="today-page__sync" data-today-section="sync">
        <SyncStatus loading={state.loading} stale={state.stale} error={state.error} />
      </div>

      <section className="today-page__section" data-today-section="current">
        <SectionHeading>当前任务{model.current.length > 0 ? ` ${model.current.length}${model.currentHasMore ? '+' : ''}` : ''}</SectionHeading>
        {model.current.length === 0 ? (
          <p className="today-page__empty" role="status">今天没有需要处理的任务</p>
        ) : (
          <TaskList tasks={model.current} emptyMessage="当前没有需要处理的任务" onOpen={onOpenTask} onComplete={completeTask} busy={busy} />
        )}
      </section>

      {model.blocked.length > 0 ? (
        <section className="today-page__section" data-today-section="blocked">
          <SectionHeading>当前阻塞 {model.blocked.length}{model.blockedHasMore ? '+' : ''}</SectionHeading>
          <TaskList tasks={model.blocked} emptyMessage="暂时没有阻塞中的任务" onOpen={onOpenTask} onComplete={completeTask} busy={busy} />
        </section>
      ) : null}

      {model.review.length > 0 ? (
        <section className="today-page__section" data-today-section="review">
          <SectionHeading>待我验收 {model.review.length}{model.reviewHasMore ? '+' : ''}</SectionHeading>
          <TaskList tasks={model.review} emptyMessage="暂时没有待验收的任务" onOpen={onOpenTask} onComplete={completeTask} busy={busy} />
        </section>
      ) : null}

      {model.pendingApprovalCount > 0 ? (
        <section className="today-page__section" data-today-section="approval">
          <InlineApprovalNotice count={model.pendingApprovalCount} onOpen={() => navigate('approvals')} />
        </section>
      ) : null}

      <section className="today-page__section today-page__composer" data-today-section="composer">
        <TaskComposer sync={sync} onCreateTask={onCreateTask} />
      </section>
    </main>
  );
}

function formatTodayDate(now: Date): string {
  return new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' }).format(now);
}
