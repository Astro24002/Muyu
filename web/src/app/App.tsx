import { useCallback, useEffect, useRef, useState, type JSX } from 'react';
import { ApiError, type ApiClient } from '../api/client';
import type { ActivityEvent, TaskItem, TaskQuadrant } from '../api/types';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';
import { ApprovalsPage } from '../pages/ApprovalsPage';
import { AppShell } from '../components/layout/AppShell';
import { InlineError } from '../components/status/InlineError';
import type { CreateTaskHandler } from '../components/tasks/TaskComposer';
import { TaskDetailPanel } from '../components/tasks/TaskDetailPanel';
import type { TaskActivityState } from '../components/tasks/TaskTimeline';
import type { WebSessionApi } from '../components/account/web-session-api';
import { ActivityPage } from '../pages/ActivityPage';
import { AllTasksPage } from '../pages/AllTasksPage';
import { CheckinsPage } from '../pages/CheckinsPage';
import { LedgerPage } from '../pages/LedgerPage';
import { MattersPage, type MatterView } from '../pages/MattersPage';
import { MyPage } from '../pages/MyPage';
import { QrLoginPage } from '../pages/QrLoginPage';
import { TodayPage } from '../pages/TodayPage';
import type { WebSocketFactory } from '../realtime/workspace-socket';
import type { TaskDetailActions } from '../tasks/task-detail-actions';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';
import { navigate, parseHash, type Route } from './routes';
import type { PrimaryRoute } from '../components/layout/TopNav';
import { useQrLoginState, useWorkspaceState } from './use-external-state';
import { useWorkspaceRealtime } from './use-workspace-realtime';

export interface AppProps {
  api: ApiClient;
  login: QrLoginController;
  sync: WorkspaceSyncController;
  socketFactory?: WebSocketFactory;
}

type AppScreen = 'loading' | 'login' | 'workspace' | 'error';
type TaskListRoute = Extract<Route, { kind: 'matters' | 'all-tasks' | 'today' | 'tasks' }>;

