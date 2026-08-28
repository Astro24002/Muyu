import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import { WebSessionView } from '../src/ui/web-session-view';
import type { WebSessionSummary } from '../src/api/types';
import { WorkspaceView } from '../src/ui/workspace-view';
import type { WorkspaceSyncState } from '../src/sync/workspace-sync';

describe('web session integration boundaries', () => {
  afterEach(() => document.body.replaceChildren());

  it('uses only WebSession APIs and never registers an Android device', async () => {
    const root = document.createElement('div');
    const active: WebSessionSummary = {
      id: 'web-1',
      status: 'ACTIVE',
      origin: 'https://muyu.example',
      created_at: '2026-08-28T09:00:00.000Z',
      expires_at: '2026-08-29T03:00:00.000Z',
    };
    const api = {
      listWebSessions: vi.fn().mockResolvedValue([active]),
      revokeWebSession: vi.fn().mockResolvedValue(undefined),
      revokeAllWebSessions: vi.fn().mockResolvedValue({ revoked_count: 1 }),
      registerAndroidDevice: vi.fn(),
      approveAndroidDevice: vi.fn(),
    };

    const cleanup = WebSessionView.mount(root, api);
    await Promise.resolve();
    await Promise.resolve();

    expect(api.listWebSessions).toHaveBeenCalledOnce();
    expect(api.registerAndroidDevice).not.toHaveBeenCalled();
    expect(api.approveAndroidDevice).not.toHaveBeenCalled();
    cleanup();
  });

  it('does not let a disposed workspace session render into the next workspace', async () => {
    const root = document.createElement('div');
    let resolveOld!: (sessions: WebSessionSummary[]) => void;
    const oldApi = {
      listWebSessions: vi.fn().mockReturnValue(new Promise((value) => { resolveOld = value; })),
      revokeWebSession: vi.fn(),
      revokeAllWebSessions: vi.fn(),
    };
    const oldCleanup = WebSessionView.mount(root, oldApi);
    oldCleanup();

    const newSession: WebSessionSummary = {
      id: 'web-new',
      status: 'ACTIVE',
      origin: 'https://new.example',
      created_at: '2026-08-28T10:00:00.000Z',
      expires_at: '2026-08-29T04:00:00.000Z',
    };
    const newApi = {
      listWebSessions: vi.fn().mockResolvedValue([newSession]),
      revokeWebSession: vi.fn(),
      revokeAllWebSessions: vi.fn(),
    };
    const newCleanup = WebSessionView.mount(root, newApi);
    resolveOld([{
      id: 'web-old',
      status: 'ACTIVE',
      origin: 'https://old.example',
      created_at: '2026-08-27T10:00:00.000Z',
      expires_at: '2026-08-28T10:00:00.000Z',
    }]);
    await Promise.resolve();
    await Promise.resolve();

    expect(root.textContent).toContain('https://new.example');
    expect(root.textContent).not.toContain('https://old.example');
    newCleanup();
  });

  it('loads the session view only after it is opened from the workspace', async () => {
    const root = document.createElement('div');
    const sync = fakeSync();
    const api = {
      listWebSessions: vi.fn().mockResolvedValue([]),
      revokeWebSession: vi.fn(),
      revokeAllWebSessions: vi.fn(),
    };
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn(), api);

    expect(api.listWebSessions).not.toHaveBeenCalled();
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '网页登录会话')!.click();
    await Promise.resolve();
    await Promise.resolve();

    expect(api.listWebSessions).toHaveBeenCalledOnce();
    expect(root.querySelector('.web-session-panel')).not.toBeNull();
    cleanup();
    expect(root.querySelector('.web-session-panel')).toBeNull();
  });

  it('notifies the app to return to QR login when the session panel gets a 401', async () => {
    const root = document.createElement('div');
    const sync = fakeSync();
    const onAuthRequired = vi.fn();
    const api = {
      listWebSessions: vi.fn().mockRejectedValue(new ApiError(401, 'web_session_expired', 'unauthorized')),
      revokeWebSession: vi.fn(),
      revokeAllWebSessions: vi.fn(),
    };
    const cleanup = WorkspaceView.mount(root, sync as never, vi.fn(), api, onAuthRequired);
    Array.from(root.querySelectorAll<HTMLButtonElement>('button')).find((button) => button.textContent === '网页登录会话')!.click();
    await Promise.resolve();
    await Promise.resolve();

    expect(onAuthRequired).toHaveBeenCalledOnce();
    cleanup();
  });
});

function fakeSync(): {
  state: WorkspaceSyncState;
  subscribe: (listener: (state: WorkspaceSyncState) => void) => () => void;
  refresh: ReturnType<typeof vi.fn>;
  createTask: ReturnType<typeof vi.fn>;
} {
  const state: WorkspaceSyncState = {
    snapshot: {
      workspace_id: 'workspace-1',
      workspace: { id: 'workspace-1', name: 'Muyu', status: 'ACTIVE' },
      members: [],
      tasks: [],
      conflicts: [],
      cursor: 1,
    },
    cursor: 1,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
  };
  const listeners = new Set<(state: WorkspaceSyncState) => void>();
  return {
    state,
    subscribe: (listener) => { listeners.add(listener); return () => listeners.delete(listener); },
    refresh: vi.fn(),
    createTask: vi.fn(),
  };
}
