import { CalendarDays, Check, ChevronDown, ChevronLeft, ChevronRight, Grid2X2, ListChecks } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type JSX, type KeyboardEvent as ReactKeyboardEvent } from 'react';
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
export type QuadrantOwnerFilter = 'all' | 'mine' | 'other';

export interface MattersPageUiState {
  quadrantOwner: QuadrantOwnerFilter;
  calendarMonth: string;
  selectedDate: string;
}

export interface MattersPageProps {
  sync: WorkspaceSyncController;
  view?: MatterView;
  readOnly?: boolean;
  uiState?: MattersPageUiState;
  onUiStateChange?: (state: MattersPageUiState) => void;
  onOpenTask: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
}

const VIEW_OPTIONS: Array<{ value: MatterView; label: string; menuLabel: string; icon: JSX.Element }> = [
  { value: 'moment', label: '此刻', menuLabel: '清单', icon: <ListChecks aria-hidden="true" size={16} /> },
  { value: 'quadrant', label: '四象限', menuLabel: '四象限', icon: <Grid2X2 aria-hidden="true" size={16} /> },
  { value: 'schedule', label: '日程', menuLabel: '日程', icon: <CalendarDays aria-hidden="true" size={16} /> },
];

const QUADRANT_FILTERS: Array<{ value: QuadrantOwnerFilter; label: string }> = [
  { value: 'all', label: '我们' },
  { value: 'mine', label: '我负责' },
  { value: 'other', label: 'TA 负责' },
];

type MomentMetricKey = 'needs_me' | 'waiting_on_other' | 'due_soon';
const METRIC_LABELS: Record<MomentMetricKey, string> = {
  needs_me: '需要我处理',
  waiting_on_other: '等对方',
  due_soon: '即将到期',
};

export function createMattersPageUiState(now = new Date()): MattersPageUiState {
  const today = dateKey(now);
  return { quadrantOwner: 'all', calendarMonth: monthKey(now), selectedDate: today };
}

export function MattersPage({
  sync,
  view = 'moment',
  readOnly = false,
  uiState,
  onUiStateChange,
  onOpenTask,
  onCreateTask,
}: MattersPageProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [localUiState, setLocalUiState] = useState(() => createMattersPageUiState());
  const currentUiState = uiState ?? localUiState;
  const [viewMenuOpen, setViewMenuOpen] = useState(false);
  const menuRootRef = useRef<HTMLDivElement>(null);
  const viewTriggerRef = useRef<HTMLButtonElement>(null);
  const restoreFocusRef = useRef(false);
  const tasks = useMemo(() => (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at), [state.snapshot?.tasks]);
  const busy = readOnly || state.loading || state.stale || state.authRequired;

  const updateUiState = useCallback((patch: Partial<MattersPageUiState>): void => {
    const next = { ...currentUiState, ...patch };
    setLocalUiState(next);
    onUiStateChange?.(next);
  }, [currentUiState, onUiStateChange]);

  useEffect(() => {
    if (!viewMenuOpen) {
      if (restoreFocusRef.current) {
        restoreFocusRef.current = false;
        viewTriggerRef.current?.focus();
      }
      return undefined;
    }

    menuRootRef.current?.querySelector<HTMLButtonElement>('[aria-checked="true"]')?.focus();
    const closeOnOutsidePointer = (event: PointerEvent): void => {
      if (event.target instanceof Node && !menuRootRef.current?.contains(event.target)) setViewMenuOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent): void => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      restoreFocusRef.current = true;
      setViewMenuOpen(false);
    };

    document.addEventListener('pointerdown', closeOnOutsidePointer);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsidePointer);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [viewMenuOpen]);

  const advanceTask = useCallback((task: TaskItem): void => {
    if (busy) return;
    const targetStatus = normalizedTaskStatus(task.status) === 'TODO' ? 'IN_PROGRESS' : 'REVIEW';
    void sync.transitionTask(task.id, targetStatus);
  }, [busy, sync]);

  const focusViewOption = (event: ReactKeyboardEvent<HTMLButtonElement>): void => {
    if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
    event.preventDefault();
    const options = [...(menuRootRef.current?.querySelectorAll<HTMLButtonElement>('[role="menuitemradio"]') ?? [])];
    const current = options.indexOf(event.currentTarget);
    const offset = event.key === 'ArrowDown' ? 1 : -1;
    options[(current + offset + options.length) % options.length]?.focus();
  };

  const today = new Date();
  return (
    <main className="matters-page" data-matters-page data-matters-view={view}>
      <header className="matters-page__header">
        <div className="matters-page__title-row">
          <div className="matters-page__view-menu" ref={menuRootRef}>
            <h1>
              <button
                ref={viewTriggerRef}
                type="button"
                className="matters-page__view-trigger"
                aria-haspopup="menu"
                aria-expanded={viewMenuOpen}
                aria-label={viewLabel(view)}
                aria-controls={viewMenuOpen ? 'matters-view-menu' : undefined}
                onClick={() => setViewMenuOpen((open) => !open)}
                onKeyDown={(event) => {
                  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                    event.preventDefault();
                    setViewMenuOpen(true);
                  }
                }}
              >
                <span>{viewLabel(view)}</span>
                <ChevronDown aria-hidden="true" size={18} />
              </button>
            </h1>
            {viewMenuOpen ? (
              <div id="matters-view-menu" className="matters-page__view-popover" role="menu" aria-label="事项视图">
                {VIEW_OPTIONS.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    role="menuitemradio"
                    aria-checked={option.value === view}
                    className={option.value === view ? 'matters-page__view-option matters-page__view-option--active' : 'matters-page__view-option'}
                    onKeyDown={focusViewOption}
                    onClick={() => {
                      restoreFocusRef.current = true;
                      setViewMenuOpen(false);
                      if (option.value !== view) navigate({ kind: 'matters', view: option.value });
                    }}
                  >
                    {option.icon}
                    <span>{option.menuLabel}</span>
                    {option.value === view ? <Check aria-hidden="true" size={15} /> : null}
                  </button>
                ))}
              </div>
            ) : null}
          </div>
          {view === 'moment' ? <time className="matters-page__date" dateTime={dateKey(today)}>{formatShortDate(today)}</time> : null}
        </div>
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
          readOnly={readOnly}
          onOpenTask={onOpenTask}
          onAdvance={advanceTask}
          onCreateTask={onCreateTask}
          now={today}
        />
      ) : view === 'quadrant' ? (
        <QuadrantView
          tasks={tasks}
          busy={busy}
          filter={currentUiState.quadrantOwner}
          onFilterChange={(quadrantOwner) => updateUiState({ quadrantOwner })}
          viewerId={state.snapshot?.viewer_user_id ?? ''}
          onOpenTask={onOpenTask}
          onAdvance={advanceTask}
        />
      ) : (
        <ScheduleView
          tasks={tasks}
          busy={busy}
          uiState={currentUiState}
          onUiStateChange={updateUiState}
          onOpenTask={onOpenTask}
          onAdvance={advanceTask}
        />
      )}
    </main>
  );
}

