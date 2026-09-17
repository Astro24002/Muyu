import { Archive, CalendarDays, Check, ChevronDown, Grid2X2, ListChecks } from 'lucide-react';
import { useCallback, useMemo, useState, type JSX } from 'react';
import type { TaskItem } from '../api/types';
import { navigate } from '../app/routes';
import { useWorkspaceState } from '../app/use-external-state';
import { InlineApprovalNotice } from '../components/approvals/InlineApprovalNotice';
import { SyncStatus } from '../components/status/SyncStatus';
import { TaskComposer, type CreateTaskHandler } from '../components/tasks/TaskComposer';
import { TaskList } from '../components/tasks/TaskList';
import { SectionHeading } from '../components/ui/SectionHeading';
import { normalizedTaskStatus } from '../tasks/task-status';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export type MatterView = 'moment' | 'quadrant' | 'schedule';

export interface MattersPageProps {
  sync: WorkspaceSyncController;
  view?: MatterView;
  onOpenTask: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
}

const VIEW_OPTIONS: Array<{ value: MatterView; label: string; menuLabel: string; icon: JSX.Element }> = [
  { value: 'moment', label: '此刻', menuLabel: '清单', icon: <ListChecks aria-hidden="true" size={15} /> },
  { value: 'quadrant', label: '四象限', menuLabel: '四象限', icon: <Grid2X2 aria-hidden="true" size={15} /> },
  { value: 'schedule', label: '日程', menuLabel: '日程', icon: <CalendarDays aria-hidden="true" size={15} /> },
];

export function MattersPage({ sync, view = 'moment', onOpenTask, onCreateTask }: MattersPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [viewMenuOpen, setViewMenuOpen] = useState(false);
  const tasks = useMemo(() => (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at), [state.snapshot?.tasks]);
  const busy = state.loading || state.stale || state.authRequired;

  const advanceTask = useCallback((task: TaskItem): void => {
    if (busy) return;
    const targetStatus = normalizedTaskStatus(task.status) === 'TODO' ? 'IN_PROGRESS' : 'REVIEW';
    void sync.transitionTask(task.id, targetStatus);
  }, [busy, sync]);

  return (
    <main className="matters-page" data-matters-page data-matters-view={view}>
      <header className="matters-page__header">
        <div className="matters-page__title">
          <p className="matters-page__eyebrow">事项</p>
          <div className="matters-page__title-row">
            <h1>{viewLabel(view)}</h1>
            <div className="matters-page__view-menu">
              <button
                type="button"
                className="matters-page__view-trigger"
                aria-haspopup="menu"
                aria-expanded={viewMenuOpen}
                onClick={() => setViewMenuOpen((open) => !open)}
              >
                <span>切换视图</span>
                <ChevronDown aria-hidden="true" size={15} />
              </button>
              {viewMenuOpen ? (
                <div className="matters-page__view-popover" role="menu" aria-label="事项视图">
                  {VIEW_OPTIONS.map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      role="menuitemradio"
                      aria-checked={option.value === view}
                      className={option.value === view ? 'matters-page__view-option matters-page__view-option--active' : 'matters-page__view-option'}
                      onClick={() => {
                        setViewMenuOpen(false);
                        navigate({ kind: 'matters', view: option.value });
                      }}
                    >
                      {option.icon}
                      <span>{option.menuLabel}</span>
                      {option.value === view ? <Check aria-hidden="true" size={14} /> : null}
                    </button>
                  ))}
                </div>
              ) : null}
            </div>
          </div>
        </div>
        <button type="button" className="matters-page__all-tasks" onClick={() => navigate({ kind: 'all-tasks' })}>
          <Archive aria-hidden="true" size={16} />
          <span>全部事情</span>
        </button>
      </header>

      <div className="matters-page__sync">
        <SyncStatus loading={state.loading} stale={state.stale} error={state.error} />
      </div>

      {view === 'moment' ? (
        <MomentView
          state={state}
          sync={sync}
          tasks={tasks}
          busy={busy}
          onOpenTask={onOpenTask}
          onAdvance={advanceTask}
          onCreateTask={onCreateTask}
        />
      ) : view === 'quadrant' ? (
        <QuadrantView tasks={tasks} busy={busy} onOpenTask={onOpenTask} onAdvance={advanceTask} />
      ) : (
        <ScheduleView tasks={tasks} busy={busy} onOpenTask={onOpenTask} onAdvance={advanceTask} />
      )}
    </main>
  );
}

