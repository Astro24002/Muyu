import { act, fireEvent } from '@testing-library/react';
import { renderToString } from 'react-dom/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, type ApiClient } from '../src/api/client';
import { App } from '../src/app/App';
import type { QrLoginState } from '../src/auth/qr-login';
import type { SocketLike, WebSocketFactory } from '../src/realtime/workspace-socket';
import { WorkspaceSyncController, type WorkspaceSyncState } from '../src/sync/workspace-sync';
import type { WorkspaceSnapshot } from '../src/api/types';
import { render } from './react-test-helpers';

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

class FakeLogin {
  state: QrLoginState = { kind: 'signed_out' };
  readonly start = vi.fn(async () => undefined);
  readonly stop = vi.fn(() => {
    this.state = { kind: 'signed_out' };
    this.emit();
  });
  readonly dispose = vi.fn();
  private readonly listeners = new Set<(state: QrLoginState) => void>();

  subscribe(listener: (state: QrLoginState) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  signIn(): void {
    this.state = { kind: 'signed_in', expiresAt: '2026-09-01T00:00:00.000Z' };
    this.emit();
  }

  private emit(): void {
    for (const listener of this.listeners) listener(this.state);
  }
}

function createFakeSync(initial: WorkspaceSyncState): {
  sync: WorkspaceSyncController;
  loadSnapshot: ReturnType<typeof vi.fn>;
  setState: (state: WorkspaceSyncState) => void;
  emit: () => void;
} {
  let current = initial;
  const listeners = new Set<(state: WorkspaceSyncState) => void>();
  const loadSnapshot = vi.fn(async () => undefined);
  const sync = {
    get state(): WorkspaceSyncState { return current; },
    loadSnapshot,
    pull: vi.fn(async () => undefined),
    clear: vi.fn(() => {
      current = emptyWorkspaceState();
      for (const listener of listeners) listener(current);
    }),
    dispose: vi.fn(),
    subscribe(listener: (state: WorkspaceSyncState) => void): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  } as unknown as WorkspaceSyncController;
  return {
    sync,
    loadSnapshot,
    setState: (state) => { current = state; },
    emit: () => { for (const listener of listeners) listener(current); },
  };
}

describe('React app lifecycle', () => {
  afterEach(() => {
    vi.useRealTimers();
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });
  });