function MomentView({ state, sync, tasks, busy, readOnly, onOpenTask, onAdvance, onCreateTask, now }: {
  state: ReturnType<typeof useWorkspaceState>;
  sync: WorkspaceSyncController;
  tasks: TaskItem[];
  busy: boolean;
  readOnly: boolean;
  onOpenTask: (task: TaskItem) => void;
  onAdvance: (task: TaskItem) => void;
  onCreateTask: CreateTaskHandler;
  now: Date;
}): JSX.Element {
  const [selectedMetric, setSelectedMetric] = useState<MomentMetricKey | null>(null);
  const [overdueExpanded, setOverdueExpanded] = useState(false);
  const home = state.home;
  const approvals = home?.entries?.needs_me?.items ?? [];
  const metricEntries = selectedMetric === 'needs_me'
    ? home?.entries?.needs_me
    : selectedMetric === 'waiting_on_other'
      ? home?.entries?.waiting_on_other
      : selectedMetric === 'due_soon'
        ? home?.entries?.due_soon
        : undefined;
  const metricTasks = selectedMetric === 'due_soon'
    ? home?.entries?.due_soon?.items ?? []
    : selectedMetric === 'needs_me'
      ? home?.entries?.needs_me?.items.map((item) => item.task).filter((task): task is TaskItem => task !== null) ?? []
      : selectedMetric === 'waiting_on_other'
        ? home?.entries?.waiting_on_other?.items.map((item) => item.task).filter((task): task is TaskItem => task !== null) ?? []
        : [];
  const hasMissingEntryTasks = selectedMetric !== 'due_soon'
    && (metricEntries?.items.some((item) => !('task' in item) || item.task === null) ?? false);
  const showMoreEntries = metricEntries?.has_more === true || hasMissingEntryTasks;
  const overdueTasks = tasks
    .filter((task) => {
      if (task.parent_task_id || !isOpenTask(task) || !task.due_at) return false;
      const dueAt = Date.parse(task.due_at);
      return Number.isFinite(dueAt) && dueAt < now.getTime();
    })
    .sort((left, right) => Date.parse(left.due_at!) - Date.parse(right.due_at!) || left.id.localeCompare(right.id));
  const completedTasks = tasks
    .filter((task) => !task.parent_task_id && normalizedTaskStatus(task.status) === 'DONE')
    .sort((left, right) => right.updated_at.localeCompare(left.updated_at) || left.id.localeCompare(right.id));

  return (
    <>
      <div className="matters-page__metrics" aria-label="事项入口指标">
        <Metric label={METRIC_LABELS.needs_me} value={home?.entry_counts?.needs_me ?? 0} selected={selectedMetric === 'needs_me'} onClick={() => setSelectedMetric((current) => current === 'needs_me' ? null : 'needs_me')} />
        <Metric label={METRIC_LABELS.waiting_on_other} value={home?.entry_counts?.waiting_on_other ?? 0} selected={selectedMetric === 'waiting_on_other'} onClick={() => setSelectedMetric((current) => current === 'waiting_on_other' ? null : 'waiting_on_other')} />
        <Metric label={METRIC_LABELS.due_soon} value={home?.entry_counts?.due_soon ?? 0} selected={selectedMetric === 'due_soon'} onClick={() => setSelectedMetric((current) => current === 'due_soon' ? null : 'due_soon')} />
      </div>
      {selectedMetric ? (
        <section className="matters-page__metric-detail" aria-label={METRIC_LABELS[selectedMetric]}>
          <div className="matters-page__metric-detail-heading">
            <SectionHeading>{METRIC_LABELS[selectedMetric]}</SectionHeading>
            <button type="button" className="matters-page__metric-close" aria-label="收起指标详情" onClick={() => setSelectedMetric(null)}>收起</button>
          </div>
          <TaskList tasks={metricTasks} emptyMessage="目前没有待处理事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} showPrimaryAction={selectedMetric === 'due_soon'} />
          {showMoreEntries ? (
            <button type="button" className="matters-page__metric-more" onClick={() => navigate(selectedMetric === 'due_soon' ? { kind: 'all-tasks' } : 'approvals')}>
              {selectedMetric === 'due_soon' ? '查看更多事项' : '打开审批'}
            </button>
          ) : null}
        </section>
      ) : (
        <>
          <section className="matters-page__section" aria-labelledby="matters-overdue-heading">
            <div className="matters-page__collapsible-heading">
              <SectionHeading id="matters-overdue-heading">已经过期</SectionHeading>
              <span className="matters-page__collapsible-count">{overdueTasks.length} 项</span>
              <button
                type="button"
                className="matters-page__collapsible-toggle"
                aria-label={overdueExpanded ? '收起已经过期清单' : '展开已经过期清单'}
                aria-expanded={overdueExpanded}
                aria-controls="matters-overdue-list"
                title={overdueExpanded ? '收起已经过期清单' : '展开已经过期清单'}
                onClick={() => setOverdueExpanded((expanded) => !expanded)}
              >
                {overdueExpanded ? <ChevronDown aria-hidden="true" size={20} /> : <ChevronRight aria-hidden="true" size={20} />}
              </button>
            </div>
            <div id="matters-overdue-list" hidden={!overdueExpanded}>
              {overdueExpanded ? <TaskList tasks={overdueTasks} emptyMessage="目前没有已经过期的事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} /> : null}
            </div>
          </section>
          <section className="matters-page__section" aria-labelledby="matters-completed-heading">
            <SectionHeading id="matters-completed-heading">已完成/已归档</SectionHeading>
            <TaskList tasks={completedTasks} emptyMessage="暂无已完成或已归档的事情" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} showPrimaryAction={false} />
          </section>
          {approvals.length > 0 ? <InlineApprovalNotice count={approvals.length} onOpen={() => navigate('approvals')} /> : null}
          {!readOnly ? (
            <section className="matters-page__section matters-page__composer" aria-label="新增事项">
              <TaskComposer sync={sync} onCreateTask={onCreateTask} />
            </section>
          ) : null}
        </>
      )}
    </>
  );
}

