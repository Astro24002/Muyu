import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import type { WorkspaceSnapshot } from '../src/api/types';
import { App } from '../src/app';
import { WorkspaceSocket, type SocketLike } from '../src/realtime/workspace-socket';
import { WorkspaceSyncController } from '../src/sync/workspace-sync';

const snapshot: WorkspaceSnapshot = {
  workspace_id: 'workspace-1',
  workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
  members: [],
  tasks: [],
  conflicts: [],
  cursor: 5,
};

class FakeSocket implements SocketLike {
  onopen: ((event: Event) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  readonly close = vi.fn();

  open(): void { this.onopen?.(new Event('open')); }
  fail(): void { this.onerror?.(new Event('error')); this.onclose?.(new CloseEvent('close')); }
  message(data: unknown): void { this.onmessage?.({ data: JSON.stringify(data) } as MessageEvent); }
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
  reject(error: unknown): void;
} {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, resolve, reject };
}

class FakeLogin {
  state: { kind: 'signed_out' | 'signed_in'; expiresAt?: string } = { kind: 'signed_out' };
  readonly start = vi.fn(async () => undefined);
  readonly stop = vi.fn(() => { this.state = { kind: 'signed_out' }; });
  readonly dispose = vi.fn();
  private listeners = new Set<(state: typeof this.state) => void>();

  subscribe(listener: (state: typeof this.state) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  signIn(): void {
    this.state = { kind: 'signed_in', expiresAt: '2026-08-26T00:00:00.000Z' };
    for (const listener of this.listeners) listener(this.state);
  }
}

class FakeSync {
  state = { snapshot: null as WorkspaceSnapshot | null, cursor: 0, loading: false, stale: false, error: null as string | null, conflicts: [], authRequired: false };
  readonly loadSnapshot = vi.fn(async () => undefined);
  readonly pull = vi.fn(async () => undefined);
  readonly refresh = vi.fn(async () => undefined);
  readonly createTask = vi.fn(async () => undefined);
  readonly patchTask = vi.fn(async () => undefined);
  readonly resolveConflict = vi.fn(async () => undefined);
  readonly clear = vi.fn(() => {
    this.state = { snapshot: null, cursor: 0, loading: false, stale: false, error: null, conflicts: [], authRequired: false };
    this.emit();
  });
  readonly dispose = vi.fn();
  private listeners = new Set<(state: typeof this.state) => void>();

  subscribe(listener: (state: typeof this.state) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(): void { for (const listener of this.listeners) listener(this.state); }
}

describe('App', () => {
  afterEach(() => {
    document.body.replaceChildren();
    vi.useRealTimers();
  });

  it('renders QR login when the initial snapshot requires authentication', async () => {
    const api = { logoutWebSession: vi.fn() };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state.authRequired = true;
    sync.state.error = '无法加载工作区，请检查网络后重试。';
    sync.loadSnapshot.mockImplementation(async () => {
      sync.emit();
      return undefined;
    });
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn() });
    const root = document.createElement('div');

    app.mount(root);
    await settle();

    expect(sync.loadSnapshot).toHaveBeenCalledOnce();
    expect(root.textContent).toContain('二维码登录');
    expect(login.start).toHaveBeenCalledOnce();
    app.dispose();
  });

  it('loads the snapshot before rendering workspace controls after QR exchange', async () => {
    const api = { logoutWebSession: vi.fn() };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state.authRequired = true;
    sync.loadSnapshot.mockImplementation(async () => {
      if (login.state.kind === 'signed_in') {
        sync.state = { ...sync.state, snapshot, cursor: 5, authRequired: false, error: null };
        sync.emit();
      }
      return undefined;
    });
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => new FakeSocket()) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    login.signIn();
    await settle();

    expect(sync.loadSnapshot).toHaveBeenCalledTimes(2);
    expect(root.querySelector<HTMLInputElement>('input[placeholder="新任务标题"]')).not.toBeNull();
    app.dispose();
  });

  it('logs out, closes realtime work, and returns to a new QR challenge', async () => {
    const api = { logoutWebSession: vi.fn().mockResolvedValue(undefined) };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state = { ...sync.state, snapshot, cursor: 5 };
    const socket = new FakeSocket();
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => socket) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '退出登录')?.click();
    await settle();