  it('loads once, pulls a newer realtime cursor, and disposes the socket on unmount', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const socket = new FakeSocket();
    const socketFactory = vi.fn(() => socket);
    const { unmount } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} socketFactory={socketFactory} />);

    await settle();
    expect(fake.sync.loadSnapshot).toHaveBeenCalledOnce();
    expect(socketFactory).toHaveBeenCalledOnce();

    socket.message({ type: 'workspace.changed', workspace_id: 'workspace-1', cursor: 6 });
    await settle();
    expect(fake.sync.pull).toHaveBeenCalledOnce();

    unmount();
    expect(socket.close).toHaveBeenCalledOnce();
    expect(login.dispose).toHaveBeenCalledOnce();
    expect(fake.sync.dispose).toHaveBeenCalledOnce();
  });

  it('ignores controller emissions after the React app unmounts', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const { container, unmount } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} />);

    await settle();
    unmount();
    fake.setState({ ...workspaceState(), error: 'late update' });
    fake.emit();
    await settle();

    expect(container).toBeEmptyDOMElement();
  });

  it('pulls every ten seconds only while the page is visible and catches up immediately after reconnect', async () => {
    vi.useFakeTimers();
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const sockets: FakeSocket[] = [];
    const socketFactory: WebSocketFactory = vi.fn(() => {
      const socket = new FakeSocket();
      sockets.push(socket);
      return socket;
    });
    const { unmount } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} socketFactory={socketFactory} />);
    await settle();

    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' });
    sockets[0].fail();
    vi.advanceTimersByTime(10_000);
    expect(fake.sync.pull).not.toHaveBeenCalled();

    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });
    vi.advanceTimersByTime(10_000);
    expect(fake.sync.pull).toHaveBeenCalledOnce();

    vi.advanceTimersByTime(1_000);
    sockets[1].open();
    expect(fake.sync.pull).toHaveBeenCalledTimes(2);
    vi.advanceTimersByTime(10_000);
    expect(fake.sync.pull).toHaveBeenCalledTimes(2);
    unmount();
  });

  it('coalesces repeated visible fallback ticks while a pull is in flight', async () => {
    vi.useFakeTimers();
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const pending = deferred<void>();
    const pull = vi.fn(() => pending.promise);
    (fake.sync as unknown as { pull: typeof pull }).pull = pull;
    const sockets: FakeSocket[] = [];
    const socketFactory: WebSocketFactory = vi.fn(() => {
      const socket = new FakeSocket();
      sockets.push(socket);
      return socket;
    });
    const { unmount } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} socketFactory={socketFactory} />);
    await settle();

    sockets[0].fail();
    vi.advanceTimersByTime(30_000);
    expect(pull).toHaveBeenCalledOnce();

    pending.resolve();
    await settle();
    expect(pull).toHaveBeenCalledTimes(2);
    unmount();
  });

  it('cleans local workspace state before logging out and starts a new QR flow', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const socket = new FakeSocket();
    const logoutWebSession = vi.fn().mockResolvedValue(undefined);
    const { getByRole, container } = render(
      <App api={{ logoutWebSession } as unknown as ApiClient} login={login as never} sync={fake.sync} socketFactory={() => socket} />,
    );
    await settle();

    fireEvent.click(getByRole('button', { name: '退出登录' }));
    await settle();

    expect(socket.close).toHaveBeenCalledOnce();
    expect(fake.sync.clear).toHaveBeenCalledOnce();
    expect(logoutWebSession).toHaveBeenCalledOnce();
    expect(socket.close.mock.invocationCallOrder[0]).toBeLessThan(logoutWebSession.mock.invocationCallOrder[0]);
    expect(container).not.toHaveTextContent('新任务标题');
    expect(login.start).toHaveBeenCalledOnce();
  });

  it('ignores a late legacy create completion after logout replaces the workspace with QR login', async () => {
    const lateCreate = deferred<void>();
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const createTask = vi.fn(() => lateCreate.promise);
    (fake.sync as unknown as { createTask: typeof createTask }).createTask = createTask;
    const logoutWebSession = vi.fn().mockResolvedValue(undefined);
    const { container, getByRole, getByPlaceholderText, getByLabelText } = render(
      <App api={{ logoutWebSession } as unknown as ApiClient} login={login as never} sync={fake.sync} />,
    );

    await settle();
    const title = getByPlaceholderText('新任务标题') as HTMLInputElement;
    const labels = getByPlaceholderText('任务标签（逗号分隔）') as HTMLInputElement;
    const quadrant = getByLabelText('新任务四象限') as HTMLSelectElement;
    title.value = 'late task';
    labels.value = 'late';
    quadrant.value = 'Q1';
    title.dispatchEvent(new Event('input', { bubbles: true }));
    labels.dispatchEvent(new Event('input', { bubbles: true }));
    (getByRole('button', { name: '创建任务' }).closest('form') as HTMLFormElement).dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    expect(createTask).toHaveBeenCalledOnce();

    fireEvent.click(getByRole('button', { name: '退出登录' }));
    await settle();
    expect(container).toHaveTextContent('二维码登录');

    lateCreate.resolve();
    await lateCreate.promise;
    await settle();

    expect(container).toHaveTextContent('二维码登录');
    expect(container.querySelector('input[placeholder="新任务标题"]')).toBeNull();
  });

  it('ignores stale legacy task handlers after logout replaces the workspace with QR login', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync({
      ...workspaceState(),
      snapshot: { ...snapshot, tasks: [minimalTask('stale-task')] },
    });
    const { container, getByRole } = render(
      <App api={{} as ApiClient} login={login as never} sync={fake.sync} />,
    );

    await settle();
    const staleTaskRow = container.querySelector<HTMLElement>('.task-row');
    expect(staleTaskRow).not.toBeNull();

    fireEvent.click(getByRole('button', { name: '退出登录' }));
    await settle();
    expect(container).toHaveTextContent('二维码登录');

    staleTaskRow!.dispatchEvent(new MouseEvent('click', { bubbles: true }));

    expect(container).toHaveTextContent('二维码登录');
    expect(container.querySelector('.task-detail')).toBeNull();
  });

  it('starts QR recovery without waiting for a hanging auth-required logout request', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const socket = new FakeSocket();
    const logoutWebSession = vi.fn(() => new Promise<void>(() => undefined));
    const { container } = render(
      <App api={{ logoutWebSession } as unknown as ApiClient} login={login as never} sync={fake.sync} socketFactory={() => socket} />,
    );

    await settle();
    fake.setState({ ...workspaceState(), authRequired: true, error: '登录已失效。' });
    fake.emit();

    expect(login.start).toHaveBeenCalledOnce();
    expect(logoutWebSession).toHaveBeenCalledOnce();
    await settle();
    expect(socket.close).toHaveBeenCalledOnce();
    expect(container).toHaveTextContent('二维码登录');
  });

  it('loads a new workspace when QR sign-in succeeds before explicit logout resolves', async () => {
    const logoutRequest = deferred<void>();
    const oldSnapshot = {
      ...snapshot,
      tasks: [{ ...minimalTask('old-session-task'), workspace_id: 'workspace-1' }],
    };
    const newSnapshot = {
      ...snapshot,
      workspace_id: 'workspace-new',
      workspace: { id: 'workspace-new', name: 'New workspace', status: 'ACTIVE' },
      tasks: [{ ...minimalTask('new-session-task'), workspace_id: 'workspace-new' }],
      cursor: 8,
    };
    const syncApi = {
      getWorkspaceSnapshot: vi.fn().mockResolvedValueOnce(oldSnapshot).mockResolvedValueOnce(newSnapshot),
      getWorkspaceChanges: vi.fn().mockResolvedValue({ workspace_id: 'workspace-new', cursor: 8, changes: [] }),
      createTask: vi.fn(),
      patchTask: vi.fn(),
      resolveConflict: vi.fn(),
      transitionTask: vi.fn(),
      addTaskComment: vi.fn(),
      addTaskDelay: vi.fn(),
    };
    const sync = new WorkspaceSyncController(syncApi as never);
    const login = new FakeLogin();
    const logoutWebSession = vi.fn(() => logoutRequest.promise);
    const { container, getByRole } = render(
      <App api={{ logoutWebSession } as unknown as ApiClient} login={login as never} sync={sync} />,
    );

    await settle();
    expect(container).toHaveTextContent('old-session-task');

    fireEvent.click(getByRole('button', { name: '退出登录' }));
    await settle();
    fireEvent.click(getByRole('button', { name: '重新生成二维码' }));
    login.signIn();
    await settle();
    await settle();

    expect(container).toHaveTextContent('new-session-task');
    expect(container).not.toHaveTextContent('old-session-task');

    logoutRequest.resolve();
    await settle();

    expect(container).toHaveTextContent('new-session-task');
    expect(login.start).toHaveBeenCalledOnce();
  });

  it('clears an unauthorized workspace and returns to QR login without editable controls', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(workspaceState());
    const socket = new FakeSocket();
    const { container } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} socketFactory={() => socket} />);
    await settle();

    fake.setState({ ...workspaceState(), authRequired: true, error: '登录已失效。' });
    fake.emit();
    await settle();

    expect(fake.sync.clear).toHaveBeenCalledOnce();
    expect(socket.close).toHaveBeenCalledOnce();
    expect(container).toHaveTextContent('二维码登录');
    expect(container.querySelector('input[placeholder="新任务标题"]')).toBeNull();
    expect(login.start).toHaveBeenCalledOnce();
  });

  it('shows QR login when the initial workspace load rejects with 401', async () => {
    const login = new FakeLogin();
    const fake = createFakeSync(emptyWorkspaceState());
    fake.loadSnapshot.mockRejectedValue(new ApiError(401, 'unauthorized', 'unauthorized'));
    const { container } = render(<App api={{} as ApiClient} login={login as never} sync={fake.sync} />);

    await settle();

    expect(container).toHaveTextContent('二维码登录');
    expect(login.start).toHaveBeenCalledOnce();
  });

  it('does not render an old snapshot after a new login begins', async () => {
    const first = deferred<WorkspaceSnapshot>();
    const second = deferred<WorkspaceSnapshot>();
    const api = {
      getWorkspaceSnapshot: vi.fn()
        .mockReturnValueOnce(first.promise)
        .mockReturnValueOnce(second.promise),
      getWorkspaceChanges: vi.fn(),
      createTask: vi.fn(),
      patchTask: vi.fn(),
      resolveConflict: vi.fn(),
      transitionTask: vi.fn(),
      addTaskComment: vi.fn(),
      addTaskDelay: vi.fn(),
    };
    const sync = new WorkspaceSyncController(api as never);
    const login = new FakeLogin();
    const { container } = render(<App api={{} as ApiClient} login={login as never} sync={sync} socketFactory={() => new FakeSocket()} />);

    await settle();
    login.signIn();
    await settle();

    second.resolve({ ...snapshot, workspace_id: 'workspace-new', workspace: { ...snapshot.workspace, id: 'workspace-new' }, tasks: [] });
    await second.promise;
    await settle();
    first.resolve({ ...snapshot, tasks: [{ ...minimalTask('old-task'), workspace_id: 'workspace-1' }] });
    await first.promise;
    await settle();

    expect(container).not.toHaveTextContent('old-task');
  });

  it('initializes the App route safely when rendered without a browser window', () => {
    const previousWindow = globalThis.window;
    vi.stubGlobal('window', undefined);
    try {
      const html = renderToString(
        <App api={{} as ApiClient} login={new FakeLogin() as never} sync={createFakeSync(emptyWorkspaceState()).sync} />,
      );
      expect(html).toContain('data-route="today"');
    } finally {
      vi.stubGlobal('window', previousWindow);
    }
  });
});