export function App({ api, login, sync, socketFactory }: AppProps): JSX.Element {
  const workspaceState = useWorkspaceState(sync);
  const loginState = useQrLoginState(login);
  const [screen, setScreen] = useState<AppScreen>('loading');
  const [loadError, setLoadError] = useState<string | null>(null);
  const [route, setRoute] = useState<Route>(() => parseHash(typeof window === 'undefined' ? '' : window.location.hash));
  const [taskListRoute, setTaskListRoute] = useState<TaskListRoute>({ kind: 'all-tasks' });
  const [taskActivity, setTaskActivity] = useState<TaskActivityState>({ status: 'idle', events: [] });
  const [taskActivityRetry, setTaskActivityRetry] = useState(0);
  const taskListRouteRef = useRef<TaskListRoute>({ kind: 'all-tasks' });
  const taskFocusRef = useRef<{ taskId: string; element: HTMLElement | null } | null>(null);
  const taskActivityRequestSequenceRef = useRef(0);
  const activeRef = useRef(false);
  const sessionGenerationRef = useRef(0);
  const loggingOutRef = useRef(false);
  const logoutRequestRef = useRef(0);
  const authRecoveryRef = useRef(false);
  const previousLoginKindRef = useRef<QrLoginState['kind']>(loginState.kind);
  const workspaceId = screen === 'workspace' && !workspaceState.authRequired
    ? workspaceState.snapshot?.workspace_id ?? null
    : null;
  const workspaceReady = screen === 'workspace' && Boolean(workspaceState.snapshot) && !workspaceState.authRequired;
  const taskId = route.kind === 'task' ? route.id : null;
  const selectedTask = taskId === null
    ? null
    : workspaceState.snapshot?.tasks.find((item) => item.id === taskId) ?? null;
  const stopRealtime = useWorkspaceRealtime(sync, workspaceId, { socketFactory });

  const stopLocalWorkspace = useCallback((): void => {
    stopRealtime();
  }, [stopRealtime]);

  const startLogin = useCallback((allowDuringLogout = false): void => {
    if (!activeRef.current || (!allowDuringLogout && loggingOutRef.current) || typeof login.start !== 'function') return;
    const kind = login.state?.kind;
    if (kind === undefined || kind === 'signed_out' || kind === 'expired' || kind === 'failure') {
      void login.start();
    }
  }, [login]);

  const enterLogin = useCallback((clearSync = true, allowDuringLogout = false): void => {
    if (!activeRef.current) return;
    sessionGenerationRef.current += 1;
    stopLocalWorkspace();
    if (clearSync && typeof sync.clear === 'function') sync.clear();
    setLoadError(null);
    setScreen('login');
    if (typeof login.stop === 'function') login.stop();
    startLogin(allowDuringLogout);
  }, [login, startLogin, stopLocalWorkspace, sync]);

  const bestEffortLogout = useCallback((): void => {
    if (typeof api.logoutWebSession !== 'function') return;
    try {
      void Promise.resolve(api.logoutWebSession()).catch(() => undefined);
    } catch {
      // Session cleanup is advisory during auth recovery.
    }
  }, [api]);

  const recoverAuthRequired = useCallback((): void => {
    if (!activeRef.current || authRecoveryRef.current) return;
    authRecoveryRef.current = true;
    enterLogin(true, true);
    bestEffortLogout();
  }, [bestEffortLogout, enterLogin]);

  const loadWorkspace = useCallback((clearFirst = false): void => {
    if (!activeRef.current) return;
    authRecoveryRef.current = false;
    const generation = ++sessionGenerationRef.current;
    if (clearFirst) {
      stopLocalWorkspace();
      if (typeof sync.clear === 'function') sync.clear();
    }
    setLoadError(null);
    setScreen('loading');

    let request: Promise<void>;
    try {
      request = Promise.resolve(sync.loadSnapshot());
    } catch (error) {
      request = Promise.reject(error);
    }

    void request.then(() => {
      if (!activeRef.current || generation !== sessionGenerationRef.current) return;
      const state = sync.state;
      if (state.authRequired) {
        recoverAuthRequired();
      } else if (state.snapshot) {
        setScreen('workspace');
      } else if (state.error) {
        setLoadError(state.error);
        setScreen('error');
      } else {
        enterLogin(true);
      }
    }).catch((error: unknown) => {
      if (!activeRef.current || generation !== sessionGenerationRef.current) return;
      const state = sync.state;
      if (state.authRequired) {
        recoverAuthRequired();
        return;
      }
      if (isUnauthorized(error)) {
        enterLogin(true);
        return;
      }
      if (state.snapshot) {
        setScreen('workspace');
        return;
      }
      setLoadError(state.error ?? errorMessage(error));
      setScreen('error');
    });
  }, [enterLogin, recoverAuthRequired, stopLocalWorkspace, sync]);

  const logout = useCallback((): void => {
    if (!activeRef.current || loggingOutRef.current) return;
    loggingOutRef.current = true;
    const logoutRequest = ++logoutRequestRef.current;
    sessionGenerationRef.current += 1;
    stopLocalWorkspace();
    if (typeof sync.clear === 'function') sync.clear();
    setLoadError(null);
    setScreen('login');
    if (typeof login.stop === 'function') login.stop();

    let request: Promise<void>;
    try {
      request = typeof api.logoutWebSession === 'function'
        ? api.logoutWebSession()
        : Promise.resolve();
    } catch (error) {
      request = Promise.reject(error);
    }
    void request.catch(() => undefined).finally(() => {
      if (!activeRef.current) return;
      if (logoutRequest !== logoutRequestRef.current) return;
      loggingOutRef.current = false;
      startLogin();
    });
  }, [api, login, startLogin, stopLocalWorkspace, sync]);

  useEffect(() => {
    activeRef.current = true;
    loadWorkspace();
    return () => {
      activeRef.current = false;
      sessionGenerationRef.current += 1;
      stopLocalWorkspace();
      if (typeof login.dispose === 'function') login.dispose();
      if (typeof sync.dispose === 'function') sync.dispose();
    };
  }, [loadWorkspace, login, stopLocalWorkspace, sync]);

  useEffect(() => {
    const onHashChange = (): void => setRoute(parseHash(window.location.hash));
    window.addEventListener('hashchange', onHashChange);
    onHashChange();
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  useEffect(() => {
    if (route.kind === 'task') return;
    const pendingFocus = taskFocusRef.current;
    if (!pendingFocus) return;
    taskFocusRef.current = null;
    const target = pendingFocus.element?.isConnected
      ? pendingFocus.element
      : findTaskFocusTarget(pendingFocus.taskId);
    target?.focus();
  }, [route.kind]);

  useEffect(() => {
    if (workspaceState.authRequired) recoverAuthRequired();
  }, [recoverAuthRequired, workspaceState.authRequired]);

  useEffect(() => {
    const previousKind = previousLoginKindRef.current;
    previousLoginKindRef.current = loginState.kind;
    if (loginState.kind === 'signed_in' && previousKind !== 'signed_in') {
      if (loggingOutRef.current) {
        loggingOutRef.current = false;
        logoutRequestRef.current += 1;
      }
      loadWorkspace(true);
    }
  }, [loadWorkspace, loginState.kind]);

  const retryTaskActivity = useCallback((): void => {
    setTaskActivityRetry((current) => current + 1);
  }, []);

  const getTaskActivity = useCallback((id: string): Promise<ActivityEvent[]> => {
    if (typeof api.getTaskActivity !== 'function') return Promise.reject(new Error('当前 API 不支持活动记录。'));
    return api.getTaskActivity(id);
  }, [api]);

  useEffect(() => {
    const requestSequence = ++taskActivityRequestSequenceRef.current;
    if (!workspaceReady || taskId === null || selectedTask === null) {
      setTaskActivity({ status: 'idle', events: [] });
      return undefined;
    }

    if (typeof api.getTaskActivity !== 'function') {
      setTaskActivity({ status: 'error', events: [], error: '当前 API 不支持活动记录。', retryable: false });
      return undefined;
    }

    let active = true;
    setTaskActivity({ status: 'loading', events: [] });
    let request: Promise<ActivityEvent[]>;
    try {
      request = api.getTaskActivity(taskId);
    } catch (error) {
      request = Promise.reject(error);
    }
    void request
      .then((events) => {
        if (active && requestSequence === taskActivityRequestSequenceRef.current) {
          setTaskActivity({ status: 'success', events });
        }
      })
      .catch((error: unknown) => {
        if (active && requestSequence === taskActivityRequestSequenceRef.current) {
          setTaskActivity({
            status: 'error',
            events: [],
            error: activityErrorMessage(error),
            retryable: !isActivityPermissionError(error),
          });
        }
      });

    return () => {
      active = false;
    };
  }, [api, selectedTask !== null, taskActivityRetry, taskId, workspaceId, workspaceReady]);

  const routeKey = route.kind === 'task'
    ? `task:${route.id}`
    : route.kind === 'matters'
      ? `matters:${route.view ?? 'moment'}`
      : route.kind;
  const focusNewTask = useCallback((): void => {
    const composerTrigger = document.querySelector<HTMLButtonElement>('[data-task-composer-trigger]');
    if (composerTrigger) {
      composerTrigger.focus();
      composerTrigger.click();
      return;
    }
  }, []);
  const onNavigate = useCallback((nextRoute: PrimaryRoute): void => {
    taskFocusRef.current = null;
    if (nextRoute.kind === 'matters' || nextRoute.kind === 'ledger' || nextRoute.kind === 'checkins' || nextRoute.kind === 'me') {
      if (nextRoute.kind === 'matters') {
        const nextMatterRoute: TaskListRoute = { kind: 'matters', view: nextRoute.view ?? 'moment' };
        taskListRouteRef.current = nextMatterRoute;
        setTaskListRoute(nextMatterRoute);
      }
    }
    navigate(nextRoute);
  }, []);
  const openTask = useCallback((task: TaskItem): void => {
    const backgroundRoute = taskRouteFor(route) ?? taskListRouteRef.current;
    taskListRouteRef.current = backgroundRoute;
    setTaskListRoute(backgroundRoute);
    const activeElement = typeof document !== 'undefined'
      && document.activeElement instanceof HTMLElement
      && document.activeElement !== document.body
      ? document.activeElement
      : findTaskFocusTarget(task.id);
    taskFocusRef.current = { taskId: task.id, element: activeElement };
    navigate({ kind: 'task', id: task.id });
  }, [route.kind]);
  const closeTask = useCallback((): void => {
    navigate(taskListRouteRef.current);
  }, []);
  const createTask = useCallback<CreateTaskHandler>((title: string, description: string, quadrant: TaskQuadrant, labels: string[], nextStepText?: string, targetHandlerId?: string, acceptanceCriteria?: string): Promise<void> => {
    return targetHandlerId
      ? sync.createTask(title, description, quadrant, labels, nextStepText, targetHandlerId, acceptanceCriteria)
      : sync.createTask(title, description, quadrant, labels, nextStepText, undefined, acceptanceCriteria);
  }, [sync]);
  const taskActions: TaskDetailActions | undefined = selectedTask ? {
    onTransition: (status, payload) => sync.transitionTask(selectedTask.id, status, payload),
    onComment: (body) => sync.addComment(selectedTask.id, body),
    onDelay: (date, reason, note) => sync.addDelay(selectedTask.id, date, reason, note),
    onSave: (changes) => sync.patchTask(selectedTask.id, changes),
    onRequestAgreementUpdate: (acceptanceCriteria) => sync.requestAgreementUpdate(selectedTask.id, acceptanceCriteria),
    onRequestCancellation: (reason) => sync.requestTaskCancellation(selectedTask.id, reason),
    onDeleteComment: (commentId, baseVersion) => sync.deleteTaskComment(selectedTask.id, commentId, baseVersion),
    onResolveConflict: (conflictId, resolution) => sync.resolveConflict(selectedTask.id, conflictId, resolution),
    currentUserId: workspaceState.snapshot?.viewer_user_id ?? undefined,
    canWrite: !workspaceState.loading && !workspaceState.stale && !workspaceState.authRequired,
  } : undefined;
  const taskBackground = taskListRoute.kind === 'matters' || taskListRoute.kind === 'today'
    ? <MattersPage sync={sync} view={taskListRoute.kind === 'matters' ? taskListRoute.view : 'moment'} onOpenTask={openTask} onCreateTask={createTask} />
    : <AllTasksPage sync={sync} onOpenTask={openTask} onCreateTask={createTask} />;

  return (
    <div data-testid="muyu-app" data-route={routeKey}>
      <div data-testid="react-route" data-route={routeKey} aria-live="polite" />
      {screen === 'login' ? <QrLoginPage controller={login} state={loginState} /> : null}
      {workspaceReady ? (
          <AppShell
          route={route}
          onNavigate={onNavigate}
          onLogout={logout}
          onCreateTask={canCreateTask(route) ? focusNewTask : undefined}
          sessionApi={webSessionApi(api)}
          onAuthRequired={recoverAuthRequired}
            pendingApprovalCount={pendingApprovalCount(workspaceState)}
          >
            {route.kind === 'matters' ? (
              <MattersPage sync={sync} view={route.view ?? 'moment'} onOpenTask={openTask} onCreateTask={createTask} />
            ) : route.kind === 'all-tasks' || route.kind === 'tasks' ? (
              <AllTasksPage sync={sync} onOpenTask={openTask} onCreateTask={createTask} />
            ) : route.kind === 'today' ? (
              <MattersPage sync={sync} view="moment" onOpenTask={openTask} onCreateTask={createTask} />
            ) : route.kind === 'ledger' ? (
              <LedgerPage
                api={api}
                members={workspaceState.snapshot?.members ?? []}
                viewerId={workspaceState.snapshot?.viewer_user_id}
                canWrite={!workspaceState.loading && !workspaceState.stale && !workspaceState.authRequired}
                snapshotEntries={workspaceState.snapshot?.ledger_entries}
              />
            ) : route.kind === 'checkins' ? (
              <CheckinsPage
                api={api}
                viewerId={workspaceState.snapshot?.viewer_user_id}
                canWrite={!workspaceState.loading && !workspaceState.stale && !workspaceState.authRequired}
                snapshotHabits={workspaceState.snapshot?.habits}
                snapshotAnniversaries={workspaceState.snapshot?.anniversaries}
              />
            ) : route.kind === 'me' ? (
              <MyPage sessionApi={webSessionApi(api)} onAuthRequired={recoverAuthRequired} />
            ) : route.kind === 'approvals' ? (
              <ApprovalsPage sync={sync} />
            ) : route.kind === 'activity' ? (
              <ActivityPage
                tasks={workspaceState.snapshot?.tasks ?? []}
                getTaskActivity={getTaskActivity}
                workspaceKey={workspaceId ?? 'workspace'}
              />
            ) : route.kind === 'task' ? (
              <>
                {taskBackground}
                {selectedTask && taskActions ? (
                  <TaskDetailPanel
                    key={selectedTask.id}
                    task={selectedTask}
                    members={workspaceState.snapshot?.members ?? []}
                    syncState={workspaceState}
                    actions={taskActions}
                    activityState={taskActivity}
                    onActivityRetry={retryTaskActivity}
                    onClose={closeTask}
                  />
                ) : (
                  <InlineError message="任务不存在，请刷新后重试。" />
                )}
              </>
            ) : null}
          </AppShell>
      ) : null}
      {screen !== 'login' && !workspaceReady ? placeholder(screen, loadError ?? workspaceState.error, () => loadWorkspace()) : null}
    </div>
  );
}

function findTaskFocusTarget(taskId: string): HTMLElement | null {
  if (typeof document === 'undefined') return null;
  for (const row of document.querySelectorAll<HTMLElement>('[data-task-row]')) {
    if (row.getAttribute('data-task-row') !== taskId) continue;
    return row.querySelector<HTMLElement>('[role="button"]');
  }
  return null;
}

function taskRouteFor(route: Route): TaskListRoute | null {
  if (route.kind === 'matters') return { kind: 'matters', view: route.view ?? 'moment' };
  if (route.kind === 'all-tasks') return { kind: 'all-tasks' };
  if (route.kind === 'today') return { kind: 'today' };
  if (route.kind === 'tasks') return { kind: 'tasks' };
  return null;
}

function canCreateTask(route: Route): boolean {
  if (route.kind === 'all-tasks' || route.kind === 'tasks' || route.kind === 'today') return true;
  return route.kind === 'matters' && (route.view ?? 'moment') === 'moment';
}

function placeholder(screen: AppScreen, error: string | null, onRetry: () => void): JSX.Element {
  const title = screen === 'loading'
    ? '正在加载工作区'
    : screen === 'error'
      ? '工作区暂时不可用'
      : '二维码登录';
  return (
    <main data-testid="react-page-placeholder" aria-busy={screen === 'loading' ? 'true' : undefined}>
      <h1>{title}</h1>
      {screen === 'error' ? (
        <InlineError message={error ?? '无法加载工作区，请检查网络后重试。'} onRetry={onRetry} />
      ) : (
        <p>{screen === 'loading' ? '请稍候。' : '请生成二维码登录。'}</p>
      )}
    </main>
  );
}

function webSessionApi(api: AppProps['api']): WebSessionApi | undefined {
  if (typeof api.listWebSessions !== 'function'
    || typeof api.revokeWebSession !== 'function'
    || typeof api.revokeAllWebSessions !== 'function') return undefined;
  return api as WebSessionApi;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '无法加载工作区，请检查网络后重试。';
}

function isActivityPermissionError(error: unknown): boolean {
  return error instanceof ApiError && (error.status === 401 || error.status === 403);
}

function activityErrorMessage(error: unknown): string {
  if (isActivityPermissionError(error)) return '当前账号无权查看活动记录。';
  if (error instanceof ApiError && error.status === 404) return '暂时无法找到活动记录，请重试。';
  if (error instanceof Error && error.message) return `活动记录加载失败：${error.message}`;
  return '活动记录加载失败，请重试。';
}

function isUnauthorized(error: unknown): boolean {
  if (error instanceof ApiError) return error.status === 401;
  return Boolean(error && typeof error === 'object' && 'status' in error && error.status === 401);
}

function pendingApprovalCount(state: WorkspaceSyncState): number {
  const approvals = state.approvals ?? state.snapshot?.approval_requests ?? [];
  const viewerId = state.snapshot?.viewer_user_id;
  return approvals.filter((approval) => approval.status === 'PENDING' && (!viewerId || approval.approver_id === viewerId)).length;
}