function QuadrantView({ tasks, busy, filter, onFilterChange, viewerId, onOpenTask, onAdvance }: ViewProps & {
  tasks: TaskItem[];
  filter: QuadrantOwnerFilter;
  onFilterChange: (filter: QuadrantOwnerFilter) => void;
  viewerId: string;
}): JSX.Element {
  const visibleTasks = tasks.filter((task) => {
    if (!isOpenTask(task)) return false;
    if (filter === 'mine') return task.current_handler_id === viewerId;
    if (filter === 'other') return task.current_handler_id !== viewerId;
    return true;
  });
  const groups = ['Q1', 'Q2', 'Q3', 'Q4'].map((quadrant) => ({
    quadrant,
    tasks: visibleTasks.filter((task) => task.quadrant === quadrant),
  }));
  return (
    <>
      <div className="matters-page__owner-filter" role="group" aria-label="负责人筛选">
        {QUADRANT_FILTERS.map((option) => (
          <button key={option.value} type="button" aria-pressed={filter === option.value} onClick={() => onFilterChange(option.value)}>
            {option.label}
          </button>
        ))}
      </div>
      <div className="matters-page__quadrants">
        {groups.map((group) => (
          <section key={group.quadrant} className="matters-page__section" aria-label={quadrantLabel(group.quadrant)}>
            <SectionHeading>{quadrantLabel(group.quadrant)}</SectionHeading>
            <TaskList tasks={group.tasks} emptyMessage="这里暂时没有事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} />
          </section>
        ))}
      </div>
    </>
  );
}

