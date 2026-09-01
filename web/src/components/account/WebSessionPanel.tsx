import { useCallback, useEffect, useRef, useState, type JSX } from 'react';
import { ApiError } from '../../api/client';
import type { WebSessionSummary } from '../../api/types';
import type { WebSessionViewApi } from '../../ui/web-session-view';

export type WebSessionPanelApi = WebSessionViewApi;

export interface WebSessionPanelProps {
  api: WebSessionPanelApi;
  onAuthRequired?: () => void;
  now?: () => number;
  className?: string;
}

type BusyAction = 'revoke' | 'revoke-all' | null;
type PanelState = {
  sessions: WebSessionSummary[];
  loading: boolean;
  error: string | null;
};

const defaultNow = (): number => Date.now();

export function WebSessionPanel({ api, onAuthRequired, now = defaultNow, className }: WebSessionPanelProps): JSX.Element {
  const [state, setState] = useState<PanelState>({ sessions: [], loading: true, error: null });
  const [busy, setBusy] = useState<BusyAction>(null);
  const nowRef = useRef(now);
  const mountedRef = useRef(false);
  const generationRef = useRef(0);
  const busyRef = useRef<BusyAction>(null);
  const expiryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  nowRef.current = now;

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      generationRef.current += 1;
      busyRef.current = null;
      if (expiryTimerRef.current !== null) {
        clearTimeout(expiryTimerRef.current);
        expiryTimerRef.current = null;
      }
    };
  }, []);

  const load = useCallback((): void => {
    const requestGeneration = ++generationRef.current;
    setState((current) => ({ ...current, loading: true, error: null }));

    void api.listWebSessions().then((sessions) => {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState({ sessions: activeSessions(sessions, nowRef.current()), loading: false, error: null });
    }).catch((error: unknown) => {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState((current) => ({ ...current, loading: false, error: loadErrorMessage(error) }));
      notifyAuthRequired(error, onAuthRequired);
    });
  }, [api, onAuthRequired]);

  useEffect(() => {
    load();
    return () => {
      generationRef.current += 1;
      busyRef.current = null;
      if (mountedRef.current) setBusy(null);
    };
  }, [load]);

  useEffect(() => {
    if (expiryTimerRef.current !== null) {
      clearTimeout(expiryTimerRef.current);
      expiryTimerRef.current = null;
    }

    const nextExpiry = state.sessions.reduce<number | null>((earliest, session) => {
      const expiresAt = Date.parse(session.expires_at);
      if (!Number.isFinite(expiresAt)) return earliest;
      return earliest === null ? expiresAt : Math.min(earliest, expiresAt);
    }, null);
    if (nextExpiry === null) return undefined;

    const timer = setTimeout(() => {
      expiryTimerRef.current = null;
      setState((current) => {
        const sessions = activeSessions(current.sessions, nowRef.current());
        return sessions.length === current.sessions.length ? current : { ...current, sessions };
      });
    }, Math.max(0, nextExpiry - nowRef.current()));
    expiryTimerRef.current = timer;

    return () => {
      clearTimeout(timer);
      if (expiryTimerRef.current === timer) expiryTimerRef.current = null;
    };
  }, [now, state.sessions]);

  const revoke = useCallback(async (id: string): Promise<void> => {
    if (!mountedRef.current || busyRef.current !== null) return;
    const requestGeneration = ++generationRef.current;
    busyRef.current = 'revoke';
    setBusy('revoke');
    setState((current) => ({ ...current, loading: true, error: null }));

    try {
      await api.revokeWebSession(id);
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState((current) => ({
        ...current,
        sessions: current.sessions.filter((session) => session.id !== id),
        error: null,
      }));
    } catch (error) {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState((current) => ({ ...current, error: revokeErrorMessage(error) }));
      notifyAuthRequired(error, onAuthRequired);
    } finally {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      busyRef.current = null;
      setBusy(null);
      setState((current) => ({ ...current, loading: false }));
    }
  }, [api, onAuthRequired]);

  const revokeAll = useCallback(async (): Promise<void> => {
    if (!mountedRef.current || busyRef.current !== null) return;
    const requestGeneration = ++generationRef.current;
    busyRef.current = 'revoke-all';
    setBusy('revoke-all');
    setState((current) => ({ ...current, loading: true, error: null }));

    try {
      await api.revokeAllWebSessions();
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState({ sessions: [], loading: false, error: null });
    } catch (error) {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      setState((current) => ({ ...current, loading: false, error: revokeAllErrorMessage(error) }));
      notifyAuthRequired(error, onAuthRequired);
    } finally {
      if (!isCurrent(mountedRef.current, generationRef.current, requestGeneration)) return;
      busyRef.current = null;
      setBusy(null);
    }
  }, [api, onAuthRequired]);

  const isBusy = busy !== null;
  const panelClassName = ['web-session-panel', className].filter(Boolean).join(' ');

  return (
    <section className={panelClassName} aria-label="网页登录会话" aria-busy={state.loading || isBusy}>
      <div className="web-session-panel__header">
        <h2>网页登录会话</h2>
        <button type="button" className="web-session-panel__refresh" onClick={load} disabled={state.loading || isBusy}>
          刷新会话
        </button>
      </div>

      {state.loading && state.sessions.length === 0 ? (
        <p className="web-session-panel__status" role="status" aria-live="polite">正在加载网页登录会话</p>
      ) : null}

      {isBusy ? (
        <p className="web-session-panel__status" role="status" aria-live="polite">
          {busy === 'revoke-all' ? '正在撤销全部会话' : '正在撤销会话'}
        </p>
      ) : null}

      {state.error ? <p className="web-session-panel__error" role="alert">{state.error}</p> : null}

      {state.sessions.length > 0 ? (
        <>
          <button type="button" className="web-session-panel__revoke-all" onClick={() => void revokeAll()} disabled={state.loading || isBusy}>
            撤销全部会话
          </button>
          <div className="web-session-list">
            {state.sessions.map((session) => (
              <article className="web-session-item" data-testid={`web-session-item-${session.id}`} key={session.id}>
                <div className="web-session-item__details">
                  <strong>{session.origin ?? '未标注来源'}</strong>
                  <span>创建于 {formatDate(session.created_at)}</span>
                  <span>过期于 {formatDate(session.expires_at)}</span>
                </div>
                <button
                  type="button"
                  className="web-session-item__revoke"
                  onClick={() => void revoke(session.id)}
                  disabled={state.loading || isBusy}
                >
                  撤销
                </button>
              </article>
            ))}
          </div>
        </>
      ) : !state.loading ? (
        <p className="web-session-panel__empty">没有有效的网页登录会话</p>
      ) : null}
    </section>
  );
}

function activeSessions(sessions: WebSessionSummary[], now: number): WebSessionSummary[] {
  return sessions.filter((session) => session.status === 'ACTIVE' && Date.parse(session.expires_at) > now);
}

function isCurrent(mounted: boolean, generation: number, requestGeneration: number): boolean {
  return mounted && generation === requestGeneration;
}

function isUnauthorized(error: unknown): boolean {
  if (error instanceof ApiError) return error.status === 401;
  return Boolean(error && typeof error === 'object' && 'status' in error && error.status === 401);
}

function notifyAuthRequired(error: unknown, callback?: () => void): void {
  if (isUnauthorized(error)) callback?.();
}

function loadErrorMessage(error: unknown): string {
  return isUnauthorized(error) ? '登录状态已过期，请重新登录。' : '无法加载网页登录会话，请稍后重试。';
}

function revokeErrorMessage(error: unknown): string {
  return isUnauthorized(error) ? '登录状态已过期，请重新登录。' : '撤销会话失败，请稍后重试。';
}

function revokeAllErrorMessage(error: unknown): string {
  return isUnauthorized(error) ? '登录状态已过期，请重新登录。' : '无法撤销全部会话，请稍后重试。';
}

function formatDate(value: string): string {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}