    expect(api.logoutWebSession).toHaveBeenCalledOnce();
    expect(socket.close).toHaveBeenCalledOnce();
    expect(root.textContent).toContain('二维码登录');
    expect(login.start).toHaveBeenCalledOnce();
    app.dispose();
  });

  it('returns to QR login when logout has a recoverable network failure', async () => {
    const api = { logoutWebSession: vi.fn().mockRejectedValue(new TypeError('Network unavailable')) };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state = { ...sync.state, snapshot, cursor: 5 };
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => new FakeSocket()) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '退出登录')?.click();
    await settle();

    expect(root.textContent).toContain('二维码登录');
    app.dispose();
  });

  it('does not render the prior workspace when the new session snapshot load fails', async () => {
    const api = { logoutWebSession: vi.fn().mockResolvedValue(undefined) };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state = { ...sync.state, snapshot, cursor: 5 };
    sync.loadSnapshot.mockImplementation(async () => {
      if (login.state.kind === 'signed_in') {
        sync.state = { ...sync.state, error: '无法加载工作区，请检查网络后重试。' };
        sync.emit();
      }
    });
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => new FakeSocket()) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '退出登录')?.click();
    await settle();
    login.signIn();
    await settle();

    expect(sync.clear).toHaveBeenCalledOnce();
    expect(root.querySelector('[role="alert"]')?.textContent).toContain('无法加载工作区');
    expect(root.querySelector('input[placeholder="新任务标题"]')).toBeNull();
    app.dispose();
  });

  it('does not render a stale session snapshot after logout and a new-session load failure', async () => {
    const api = { logoutWebSession: vi.fn().mockResolvedValue(undefined) };
    const login = new FakeLogin();
    const sessionASnapshot = deferred<WorkspaceSnapshot>();
    const syncApi = {
      getWorkspaceSnapshot: vi.fn()
        .mockResolvedValueOnce(snapshot)
        .mockReturnValueOnce(sessionASnapshot.promise)
        .mockRejectedValueOnce(new TypeError('Network unavailable')),
      getWorkspaceChanges: vi.fn(),
      createTask: vi.fn(),
      patchTask: vi.fn(),
      resolveConflict: vi.fn(),
    };
    const sync = new WorkspaceSyncController(syncApi as never);
    const app = new App({ api: api as never, login: login as never, sync, socketFactory: vi.fn(() => new FakeSocket()) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    await settle();
    expect(root.querySelector('input[placeholder="新任务标题"]')).not.toBeNull();
    const pendingSessionARefresh = sync.refresh();
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '退出登录')?.click();
    await settle();
    sessionASnapshot.resolve({ ...snapshot, cursor: 6 });
    await pendingSessionARefresh;
    login.signIn();
    await settle();
    await settle();

    expect(root.querySelector('[role="alert"]')?.textContent).toContain('无法加载工作区');
    expect(root.querySelector('input[placeholder="新任务标题"]')).toBeNull();
    app.dispose();
  });

  it('clears the workspace snapshot when a mounted workspace requires authentication', async () => {
    const api = { logoutWebSession: vi.fn().mockResolvedValue(undefined) };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state = { ...sync.state, snapshot, cursor: 5 };
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => new FakeSocket()) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    sync.state = { ...sync.state, authRequired: true };
    sync.emit();
    await settle();

    expect(sync.clear).toHaveBeenCalledOnce();
    expect(root.textContent).toContain('二维码登录');
    expect(root.querySelector('input[placeholder="新任务标题"]')).toBeNull();
    app.dispose();
  });

  it('pulls when a higher validated workspace cursor arrives over realtime', async () => {
    const api = { logoutWebSession: vi.fn() };
    const login = new FakeLogin();
    const sync = new FakeSync();
    sync.state = { ...sync.state, snapshot, cursor: 5 };
    const socket = new FakeSocket();
    const app = new App({ api: api as never, login: login as never, sync: sync as never, socketFactory: vi.fn(() => socket) });
    const root = document.createElement('div');

    app.mount(root);
    await settle();
    expect(socket.onmessage).not.toBeNull();
    socket.message({ type: 'workspace.changed', workspace_id: 'workspace-1', cursor: 6 });
    socket.message({ type: 'workspace.changed', workspace_id: 'other-workspace', cursor: 7 });
    socket.message({ type: 'workspace.changed', workspace_id: 'workspace-1', cursor: '7' });
    await settle();

    expect(sync.pull).toHaveBeenCalledOnce();
    app.dispose();
  });
});

describe('WorkspaceSocket', () => {
  afterEach(() => vi.useRealTimers());

  it('emits only a higher-cursor hint for its own workspace', () => {
    const raw = new FakeSocket();
    const onHint = vi.fn();
    const socket = new WorkspaceSocket('workspace-1', { factory: () => raw, onHint });

    socket.connect();
    raw.message({ type: 'workspace.changed', workspace_id: 'workspace-1', cursor: 6 });
    raw.message({ type: 'workspace.changed', workspace_id: 'other-workspace', cursor: 7 });

    expect(onHint).toHaveBeenCalledExactlyOnceWith(6);
    socket.dispose();
  });

  it('uses a cookie-authenticated URL and cancels pending reconnects on dispose', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const socket = new WorkspaceSocket('workspace-1', {
      factory: vi.fn(() => {
        const value = new FakeSocket();
        sockets.push(value);
        return value;
      }),
      location: new URL('https://app.test:8443/'),
    });

    socket.connect();
    sockets[0].fail();
    socket.dispose();
    vi.advanceTimersByTime(10_000);

    expect(socket.url).toBe('wss://app.test:8443/api/v1/realtime?workspace_id=workspace-1');
    expect(socket.url).not.toMatch(/bearer|cookie|token/i);
    expect(sockets).toHaveLength(1);
  });

  it('reconnects with bounded delays after repeated close events', () => {
    vi.useFakeTimers();
    const sockets: FakeSocket[] = [];
    const socket = new WorkspaceSocket('workspace-1', {
      factory: vi.fn(() => {
        const value = new FakeSocket();
        sockets.push(value);
        return value;
      }),
      location: new URL('http://app.test/'),
    });

    socket.connect();
    sockets[0].fail();
    vi.advanceTimersByTime(999);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    sockets[1].fail();
    vi.advanceTimersByTime(1_999);
    expect(sockets).toHaveLength(2);
    vi.advanceTimersByTime(1);
    sockets[2].fail();
    vi.advanceTimersByTime(4_999);
    expect(sockets).toHaveLength(3);
    vi.advanceTimersByTime(1);

    expect(sockets).toHaveLength(4);
    socket.dispose();
  });
});

async function settle(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}
