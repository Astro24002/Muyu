import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import { WebSessionView } from '../src/ui/web-session-view';
import type { WebSessionSummary } from '../src/api/types';

const activeSession: WebSessionSummary = {
  id: 'session-active',
  status: 'ACTIVE',
  origin: 'https://muyu.example',
  created_at: '2026-08-28T09:00:00.000Z',
  expires_at: '2026-08-29T03:00:00.000Z',
};

const expiredSession: WebSessionSummary = {
  id: 'session-expired',
  status: 'EXPIRED',
  origin: 'https://old.example',
  created_at: '2026-08-20T09:00:00.000Z',
  expires_at: '2026-08-21T03:00:00.000Z',
};
const testNow = Date.parse('2026-08-28T12:00:00.000Z');

function apiStub(sessions: WebSessionSummary[] = [activeSession, expiredSession]) {
  return {
    listWebSessions: vi.fn().mockResolvedValue(sessions),
    revokeWebSession: vi.fn().mockResolvedValue(undefined),
    revokeAllWebSessions: vi.fn().mockResolvedValue({ revoked_count: sessions.length }),
  };
}

describe('WebSessionView', () => {
  afterEach(() => {
    document.body.replaceChildren();
    vi.restoreAllMocks();
  });

  it('shows only active sessions and never renders credentials or digests', async () => {
    const root = document.createElement('div');
    const api = apiStub();

    const cleanup = WebSessionView.mount(root, api, { now: () => testNow });
    await settle();

    expect(api.listWebSessions).toHaveBeenCalledOnce();
    expect(root.querySelectorAll('.web-session-item')).toHaveLength(1);
    expect(root.textContent).toContain('https://muyu.example');
    expect(root.textContent).not.toContain('https://old.example');
    expect(root.textContent).not.toMatch(/digest|token|cookie|proof/i);
    cleanup();
  });

  it('removes a session after a successful revoke without losing the remaining list', async () => {
    const root = document.createElement('div');
    const second = { ...activeSession, id: 'session-second', origin: 'https://second.example' };
    const api = apiStub([activeSession, second]);

    const cleanup = WebSessionView.mount(root, api, { now: () => testNow });
    await settle();
    root.querySelector<HTMLButtonElement>('[data-action="revoke"][data-session-id="session-active"]')!.click();
    await settle();

    expect(api.revokeWebSession).toHaveBeenCalledExactlyOnceWith('session-active');
    expect(root.querySelector('[data-session-id="session-active"]')).toBeNull();
    expect(root.querySelector('[data-session-id="session-second"]')).not.toBeNull();
    cleanup();
  });

  it('keeps the list visible when revocation fails', async () => {
    const root = document.createElement('div');
    const api = apiStub();
    api.revokeWebSession.mockRejectedValue(new Error('network'));

    const cleanup = WebSessionView.mount(root, api, { now: () => testNow });
    await settle();
    root.querySelector<HTMLButtonElement>('[data-action="revoke"]')!.click();
    await settle();

    expect(root.querySelector('[data-session-id="session-active"]')).not.toBeNull();
    expect(root.querySelector('[role="alert"]')?.textContent).toContain('network');
    cleanup();
  });

  it('clears active sessions after revoke-all succeeds', async () => {
    const root = document.createElement('div');
    const api = apiStub();
    const cleanup = WebSessionView.mount(root, api, { now: () => testNow });
    await settle();

    root.querySelector<HTMLButtonElement>('[data-action="revoke-all"]')!.click();
    await settle();

    expect(api.revokeAllWebSessions).toHaveBeenCalledOnce();
    expect(root.querySelectorAll('[data-session-id]')).toHaveLength(0);
    expect(root.textContent).toContain('没有有效的网页登录会话');
    cleanup();
  });

  it('returns to QR login on any unauthorized response', async () => {
    const root = document.createElement('div');
    const api = apiStub();
    const onAuthRequired = vi.fn();
    api.listWebSessions.mockRejectedValue(new ApiError(401, 'web_session_expired', 'expired'));

    const cleanup = WebSessionView.mount(root, api, { now: () => testNow, onAuthRequired });
    await settle();

    expect(onAuthRequired).toHaveBeenCalledOnce();
    expect(root.querySelector('[data-session-id]')).toBeNull();
    cleanup();
  });

  it('ignores a response from a previous workspace after the view is disposed', async () => {
    const root = document.createElement('div');
    let resolve!: (sessions: WebSessionSummary[]) => void;
    const api = apiStub();
    api.listWebSessions.mockReturnValue(new Promise((value) => { resolve = value; }));

    const cleanup = WebSessionView.mount(root, api, { now: () => testNow });
    cleanup();
    resolve([activeSession]);
    await settle();

    expect(root.querySelector('[data-session-id]')).toBeNull();
  });
});

async function settle(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}
