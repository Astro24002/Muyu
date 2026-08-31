import { useCallback, useEffect, useRef, useState, type JSX } from 'react';
import { ApiError, type ApiClient } from '../api/client';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';
import { AppShell } from '../components/layout/AppShell';
import { InlineError } from '../components/status/InlineError';
import { SyncStatus } from '../components/status/SyncStatus';
import { QrLoginPage } from '../pages/QrLoginPage';
import type { WebSocketFactory } from '../realtime/workspace-socket';
import type { WebSessionViewApi } from '../ui/web-session-view';
import { WorkspaceView } from '../ui/workspace-view';
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

export function App({ api, login, sync, socketFactory }: AppProps): JSX.Element {
  const workspaceState = useWorkspaceState(sync);
  const loginState = useQrLoginState(login);
  const [screen, setScreen] = useState<AppScreen>('loading');
  const [loadError, setLoadError] = useState<string | null>(null);
  const [route, setRoute] = useState<Route>(() => parseHash(typeof window === 'undefined' ? '' : window.location.hash));
  const legacyRootRef = useRef<HTMLDivElement>(null);
  const legacyViewCleanupRef = useRef<(() => void) | undefined>(undefined);
  const legacySessionRef = useRef<LegacySyncBridge | undefined>(undefined);
  const activeRef = useRef(false);
  const sessionGenerationRef = useRef(0);
  const loggingOutRef = useRef(false);
  const logoutRequestRef = useRef(0);
  const authRecoveryRef = useRef(false);
  const previousLoginKindRef = useRef<QrLoginState['kind']>(loginState.kind);
  const canUseLegacyViews = typeof sync.subscribe === 'function' && typeof login.subscribe === 'function';
  const workspaceId = screen === 'workspace' && !workspaceState.authRequired
    ? workspaceState.snapshot?.workspace_id ?? null
    : null;
  const stopRealtime = useWorkspaceRealtime(sync, workspaceId, { socketFactory });

  const disposeLegacyView = useCallback((): void => {
    legacySessionRef.current?.invalidate();
    legacySessionRef.current = undefined;
    legacyViewCleanupRef.current?.();
    legacyViewCleanupRef.current = undefined;
    legacyRootRef.current?.replaceChildren();
  }, []);

  const stopLocalWorkspace = useCallback((): void => {
    stopRealtime();
    disposeLegacyView();
  }, [disposeLegacyView, stopRealtime]);

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

  useEffect(() => {
    const root = legacyRootRef.current;
    if (!root) return;
    if (!canUseLegacyViews) {
      disposeLegacyView();
      return;
    }

    if (screen === 'workspace' && workspaceState.snapshot) {
      root.replaceChildren();
      const legacySession = createLegacySyncBridge(sync);
      legacySessionRef.current = legacySession;
      const onLegacyLogout = (): void => {
        if (!legacySession.isActive()) return;
        if (sync.state.authRequired) recoverAuthRequired();
        else logout();
      };
      const cleanup = WorkspaceView.mount(root, legacySession.sync, onLegacyLogout, webSessionApi(api), recoverAuthRequired);
      legacyViewCleanupRef.current = cleanup;
      return () => {
        if (legacyViewCleanupRef.current !== cleanup) return;
        legacyViewCleanupRef.current = undefined;
        if (legacySessionRef.current === legacySession) legacySessionRef.current = undefined;
        legacySession.invalidate();
        cleanup();
        root.replaceChildren();
      };
    }

    disposeLegacyView();
  }, [api, canUseLegacyViews, disposeLegacyView, login, logout, recoverAuthRequired, screen, sync, workspaceState.snapshot?.workspace_id]);

  const routeKey = route.kind === 'task' ? `task:${route.id}` : route.kind;
  const focusNewTask = useCallback((): void => {
    legacyRootRef.current?.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')?.focus();
  }, []);
  const onNavigate = useCallback((nextRoute: PrimaryRoute): void => {
    navigate(nextRoute);
  }, []);
  const workspaceReady = screen === 'workspace' && Boolean(workspaceState.snapshot) && !workspaceState.authRequired && canUseLegacyViews;

  return (
    <div data-testid="muyu-app" data-route={routeKey}>
      <div data-testid="react-route" data-route={routeKey} aria-live="polite" />
      {screen === 'login' ? <QrLoginPage controller={login} state={loginState} /> : null}
      {workspaceReady ? (
        <AppShell
          route={route}
          onNavigate={onNavigate}
          onLogout={logout}
          onCreateTask={focusNewTask}
          pendingApprovalCount={pendingApprovalCount(workspaceState)}
        >
          <SyncStatus loading={workspaceState.loading} stale={workspaceState.stale} error={workspaceState.error} />
          <div ref={legacyRootRef} data-testid="legacy-app-root" />
        </AppShell>
      ) : null}
      {screen !== 'login' && !workspaceReady ? placeholder(screen, loadError ?? workspaceState.error, () => loadWorkspace()) : null}
    </div>
  );
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

function webSessionApi(api: AppProps['api']): WebSessionViewApi | undefined {
  if (typeof api.listWebSessions !== 'function'
    || typeof api.revokeWebSession !== 'function'
    || typeof api.revokeAllWebSessions !== 'function') return undefined;
  return api as WebSessionViewApi;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '无法加载工作区，请检查网络后重试。';
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

interface LegacySyncBridge {
  sync: WorkspaceSyncController;
  invalidate: () => void;
  isActive: () => boolean;
}

const INACTIVE_LEGACY_STATE: WorkspaceSyncState = {
  snapshot: null,
  cursor: 0,
  loading: false,
  stale: false,
  error: null,
  conflicts: [],
  authRequired: true,
};

function createLegacySyncBridge(sync: WorkspaceSyncController): LegacySyncBridge {
  let active = true;
  const bridgedSync = new Proxy(sync, {
    get(target, property) {
      if (property === 'state') return active ? target.state : INACTIVE_LEGACY_STATE;
      const value = Reflect.get(target, property, target);
      if (typeof value !== 'function') return value;
      return (...args: unknown[]) => active ? Reflect.apply(value, target, args) : Promise.resolve(undefined);
    },
  });
  return {
    sync: bridgedSync,
    invalidate: () => { active = false; },
    isActive: () => active,
  };
}
