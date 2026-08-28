import { ApiError } from '../api/client';
import type { WebSessionSummary } from '../api/types';

export interface WebSessionViewApi {
  listWebSessions: () => Promise<WebSessionSummary[]>;
  revokeWebSession: (id: string) => Promise<void>;
  revokeAllWebSessions: () => Promise<unknown>;
}

export interface WebSessionViewOptions {
  onAuthRequired?: () => void;
  now?: () => number;
}

type ViewState = {
  sessions: WebSessionSummary[];
  loading: boolean;
  error: string | null;
};

export class WebSessionView {
  static mount(root: Element, api: WebSessionViewApi, options: WebSessionViewOptions = {}): () => void {
    let disposed = false;
    let generation = 0;
    let busy = false;
    const now = options.now ?? Date.now;
    let state: ViewState = { sessions: [], loading: true, error: null };
    const panel = document.createElement('section');
    panel.className = 'web-session-panel';
    panel.setAttribute('aria-label', '网页登录会话');
    root.append(panel);

    const render = () => {
      if (disposed) return;
      panel.replaceChildren(buildPanel(state, now(), {
        onRefresh: () => void load(),
        onRevoke: (id) => void revoke(id),
        onRevokeAll: () => void revokeAll(),
      }));
    };

    const load = async (): Promise<void> => {
      const requestGeneration = ++generation;
      state = { ...state, loading: true, error: null };
      render();
      try {
        const sessions = await api.listWebSessions();
        if (disposed || requestGeneration !== generation) return;
        state = { sessions: activeSessions(sessions, now()), loading: false, error: null };
      } catch (error) {
        if (disposed || requestGeneration !== generation) return;
        state = { sessions: [], loading: false, error: errorMessage(error) };
        if (isUnauthorized(error)) options.onAuthRequired?.();
      }
      render();
    };

    const revoke = async (id: string): Promise<void> => {
      if (busy || disposed) return;
      busy = true;
      const requestGeneration = generation;
      state = { ...state, loading: true, error: null };
      render();
      try {
        await api.revokeWebSession(id);
        if (disposed || requestGeneration !== generation) return;
        state = { ...state, sessions: state.sessions.filter((item) => item.id !== id), loading: false, error: null };
      } catch (error) {
        if (disposed || requestGeneration !== generation) return;
        state = { ...state, loading: false, error: errorMessage(error) };
        if (isUnauthorized(error)) options.onAuthRequired?.();
      } finally {
        busy = false;
      }
      render();
    };

    const revokeAll = async (): Promise<void> => {
      if (busy || disposed) return;
      busy = true;
      const requestGeneration = generation;
      state = { ...state, loading: true, error: null };
      render();
      try {
        await api.revokeAllWebSessions();
        if (disposed || requestGeneration !== generation) return;
        state = { sessions: [], loading: false, error: null };
      } catch (error) {
        if (disposed || requestGeneration !== generation) return;
        state = { ...state, loading: false, error: errorMessage(error) };
        if (isUnauthorized(error)) options.onAuthRequired?.();
      } finally {
        busy = false;
      }
      render();
    };

    render();
    void load();
    return () => {
      if (disposed) return;
      disposed = true;
      generation += 1;
      panel.remove();
    };
  }
}

function buildPanel(
  state: ViewState,
  now: number,
  actions: { onRefresh: () => void; onRevoke: (id: string) => void; onRevokeAll: () => void },
): HTMLElement {
  const content = document.createElement('div');
  const heading = document.createElement('h2');
  heading.textContent = '网页登录会话';
  content.append(heading);

  const refresh = actionButton('刷新会话', 'refresh', actions.onRefresh);
  refresh.disabled = state.loading;
  content.append(refresh);

  if (state.loading && state.sessions.length === 0) {
    content.append(text('正在加载网页登录会话。'));
    return content;
  }
  if (state.error) {
    const error = text(state.error);
    error.setAttribute('role', 'alert');
    content.append(error);
  }
  if (state.sessions.length === 0) {
    content.append(text('没有有效的网页登录会话。'));
    return content;
  }

  const revokeAll = actionButton('撤销全部网页登录会话', 'revoke-all', actions.onRevokeAll);
  revokeAll.disabled = state.loading;
  content.append(revokeAll);
  const list = document.createElement('div');
  list.className = 'web-session-list';
  for (const session of state.sessions) {
    const item = document.createElement('article');
    item.className = 'web-session-item';
    item.dataset.sessionId = session.id;
    const origin = session.origin ?? '未标注来源';
    item.append(
      text(origin),
      text(`创建时间: ${formatDate(session.created_at)}`),
      text(`过期时间: ${formatDate(session.expires_at)}`),
    );
    const revoke = actionButton('撤销', 'revoke', () => actions.onRevoke(session.id));
    revoke.dataset.sessionId = session.id;
    revoke.disabled = state.loading || Date.parse(session.expires_at) <= now;
    item.append(revoke);
    list.append(item);
  }
  content.append(list);
  return content;
}

function activeSessions(sessions: WebSessionSummary[], now: number): WebSessionSummary[] {
  return sessions.filter((session) => session.status === 'ACTIVE' && Date.parse(session.expires_at) > now);
}

function isUnauthorized(error: unknown): boolean {
  return error instanceof ApiError && error.status === 401;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '无法加载网页登录会话，请稍后重试。';
}

function actionButton(label: string, action: string, handler: () => void): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.dataset.action = action;
  button.textContent = label;
  button.addEventListener('click', handler);
  return button;
}

function text(value: string): HTMLParagraphElement {
  const node = document.createElement('p');
  node.textContent = value;
  return node;
}

function formatDate(value: string): string {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}