function ScheduleView({ tasks, busy, uiState, onUiStateChange, onOpenTask, onAdvance }: ViewProps & {
  tasks: TaskItem[];
  uiState: MattersPageUiState;
  onUiStateChange: (patch: Partial<MattersPageUiState>) => void;
}): JSX.Element {
  const month = parseDateKey(uiState.calendarMonth);
  const selectedDate = parseDateKey(uiState.selectedDate);
  const today = startOfDay(new Date());
  const todayKey = dateKey(today);
  const calendarGridRef = useRef<HTMLDivElement>(null);
  const focusDateRef = useRef<string | null>(null);
  const openDatedTasks = tasks.filter((task) => isOpenTask(task) && task.due_at !== null && Number.isFinite(Date.parse(task.due_at)));
  const countsByDate = new Map<string, number>();
  for (const task of openDatedTasks) {
    const key = dateKey(new Date(task.due_at as string));
    countsByDate.set(key, (countsByDate.get(key) ?? 0) + 1);
  }
  const firstGridDay = addDays(startOfMonth(month), -((startOfMonth(month).getDay() + 6) % 7));
  const calendarDays = Array.from({ length: 42 }, (_, index) => addDays(firstGridDay, index));
  const selectedDateKey = dateKey(selectedDate);
  const selectedTasks = openDatedTasks.filter((task) => dateKey(new Date(task.due_at as string)) === selectedDateKey);
  const monthTitle = new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long' }).format(month);
  const selectedLabel = new Intl.DateTimeFormat('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }).format(selectedDate);

  useEffect(() => {
    if (focusDateRef.current !== selectedDateKey) return;
    calendarGridRef.current?.querySelector<HTMLButtonElement>(`[data-calendar-date="${selectedDateKey}"]`)?.focus();
    focusDateRef.current = null;
  }, [selectedDateKey, uiState.calendarMonth]);

  const changeSelectedDate = (date: Date, moveFocus = false): void => {
    if (moveFocus) focusDateRef.current = dateKey(date);
    onUiStateChange({ selectedDate: dateKey(date), calendarMonth: monthKey(date) });
  };
  const changeMonth = (amount: number, moveFocus = false): void => {
    const selectedDay = selectedDate.getDate();
    const nextMonth = new Date(month.getFullYear(), month.getMonth() + amount, 1);
    const lastDay = new Date(nextMonth.getFullYear(), nextMonth.getMonth() + 1, 0).getDate();
    const nextSelection = new Date(nextMonth.getFullYear(), nextMonth.getMonth(), Math.min(selectedDay, lastDay));
    if (moveFocus) focusDateRef.current = dateKey(nextSelection);
    onUiStateChange({ calendarMonth: monthKey(nextMonth), selectedDate: dateKey(nextSelection) });
  };
  const onCalendarKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, day: Date): void => {
    let next: Date | null = null;
    if (event.key === 'ArrowLeft') next = addDays(day, -1);
    if (event.key === 'ArrowRight') next = addDays(day, 1);
    if (event.key === 'ArrowUp') next = addDays(day, -7);
    if (event.key === 'ArrowDown') next = addDays(day, 7);
    if (event.key === 'Home') next = addDays(day, -((day.getDay() + 6) % 7));
    if (event.key === 'End') next = addDays(day, 6 - ((day.getDay() + 6) % 7));
    if (event.key === 'PageUp') {
      event.preventDefault();
      changeMonth(-1, true);
      return;
    }
    if (event.key === 'PageDown') {
      event.preventDefault();
      changeMonth(1, true);
      return;
    }
    if (!next) return;
    event.preventDefault();
    changeSelectedDate(next, true);
  };

  return (
    <div className="matters-page__schedule">
      <section className="matters-page__calendar" aria-label="日程月历">
        <div className="matters-page__calendar-header">
          <button type="button" aria-label="上个月" onClick={() => changeMonth(-1)}><ChevronLeft aria-hidden="true" size={18} /></button>
          <h2>{monthTitle}</h2>
          <button type="button" aria-label="下个月" onClick={() => changeMonth(1)}><ChevronRight aria-hidden="true" size={18} /></button>
        </div>
        <div ref={calendarGridRef} className="matters-page__calendar-grid" role="grid" aria-label={monthTitle}>
          <div className="matters-page__calendar-row" role="row">
            {['周一', '周二', '周三', '周四', '周五', '周六', '周日'].map((day) => <span key={day} role="columnheader">{day}</span>)}
          </div>
          {Array.from({ length: 6 }, (_, weekIndex) => (
            <div className="matters-page__calendar-row" role="row" key={weekIndex}>
              {calendarDays.slice(weekIndex * 7, weekIndex * 7 + 7).map((day) => {
                const key = dateKey(day);
                const count = countsByDate.get(key) ?? 0;
                const selected = key === selectedDateKey;
                const todayMatch = key === todayKey;
                const classes = [
                  'matters-page__calendar-day',
                  day.getMonth() === month.getMonth() ? undefined : 'matters-page__calendar-day--outside',
                  todayMatch ? 'matters-page__calendar-day--today' : undefined,
                  selected ? 'matters-page__calendar-day--selected' : undefined,
                ].filter(Boolean).join(' ');
                const dayLabel = new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric' }).format(day);
                return (
                  <div key={key} role="gridcell" aria-selected={selected}>
                    <button
                      type="button"
                      className={classes}
                      aria-label={`${dayLabel}${count > 0 ? `，${count}项到期事项` : ''}`}
                      aria-pressed={selected}
                      data-has-tasks={count > 0 ? 'true' : undefined}
                      data-calendar-date={key}
                      tabIndex={selected ? 0 : -1}
                      onClick={() => changeSelectedDate(day)}
                      onKeyDown={(event) => onCalendarKeyDown(event, day)}
                    >
                      <span>{day.getDate()}</span>
                      {count > 0 ? <span className="matters-page__calendar-dot" aria-hidden="true" /> : null}
                    </button>
                  </div>
                );
              })}
            </div>
          ))}
        </div>
        <div className="matters-page__selected-date">
          <SectionHeading>{selectedLabel}</SectionHeading>
          <button type="button" className="matters-page__today-button" onClick={() => onUiStateChange({ calendarMonth: monthKey(today), selectedDate: todayKey })}>回到今天</button>
        </div>
      </section>
      <section className="matters-page__section" aria-label={`${selectedLabel}到期事项`}>
        <TaskList tasks={selectedTasks} emptyMessage="这一天没有到期事项" onOpen={onOpenTask} onComplete={onAdvance} busy={busy} />
      </section>
    </div>
  );
}