function MomentView({ state, sync, tasks, busy, onOpenTask, onAdvance, onCreateTask }: {
  state: ReturnType<typeof useWorkspaceState>;
  sync: WorkspaceSyncController;
  tasks: TaskItem[];
  busy: boolean;
  onOpenTask: (task: TaskItem) => void;
  onAdvance: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
}): JSX.Element {
  const home = state.home;
  const rawSections = [
    { key: 'blocked', label: '卡住的事情', tasks: home?.moment?.blocked?.items ?? home?.moment?.blocked_tasks?.items ?? tasks.filter((task) => normalizedTaskStatus(task.status) === 'BLOCKED') },
    { key: 'mine', label: '我在推进', tasks: home?.moment?.mine?.items ?? home?.moment?.my_tasks?.items ?? tasks.filter((task) => task.current_handler_id === state.snapshot?.viewer_user_id && !['BLOCKED', 'DONE', 'CANCELLED'].includes(normalizedTaskStatus(task.status) ?? 'TODO')) },
    { key: 'other', label: 'TA 在推进', tasks: home?.moment?.other?.items ?? home?.moment?.other_tasks?.items ?? tasks.filter((task) => task.current_handler_id !== state.snapshot?.viewer_user_id && !['BLOCKED', 'DONE', 'CANCELLED'].includes(normalizedTaskStatus(task.status) ?? 'TODO')) },
  ];
  const seen = new Set<string>();
  const sections = rawSections.map((section) => ({
    ...section,
    tasks: section.tasks.filter((task) => {
      if (seen.has(task.id)) return false;
      seen.add(task.id);
      return true;
    }),
  }));
  const approvals = home?.entries?.needs_me?.items ?? [];

  return (
    <>
      <div className="matters-page__metrics" aria-label="事项入口指标">
        <Metric label="需要我处理" value={home?.entry_counts?.needs_me ?? 0} />
        <Metric label="等对方" value={home?.entry_counts?.waiting_on_other ?? 0} />
        <Metric label="本周到期" value={home?.entry_counts?.due_this_week ?? 0} />
      </div>
      {sections.map((section) => (
        <section key={section.key} className="matters-page__section" aria-labelledby={`matters-${section.key}-heading`}>
          <SectionHeading id={`matters-${section.key}-heading`}>{section.label}</SectionHeading>
          <TaskList tasks={section.tasks} emptyMessage="这里暂时没有事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} />
        </section>
      ))}
      {approvals.length > 0 ? <InlineApprovalNotice count={approvals.length} onOpen={() => navigate('approvals')} /> : null}
      <section className="matters-page__section matters-page__composer" aria-label="新增事项">
        <TaskComposer sync={sync} onCreateTask={onCreateTask} />
      </section>
    </>
  );
}

function QuadrantView({ tasks, busy, onOpenTask, onAdvance }: ViewProps & { tasks: TaskItem[] }): JSX.Element {
  const groups = ['Q1', 'Q2', 'Q3', 'Q4'].map((quadrant) => ({
    quadrant,
    tasks: tasks.filter((task) => task.quadrant === quadrant && task.status !== 'DONE' && task.status !== 'CANCELLED'),
  }));
  return <div className="matters-page__quadrants">{groups.map((group) => <section key={group.quadrant} className="matters-page__section"><SectionHeading>{quadrantLabel(group.quadrant)}</SectionHeading><TaskList tasks={group.tasks} emptyMessage="这里暂时没有事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} /></section>)}</div>;
}

function ScheduleView({ tasks, busy, onOpenTask, onAdvance }: ViewProps & { tasks: TaskItem[] }): JSX.Element {
  const groups = new Map<string, TaskItem[]>();
  for (const task of tasks.filter((item) => item.status !== 'DONE' && item.status !== 'CANCELLED')) {
    const key = task.due_at ? new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'short' }).format(new Date(task.due_at)) : '未安排日期';
    groups.set(key, [...(groups.get(key) ?? []), task]);
  }
  return <div className="matters-page__schedule">{groups.size === 0 ? <p className="task-list__empty" role="status">这里暂时没有事项</p> : [...groups].map(([date, dateTasks]) => <section key={date} className="matters-page__section"><SectionHeading>{date}</SectionHeading><TaskList tasks={dateTasks} emptyMessage="这里暂时没有事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} /></section>)}</div>;
}

type ViewProps = { busy: boolean; onOpenTask: (task: TaskItem) => void; onAdvance: (task: TaskItem) => void };

function Metric({ label, value }: { label: string; value: number }): JSX.Element {
  return <div className="matters-page__metric"><strong>{value}</strong><span>{label}</span></div>;
}

function viewLabel(view: MatterView): string { return VIEW_OPTIONS.find((option) => option.value === view)?.label ?? '此刻'; }
function quadrantLabel(quadrant: string): string {
  return ({ Q1: '重要且紧急', Q2: '重要不紧急', Q3: '紧急不重要', Q4: '不重要不紧急' } as Record<string, string>)[quadrant] ?? quadrant;
}
