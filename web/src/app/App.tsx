import { useCallback, useEffect, useRef, useState, type JSX } from 'react';
import { ApiError, type ApiClient } from '../api/client';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';
import type { WebSocketFactory } from '../realtime/workspace-socket';
import type { WebSessionViewApi } from '../ui/web-session-view';
import { QrLoginView } from '../ui/qr-login-view';
import { WorkspaceView } from '../ui/workspace-view';
import type { WorkspaceSyncController } from '../sync/workspace-sync';
import { parseHash, type Route } from './routes';
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
  const [route, setRoute] = useState<Route>(() => parseHash(window.location.hash));
  const legacyRootRef = useRef<HTMLDivElement>(null);
  const legacyViewCleanupRef = useRef<(() => void) | undefined>(undefined);
  const activeRef = useRef(false);
  const sessionGenerationRef = useRef(0);
  const loggingOutRef = useRef(false);
  const previousLoginKindRef = useRef<QrLoginState['kind']>(loginState.kind);
  const canUseLegacyViews = typeof sync.subscribe === 'function' && typeof login.subscribe === 'function';
  const workspaceId = screen === 'workspace' && !workspaceState.authRequired
    ? workspaceState.snapshot?.workspace_id ?? null
    : null;
  const stopRealtime = useWorkspaceRealtime(sync, workspaceId, { socketFactory });

  const disposeLegacyView = useCallback((): void => {
    legacyViewCleanupRef.current?.();
    legacyViewCleanupRef.current = undefined;
    legacyRootRef.current?.replaceChildren();
  }, []);

  const stopLocalWorkspace = useCallback((): void => {
    stopRealtime();
    disposeLegacyView();
  }, [disposeLegacyView, stopRealtime]);

  const startLogin = useCallback((): void => {
    if (!activeRef.current || loggingOutRef.current || typeof login.start !== 'function') return;
    const kind = login.state?.kind;
    if (kind === undefined || kind === 'signed_out' || kind === 'expired' || kind === 'failure') {
      void login.start();
    }
  }, [login]);

  const enterLogin = useCallback((clearSync = true): void => {
    if (!activeRef.current) return;
    sessionGenerationRef.current += 1;
    stopLocalWorkspace();
    if (clearSync && typeof sync.clear === 'function') sync.clear();
    setLoadError(null);
    setScreen('login');
    if (typeof login.stop === 'function') login.stop();
    startLogin();
  }, [login, startLogin, stopLocalWorkspace, sync]);

  const loadWorkspace = useCallback((clearFirst = false): void => {
    if (!activeRef.current) return;
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
        enterLogin(true);
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
      if (state.authRequired || isUnauthorized(error)) {
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
  }, [enterLogin, stopLocalWorkspace, sync]);

  const logout = useCallback((): void => {
    if (!activeRef.current || loggingOutRef.current) return;
    loggingOutRef.current = true;
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
    if (workspaceState.authRequired && !loggingOutRef.current) enterLogin(true);
  }, [enterLogin, workspaceState.authRequired]);

  useEffect(() => {
    const previousKind = previousLoginKindRef.current;
    previousLoginKindRef.current = loginState.kind;
    if (loginState.kind === 'signed_in' && previousKind !== 'signed_in' && !loggingOutRef.current) {
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
      const cleanup = WorkspaceView.mount(root, sync, logout, webSessionApi(api), enterLogin);
      legacyViewCleanupRef.current = cleanup;
      return () => {
        if (legacyViewCleanupRef.current !== cleanup) return;
        legacyViewCleanupRef.current = undefined;
        cleanup();
        root.replaceChildren();
      };
    }

    if (screen === 'login') {
      root.replaceChildren();
      const cleanup = QrLoginView.mount(root, login, () => undefined);
      legacyViewCleanupRef.current = cleanup;
      return () => {
        if (legacyViewCleanupRef.current !== cleanup) return;
        legacyViewCleanupRef.current = undefined;
        cleanup();
        root.replaceChildren();
      };
    }

    disposeLegacyView();
  }, [api, canUseLegacyViews, disposeLegacyView, enterLogin, login, logout, screen, sync, workspaceState.snapshot?.workspace_id]);

  const showPlaceholder = !canUseLegacyViews || screen === 'loading' || screen === 'error';
  const routeKey = route.kind === 'task' ? `task:${route.id}` : route.kind;

  return (
    <div data-testid="muyu-app" data-route={routeKey}>
      <div data-testid="react-route" data-route={routeKey} aria-live="polite" />
      {showPlaceholder ? placeholder(screen, loadError ?? workspaceState.error, () => loadWorkspace()) : null}
      <div ref={legacyRootRef} data-testid="legacy-app-root" />
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
        <>
          <p role="alert">{error ?? '无法加载工作区，请检查网络后重试。'}</p>
          <button type="button" onClick={onRetry}>重试</button>
        </>
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