type ViewProps = { busy: boolean; onOpenTask: (task: TaskItem) => void; onAdvance: (task: TaskItem) => void };

function Metric({ label, value, selected, onClick }: { label: string; value: number; selected: boolean; onClick: () => void }): JSX.Element {
  return (
    <button type="button" className="matters-page__metric" aria-expanded={selected} onClick={onClick}>
      <strong>{value}</strong>
      <span>{label}</span>
    </button>
  );
}

function viewLabel(view: MatterView): string { return VIEW_OPTIONS.find((option) => option.value === view)?.label ?? '此刻'; }
function quadrantLabel(quadrant: string): string {
  return ({ Q1: '重要且紧急', Q2: '重要不紧急', Q3: '紧急不重要', Q4: '不重要不紧急' } as Record<string, string>)[quadrant] ?? quadrant;
}

function isOpenTask(task: TaskItem): boolean {
  const status = normalizedTaskStatus(task.status);
  return status !== 'DONE' && status !== 'CANCELLED';
}

function dateKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function monthKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-01`;
}

function parseDateKey(key: string): Date {
  const [year, month, day] = key.split('-').map(Number);
  return new Date(year, (month ?? 1) - 1, day ?? 1);
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

function addDays(date: Date, amount: number): Date {
  const result = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  result.setDate(result.getDate() + amount);
  return result;
}

function formatShortDate(date: Date): string {
  return new Intl.DateTimeFormat('zh-CN', { month: 'long', day: 'numeric', weekday: 'short' }).format(date);
}
