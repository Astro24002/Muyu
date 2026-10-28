import { ChevronLeft } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type JSX } from 'react';
import type { ApiClient } from '../api/client';
import type { Anniversary, Habit, HabitCheckin, HomeResponse, LedgerEntry, LedgerEntryType, LedgerSummary, TaskItem, WebSessionSummary, WorkspaceSnapshot } from '../api/types';
import { navigate, parseHash, type Route } from '../app/routes';
import { AppShell } from '../components/layout/AppShell';
import type { WebSessionApi } from '../components/account/web-session-api';
import { ActivityPage } from './ActivityPage';
import { AllTasksPage } from './AllTasksPage';
import { CheckinsPage } from './CheckinsPage';
import { LedgerPage } from './LedgerPage';
import { MattersPage, createMattersPageUiState, type MattersPageUiState } from './MattersPage';
import { MyPage } from './MyPage';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';

const PREVIEW_STATE = createPreviewState();
const PREVIEW_SYNC = {
  state: PREVIEW_STATE,
  subscribe: () => () => undefined,
  transitionTask: async () => undefined,
  createTask: async () => undefined,
} as unknown as WorkspaceSyncController;

export function MattersPreviewPage(): JSX.Element {
  const [route, setRoute] = useState<Route>(readPreviewRoute);
  const [allTasksSource, setAllTasksSource] = useState<Route>({ kind: 'matters', view: 'moment' });
  const [uiState, setUiState] = useState<MattersPageUiState>(() => createMattersPageUiState());
  const [selectedTask, setSelectedTask] = useState<TaskItem | null>(null);
  const [domainData, setDomainData] = useState<PreviewDomainData>(() => createPreviewDomainData());
  const domainDataRef = useRef(domainData);
  domainDataRef.current = domainData;
  const previousRouteRef = useRef(route);
  const lastViewRef = useRef<'moment' | 'quadrant' | 'schedule'>('moment');
  const tasks = PREVIEW_STATE.snapshot?.tasks ?? [];
  const updateDomainData = (update: (current: PreviewDomainData) => PreviewDomainData): void => {
    const next = update(domainDataRef.current);
    domainDataRef.current = next;
    setDomainData(next);
  };
  const api = useMemo(() => createPreviewApi(() => domainDataRef.current, updateDomainData), []);
  const sessionApi = useMemo(() => createPreviewSessionApi(), []);

  useEffect(() => {
    const onHashChange = (): void => setRoute(readPreviewRoute());
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  useEffect(() => {
    if (route.kind === 'matters') lastViewRef.current = route.view ?? 'moment';
  }, [route]);

  useEffect(() => {
    if (route.kind === 'all-tasks' && previousRouteRef.current.kind !== 'all-tasks') {
      setAllTasksSource(previousRouteRef.current);
    }
    if (route.kind !== 'all-tasks') previousRouteRef.current = route;
  }, [route]);

  useEffect(() => {
    if (!selectedTask) return undefined;
    const closeOnEscape = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') setSelectedTask(null);
    };
    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [selectedTask]);

  const view = route.kind === 'matters' ? route.view ?? 'moment' : 'moment';
  const displayRoute = route.kind === 'today' || route.kind === 'tasks'
    ? { kind: 'matters' as const, view: 'moment' as const }
    : route;
  const routeKey = displayRoute.kind === 'matters'
    ? `matters-${displayRoute.view ?? 'moment'}`
    : displayRoute.kind;
  return (
    <div data-testid="muyu-app" data-route={routeKey}>
      <aside className="matters-preview__notice" role="status">
        <strong>本地界面预览</strong>
        <span>示例数据 · 操作仅在当前页面有效 · 不连接生产 API</span>
      </aside>
      <AppShell
        route={displayRoute}
        onNavigate={navigate}
        onLogout={() => undefined}
        sessionApi={sessionApi}
        pendingApprovalCount={2}
      >
        {displayRoute.kind === 'all-tasks' ? (
          <div className="matters-preview__all-tasks">
            <button type="button" className="matters-preview__back" onClick={() => navigate(allTasksSource)}>
              <ChevronLeft aria-hidden="true" size={18} />
              <span>返回{allTasksSource.kind === 'me' ? '我的' : '事项'}</span>
            </button>
            <AllTasksPage sync={PREVIEW_SYNC} onOpenTask={setSelectedTask} onCreateTask={() => undefined} readOnly />
          </div>
        ) : displayRoute.kind === 'matters' ? (
              <MattersPage
                sync={PREVIEW_SYNC}
                view={displayRoute.view ?? view}
                readOnly
                uiState={uiState}
                onUiStateChange={(patch) => setUiState((current) => ({ ...current, ...patch }))}
                onOpenTask={setSelectedTask}
                onCreateTask={() => undefined}
              />
        ) : displayRoute.kind === 'ledger' ? (
          <LedgerPage api={api} members={PREVIEW_STATE.snapshot?.members ?? []} viewerId="我" canWrite snapshotEntries={domainData.ledgerEntries} />
        ) : displayRoute.kind === 'checkins' ? (
          <CheckinsPage api={api} viewerId="我" canWrite snapshotHabits={domainData.habits} snapshotAnniversaries={domainData.anniversaries} />
        ) : displayRoute.kind === 'me' ? (
          <MyPage sessionApi={sessionApi} />
        ) : displayRoute.kind === 'activity' ? (
          <ActivityPage tasks={tasks} getTaskActivity={async () => []} workspaceKey="preview-workspace" />
        ) : displayRoute.kind === 'approvals' ? (
          <PreviewSubpage title="审批" description="示例审批请求会显示在事项首页的入口指标中。" onBack={() => navigate({ kind: 'matters', view: lastViewRef.current })} />
        ) : null}
      </AppShell>
      {selectedTask ? <TaskPreviewDialog task={selectedTask} onClose={() => setSelectedTask(null)} /> : null}
    </div>
  );
}

function PreviewSubpage({ title, description, onBack }: { title: string; description: string; onBack: () => void }): JSX.Element {
  return <main className="matters-page"><header className="matters-page__header"><div className="matters-page__title-row"><button type="button" className="matters-preview__back" onClick={onBack}><ChevronLeft aria-hidden="true" size={18} /><span>返回事项</span></button><h1>{title}</h1></div></header><p>{description}</p></main>;
}

function TaskPreviewDialog({ task, onClose }: { task: TaskItem; onClose: () => void }): JSX.Element {
  const handler = PREVIEW_STATE.snapshot?.members.find((member) => member.user_id === task.current_handler_id);
  return (
    <div className="matters-preview__overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <section className="matters-preview__dialog" role="dialog" aria-modal="true" aria-labelledby="matters-preview-task-title">
        <div className="matters-preview__dialog-heading">
          <h2 id="matters-preview-task-title">{task.title}</h2>
          <button type="button" aria-label="关闭任务详情" onClick={onClose}>关闭</button>
        </div>
        <p>{task.description || '暂无补充说明。'}</p>
        {task.next_step_text ? <p><strong>下一步：</strong>{task.next_step_text}</p> : null}
        <dl>
          <div><dt>负责人</dt><dd>{handler?.display_name ?? '成员'}</dd></div>
          <div><dt>状态</dt><dd>{previewStatus(task.status)}</dd></div>
          {task.blocked_reason ? <div><dt>卡住原因</dt><dd>{task.blocked_reason}</dd></div> : null}
        </dl>
      </section>
    </div>
  );
}

function createPreviewState(): WorkspaceSyncState {
  const now = new Date();
  const viewerId = '我';
  const partnerId = 'TA';
  const timestamp = now.toISOString();
  const task = (input: {
    id: string;
    number: string;
    title: string;
    status: TaskItem['status'];
    handler: string;
    quadrant: TaskItem['quadrant'];
    dueInDays: number;
    description: string;
    nextStep: string;
    blockedReason?: string;
    completedAt?: string;
  }): TaskItem => ({
    id: input.id,
    workspace_id: 'preview-workspace',
    parent_task_id: null,
    title: input.title,
    description: input.description,
    next_step_text: input.nextStep,
    acceptance_criteria: null,
    due_at: offsetDate(now, input.dueInDays),
    status: input.status,
    current_handler_id: input.handler,
    blocked_reason: input.blockedReason ?? null,
    blocked_since: input.blockedReason ? timestamp : null,
    resume_handler_id: null,
    waiting_for_user_id: null,
    reviewer_user_id: partnerId,
    review_submitted_at: null,
    reviewed_at: null,
    review_rejection_reason: null,
    planned_start_at: null,
    estimated_minutes: null,
    completed_at: input.completedAt ?? null,
    created_by: viewerId,
    created_at: timestamp,
    updated_at: timestamp,
    delay_count: 0,
    total_delay_minutes: 0,
    version: 1,
    status_version: 1,
    field_versions: {},
    lifecycle_version: 1,
    deleted_at: null,
    task_number: input.number,
    quadrant: input.quadrant,
    labels: ['生活'],
    progress: null,
  });

  const blocked = task({
    id: 'preview-blocked', number: '26090021', title: '确认周末采购安排', status: 'BLOCKED', handler: viewerId, quadrant: 'Q1', dueInDays: 2,
    description: '整理周末晚餐所需食材，确认购买安排。', nextStep: '确认食材到货时间。', blockedReason: '还没确认到货时间',
  });
  const mine = task({
    id: 'preview-mine', number: '26090022', title: '安排周末晚餐', status: 'IN_PROGRESS', handler: viewerId, quadrant: 'Q2', dueInDays: 1,
    description: '确定菜单并和 TA 对齐时间。', nextStep: '列出三道菜的备选菜单。',
  });
  const other = task({
    id: 'preview-other', number: '26090023', title: '确认周末出行路线', status: 'TODO', handler: partnerId, quadrant: 'Q1', dueInDays: 3,
    description: '整理适合当天往返的路线。', nextStep: '查看天气并确认出发时间。',
  });
  const done = task({
    id: 'preview-done', number: '26090020', title: '完成周末行程初稿', status: 'DONE', handler: viewerId, quadrant: 'Q2', dueInDays: -4,
    description: '已完成并确认行程初稿。', nextStep: '已完成。', completedAt: timestamp,
  });
  const tasks = [blocked, mine, other];
  const incoming = previewApproval('preview-approval-incoming', viewerId, partnerId, other, timestamp);
  const outgoing = previewApproval('preview-approval-outgoing', partnerId, viewerId, mine, timestamp);
  const snapshot: WorkspaceSnapshot = {
    workspace_id: 'preview-workspace',
    workspace: { id: 'preview-workspace', name: 'Muyu', status: 'ACTIVE' },
    members: [
      { user_id: viewerId, display_name: '我', member_slot: 1, membership_status: 'ACTIVE' },
      { user_id: partnerId, display_name: 'TA', member_slot: 2, membership_status: 'ACTIVE' },
    ],
    tasks: [...tasks, done],
    conflicts: [],
    cursor: 12,
    viewer_user_id: viewerId,
    comments: [],
    approval_requests: [incoming, outgoing],
    classifications: [{ id: 'preview-classification', workspace_id: 'preview-workspace', name: '生活', created_by: viewerId, created_at: timestamp }],
  };
  const home: HomeResponse = {
    viewer_user_id: viewerId,
    as_of: timestamp,
    entry_counts: { needs_me: 1, waiting_on_other: 1, due_this_week: 3, due_soon: 3 },
    moment: {
      blocked: { items: [blocked], has_more: false },
      mine: { items: [mine], has_more: false },
      other: { items: [other], has_more: false },
    },
    entries: {
      needs_me: { items: [{ approval_request: incoming, task: other }], has_more: false },
      waiting_on_other: { items: [{ approval_request: outgoing, task: mine }], has_more: false },
      due_this_week: { items: tasks, has_more: false },
      due_soon: { items: tasks, has_more: false },
    },
  };
  return { snapshot, cursor: snapshot.cursor, loading: false, stale: false, error: null, conflicts: [], authRequired: false, home };
}

interface PreviewDomainData {
  ledgerEntries: LedgerEntry[];
  habits: Habit[];
  anniversaries: Anniversary[];
  sequence: number;
}

type PreviewApi = Pick<ApiClient,
  | 'getLedgerSummary' | 'listLedger' | 'createLedger' | 'patchLedger' | 'deleteLedger'
  | 'listHabits' | 'createHabit' | 'patchHabit' | 'habitAction' | 'deleteHabit'
  | 'listAnniversaries' | 'createAnniversary' | 'patchAnniversary' | 'deleteAnniversary' | 'prepareAnniversary'
>;

function createPreviewDomainData(): PreviewDomainData {
  const now = new Date();
  const today = dateKey(now);
  const previousDay = offsetDay(now, -1);
  const recentDays = Array.from({ length: 7 }, (_, index) => offsetDay(now, index - 6));
  const viewerId = '我';
  const partnerId = 'TA';
  const members = PREVIEW_STATE.snapshot?.members ?? [];
  const entry = (id: string, type: LedgerEntryType, amount: string, title: string, category: string, payer: string, dayOffset: number): LedgerEntry => {
    const amountMinor = Math.round(Number(amount) * 100);
    const member = members.find((item) => item.user_id === payer);
    return {
      id,
      workspace_id: 'preview-workspace',
      type,
      amount_minor: amountMinor,
      amount: amountMinorToText(amountMinor),
      currency: 'CNY',
      title,
      category,
      payer_or_payee_id: payer,
      payer_or_payee_name: member?.display_name ?? payer,
      date: offsetDay(now, dayOffset),
      note: null,
      created_by: viewerId,
      updated_by: viewerId,
      version: 1,
      deleted_at: null,
    };
  };
  const anniversary = (id: string, title: string, offset: number, kind: Anniversary['kind'], prepareDays: number): Anniversary => {
    const occurrence = new Date(`${today}T12:00:00`);
    occurrence.setDate(occurrence.getDate() + offset);
    const occurrenceDate = dateKey(occurrence);
    return {
      id,
      workspace_id: 'preview-workspace',
      title,
      anchor_date: `2020-${occurrenceDate.slice(5)}`,
      kind,
      prepare_days: prepareDays,
      note: null,
      next_occurrence: occurrenceDate,
      days_until: offset,
      is_today: offset === 0,
      version: 1,
      deleted_at: null,
    };
  };
  const habit = (id: string, ownerId: string, title: string, checkedIn: boolean, checkinDay?: string): Habit => {
    const checkin: HabitCheckin | null = checkedIn ? {
      id: `${id}-checkin`,
      habit_id: id,
      workspace_id: 'preview-workspace',
      actor_id: ownerId,
      frequency_snapshot: 'DAILY',
      period_key: today,
      day: checkinDay ?? today,
      occurred_at: `${checkinDay ?? today}T08:00:00.000Z`,
      revoked_at: null,
    } : null;
    return {
      id,
      workspace_id: 'preview-workspace',
      owner_id: ownerId,
      title,
      note: null,
      frequency: 'DAILY',
      start_date: offsetDay(now, -30),
      status: 'ACTIVE',
      version: 1,
      current_period_key: today,
      checked_in: checkedIn,
      current_checkin: checkin,
      checkins: checkin ? [checkin] : [],
      recent_days: recentDays,
      recent_checkin_days: checkin ? [checkin.day] : [],
      deleted_at: null,
    };
  };
  return {
    ledgerEntries: [
      entry('preview-ledger-cafe', 'EXPENSE', '28.50', '周末咖啡', '餐饮', viewerId, 0),
      entry('preview-ledger-groceries', 'EXPENSE', '126.80', '晚餐食材', '日用', partnerId, -1),
      entry('preview-ledger-transfer', 'INCOME', '3200.00', '共同支出补充', '其他', partnerId, -3),
    ],
    habits: [
      habit('preview-habit-reading', viewerId, '睡前阅读', true),
      habit('preview-habit-walk', viewerId, '饭后散步', false),
      habit('preview-habit-stretch', partnerId, '晚间拉伸', true, previousDay),
    ],
    anniversaries: [
      anniversary('preview-anniversary-together', '相识纪念日', 12, 'ANNIVERSARY', 7),
      anniversary('preview-anniversary-birthday', 'TA 的生日', 28, 'BIRTHDAY', 3),
    ],
    sequence: 1,
  };
}

function createPreviewApi(getData: () => PreviewDomainData, updateData: (update: (current: PreviewDomainData) => PreviewDomainData) => void): PreviewApi {
  const activeEntries = (): LedgerEntry[] => getData().ledgerEntries.filter((entry) => entry.deleted_at === null);
  const byMemberName = (id: string): string => PREVIEW_STATE.snapshot?.members.find((member) => member.user_id === id)?.display_name ?? id;
  const makeSummary = (month: string): LedgerSummary => {
    const entries = activeEntries().filter((entry) => entry.date.startsWith(month));
    const expenses = entries.filter((entry) => entry.type === 'EXPENSE');
    const income = entries.filter((entry) => entry.type === 'INCOME');
    const expenseMinor = expenses.reduce((total, entry) => total + entry.amount_minor, 0);
    const incomeMinor = income.reduce((total, entry) => total + entry.amount_minor, 0);
    const categories = new Map<string, number>();
    const payers = new Map<string, number>();
    expenses.forEach((entry) => {
      categories.set(entry.category, (categories.get(entry.category) ?? 0) + entry.amount_minor);
      payers.set(entry.payer_or_payee_id, (payers.get(entry.payer_or_payee_id) ?? 0) + entry.amount_minor);
    });
    return {
      month,
      currency: 'CNY',
      expense_minor: expenseMinor,
      income_minor: incomeMinor,
      balance_minor: incomeMinor - expenseMinor,
      categories: [...categories].map(([category, amount_minor]) => ({ category, amount_minor, ratio: expenseMinor === 0 ? 0 : amount_minor / expenseMinor })),
      payer_totals: [...payers].map(([user_id, amount_minor]) => ({ user_id, display_name: byMemberName(user_id), amount_minor })),
    };
  };
  const createId = (kind: string): string => `preview-${kind}-${getData().sequence}`;
  const bump = (update: (current: PreviewDomainData) => PreviewDomainData): void => updateData((current) => ({ ...update(current), sequence: current.sequence + 1 }));
  const makeAnniversary = (input: { id: string; title: string; anchorDate: string; kind: Anniversary['kind']; prepareDays: number; note?: string }): Anniversary => {
    const now = new Date();
    const today = dateKey(now);
    const [year, month, day] = input.anchorDate.split('-').map(Number);
    let occurrence = new Date(now.getFullYear(), month - 1, day, 12);
    if (dateKey(occurrence) < today) occurrence = new Date(now.getFullYear() + 1, month - 1, day, 12);
    const nextOccurrence = dateKey(occurrence);
    const daysUntil = Math.round((occurrence.getTime() - new Date(`${today}T12:00:00`).getTime()) / 86_400_000);
    return {
      id: input.id,
      workspace_id: 'preview-workspace',
      title: input.title,
      anchor_date: `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`,
      kind: input.kind,
      prepare_days: input.prepareDays,
      note: input.note ?? null,
      next_occurrence: nextOccurrence,
      days_until: daysUntil,
      is_today: daysUntil === 0,
      version: 1,
    };
  };

  return {
    listLedger: async ({ month, type }) => activeEntries().filter((entry) => entry.date.startsWith(month) && (!type || entry.type === type)),
    getLedgerSummary: async (month) => makeSummary(month),
    createLedger: async (input) => {
      const amountMinor = Math.round(Number(input.amount) * 100);
      if (!Number.isFinite(amountMinor) || amountMinor <= 0) throw new Error('请输入有效金额。');
      const id = createId('ledger');
      const memberName = byMemberName(input.payerOrPayeeId);
      const entry: LedgerEntry = {
        id,
        workspace_id: 'preview-workspace',
        type: input.type,
        amount_minor: amountMinor,
        amount: amountMinorToText(amountMinor),
        currency: 'CNY',
        title: input.title,
        category: input.category,
        payer_or_payee_id: input.payerOrPayeeId,
        payer_or_payee_name: memberName,
        date: input.date,
        note: input.note ?? null,
        created_by: '我',
        updated_by: '我',
        version: 1,
        deleted_at: null,
      };
      bump((current) => ({ ...current, ledgerEntries: [entry, ...current.ledgerEntries] }));
      return entry;
    },
    patchLedger: async (id, input) => {
      const current = activeEntries().find((entry) => entry.id === id);
      if (!current) throw new Error('找不到这笔示例账目。');
      const changes = input.changes;
      const amount = changes.amount === undefined ? current.amount : String(changes.amount);
      const amountMinor = Math.round(Number(amount) * 100);
      const entry: LedgerEntry = {
        ...current,
        type: (changes.type as LedgerEntryType | undefined) ?? current.type,
        amount_minor: amountMinor,
        amount: amountMinorToText(amountMinor),
        title: (changes.title as string | undefined) ?? current.title,
        category: (changes.category as string | undefined) ?? current.category,
        payer_or_payee_id: (changes.payer_or_payee_id as string | undefined) ?? current.payer_or_payee_id,
        payer_or_payee_name: byMemberName((changes.payer_or_payee_id as string | undefined) ?? current.payer_or_payee_id),
        date: (changes.date as string | undefined) ?? current.date,
        note: (changes.note as string | null | undefined) ?? current.note,
        version: current.version + 1,
      };
      bump((data) => ({ ...data, ledgerEntries: data.ledgerEntries.map((item) => item.id === id ? entry : item) }));
      return entry;
    },
    deleteLedger: async (id) => {
      const now = new Date().toISOString();
      let deleted: LedgerEntry | undefined;
      bump((current) => ({
        ...current,
        ledgerEntries: current.ledgerEntries.map((entry) => {
          if (entry.id !== id) return entry;
          deleted = { ...entry, deleted_at: now, version: entry.version + 1 };
          return deleted;
        }),
      }));
      if (!deleted) throw new Error('找不到这笔示例账目。');
      return deleted;
    },
    listHabits: async (owner) => getData().habits.filter((habit) => habit.status !== 'DELETED' && (owner === 'all' || (owner === 'mine' ? habit.owner_id === '我' : habit.owner_id !== '我'))),
    createHabit: async (input) => {
      const today = dateKey(new Date());
      const habit: Habit = {
        id: createId('habit'), workspace_id: 'preview-workspace', owner_id: '我', title: input.title, note: input.note ?? null,
        frequency: input.frequency, start_date: input.startDate ?? today, status: 'ACTIVE', version: 1,
        current_period_key: today, checked_in: false, current_checkin: null, checkins: [],
        recent_days: Array.from({ length: 7 }, (_, index) => offsetDay(new Date(), index - 6)), recent_checkin_days: [], deleted_at: null,
      };
      bump((current) => ({ ...current, habits: [habit, ...current.habits] }));
      return habit;
    },
    patchHabit: async (id, input) => {
      const current = getData().habits.find((habit) => habit.id === id);
      if (!current) throw new Error('找不到这个示例习惯。');
      const changes = input.changes;
      const updated: Habit = {
        ...current,
        title: (changes.title as string | undefined) ?? current.title,
        frequency: (changes.frequency as Habit['frequency'] | undefined) ?? current.frequency,
        start_date: (changes.start_date as string | undefined) ?? current.start_date,
        note: (changes.note as string | null | undefined) ?? current.note,
        version: current.version + 1,
      };
      bump((data) => ({ ...data, habits: data.habits.map((habit) => habit.id === id ? updated : habit) }));
      return updated;
    },
    habitAction: async (id, action) => {
      const current = getData().habits.find((habit) => habit.id === id);
      if (!current) throw new Error('找不到这个示例习惯。');
      let updated: Habit;
      if (action === 'pause' || action === 'resume') {
        updated = { ...current, status: action === 'pause' ? 'PAUSED' : 'ACTIVE', version: current.version + 1 };
      } else if (action === 'checkin') {
        const today = dateKey(new Date());
        const checkin: HabitCheckin = {
          id: `${id}-checkin-${current.version + 1}`, habit_id: id, workspace_id: 'preview-workspace', actor_id: '我',
          frequency_snapshot: current.frequency, period_key: current.current_period_key, day: today,
          occurred_at: new Date().toISOString(), revoked_at: null,
        };
        updated = { ...current, checked_in: true, current_checkin: checkin, checkins: [...current.checkins, checkin], recent_checkin_days: [...new Set([...(current.recent_checkin_days ?? []), today])], version: current.version + 1 };
      } else {
        const revokedAt = new Date().toISOString();
        const checkins = current.checkins.map((checkin) => checkin.id === current.current_checkin?.id ? { ...checkin, revoked_at: revokedAt } : checkin);
        updated = { ...current, checked_in: false, current_checkin: null, checkins, recent_checkin_days: (current.recent_checkin_days ?? []).filter((day) => day !== current.current_checkin?.day), version: current.version + 1 };
      }
      bump((data) => ({ ...data, habits: data.habits.map((habit) => habit.id === id ? updated : habit) }));
      return updated;
    },
    deleteHabit: async (id) => {
      let deleted = getData().habits.find((habit) => habit.id === id);
      if (!deleted) throw new Error('找不到这个示例习惯。');
      deleted = { ...deleted, status: 'DELETED', deleted_at: new Date().toISOString(), version: deleted.version + 1 };
      bump((current) => ({ ...current, habits: current.habits.filter((habit) => habit.id !== id) }));
      return deleted;
    },
    listAnniversaries: async () => getData().anniversaries.filter((item) => item.deleted_at == null),
    createAnniversary: async (input) => {
      const anniversary = makeAnniversary({ id: createId('anniversary'), title: input.title, anchorDate: input.anchorDate, kind: input.kind, prepareDays: input.prepareDays, note: input.note });
      bump((current) => ({ ...current, anniversaries: [anniversary, ...current.anniversaries] }));
      return anniversary;
    },
    patchAnniversary: async (id, input) => {
      const current = getData().anniversaries.find((item) => item.id === id);
      if (!current) throw new Error('找不到这个示例纪念日。');
      const changes = input.changes;
      const updated = makeAnniversary({
        id,
        title: (changes.title as string | undefined) ?? current.title,
        anchorDate: (changes.anchor_date as string | undefined) ?? current.anchor_date,
        kind: (changes.kind as Anniversary['kind'] | undefined) ?? current.kind,
        prepareDays: (changes.prepare_days as number | undefined) ?? current.prepare_days,
        note: (changes.note as string | null | undefined) ?? current.note ?? undefined,
      });
      updated.version = current.version + 1;
      bump((data) => ({ ...data, anniversaries: data.anniversaries.map((item) => item.id === id ? updated : item) }));
      return updated;
    },
    deleteAnniversary: async (id) => {
      let deleted = getData().anniversaries.find((item) => item.id === id);
      if (!deleted) throw new Error('找不到这个示例纪念日。');
      deleted = { ...deleted, deleted_at: new Date().toISOString(), version: deleted.version + 1 };
      bump((current) => ({ ...current, anniversaries: current.anniversaries.filter((item) => item.id !== id) }));
      return deleted;
    },
    prepareAnniversary: async (id) => {
      const anniversary = getData().anniversaries.find((item) => item.id === id);
      if (!anniversary) throw new Error('找不到这个示例纪念日。');
      const task = PREVIEW_STATE.snapshot?.tasks[0];
      if (!task) throw new Error('没有示例任务。');
      return { task, cursor: PREVIEW_STATE.cursor, source_key: `anniversary:${id}:${anniversary.next_occurrence}` };
    },
  };
}

function createPreviewSessionApi(): WebSessionApi {
  let sessions: WebSessionSummary[] = [{
    id: 'preview-session',
    status: 'ACTIVE',
    origin: '本地界面预览',
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 86_400_000).toISOString(),
  }];
  return {
    listWebSessions: async () => [...sessions],
    revokeWebSession: async (id) => { sessions = sessions.filter((session) => session.id !== id); },
    revokeAllWebSessions: async () => { sessions = []; return { revoked_count: 0 }; },
  };
}

function amountMinorToText(value: number): string { return (value / 100).toFixed(2); }
function dateKey(value: Date): string { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`; }
function offsetDay(value: Date, offset: number): string { const result = new Date(value); result.setDate(result.getDate() + offset); return dateKey(result); }

function previewApproval(id: string, requester: string, approver: string, task: TaskItem, timestamp: string) {
  return {
    id,
    workspace_id: 'preview-workspace',
    task_id: task.id,
    comment_id: null,
    requester_id: requester,
    approver_id: approver,
    request_type: 'HANDLER_TRANSFER' as const,
    proposed_changes: { current_handler_id: approver },
    base_field_versions: {},
    request_id: id,
    status: 'PENDING' as const,
    created_at: timestamp,
    reviewed_at: null,
    reviewed_by: null,
    rejection_reason: null,
    resolved_cursor: null,
  };
}

function offsetDate(now: Date, days: number): string {
  const due = new Date(now);
  due.setDate(due.getDate() + days);
  due.setHours(17, 0, 0, 0);
  return due.toISOString();
}

function previewStatus(status: TaskItem['status']): string {
  return ({ BLOCKED: '卡住', IN_PROGRESS: '进行中', TODO: '待开始', REVIEW: '待验收', DONE: '已完成', CANCELLED: '已取消' } as Record<string, string>)[status] ?? status;
}

function readPreviewRoute(): Route {
  const route = parseHash(window.location.hash);
  return route.kind === 'matters' || route.kind === 'all-tasks' || route.kind === 'ledger' || route.kind === 'checkins' || route.kind === 'me' || route.kind === 'activity' || route.kind === 'approvals'
    ? route
    : { kind: 'matters', view: 'moment' };
}