function workspaceState(): WorkspaceSyncState {
  return { ...emptyWorkspaceState(), snapshot };
}

function emptyWorkspaceState(): WorkspaceSyncState {
  return {
    snapshot: null,
    cursor: 0,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
  };
}

function minimalTask(id: string) {
  return {
    id,
    workspace_id: 'workspace-1',
    parent_task_id: null,
    title: id,
    description: '',
    due_at: null,
    status: 'TODO' as const,
    current_handler_id: '',
    blocked_reason: null,
    blocked_since: null,
    resume_handler_id: null,
    waiting_for_user_id: null,
    planned_start_at: null,
    estimated_minutes: null,
    completed_at: null,
    created_by: '',
    created_at: '2026-08-31T00:00:00.000Z',
    updated_at: '2026-08-31T00:00:00.000Z',
    assignee_ids: [],
    delay_count: 0,
    total_delay_minutes: 0,
    version: 1,
    status_version: 1,
    field_versions: {},
    lifecycle_version: 1,
    deleted_at: null,
    quadrant: 'Q2' as const,
    labels: [],
  };
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (error: unknown) => void;
} {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((promiseResolve, promiseReject) => {
    resolve = promiseResolve;
    reject = promiseReject;
  });
  return { promise, resolve, reject };
}

async function settle(): Promise<void> {
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}
