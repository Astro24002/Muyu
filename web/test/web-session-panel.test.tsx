import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import type { WebSessionSummary } from '../src/api/types';
import { WebSessionPanel, type WebSessionPanelApi } from '../src/components/account/WebSessionPanel';
import { UserMenu } from '../src/components/layout/UserMenu';
import { render } from './react-test-helpers';

const now = Date.parse('2026-09-01T12:00:00Z');
const active: WebSessionSummary = {
  id: 'session-active',
  status: 'ACTIVE',
  origin: 'https://muyu.example',
  created_at: '2026-09-01T09:00:00Z',
  expires_at: '2026-09-02T09:00:00Z',
};
const expired: WebSessionSummary = { ...active, id: 'session-expired', expires_at: '2026-09-01T11:00:00Z' };
const revoked: WebSessionSummary = { ...active, id: 'session-revoked', status: 'REVOKED' };

function apiStub(sessions: WebSessionSummary[] = [active, expired, revoked]): WebSessionPanelApi {
  return {
    listWebSessions: vi.fn().mockResolvedValue(sessions),
    revokeWebSession: vi.fn().mockResolvedValue(undefined),
    revokeAllWebSessions: vi.fn().mockResolvedValue({ revoked_count: sessions.length }),
  };
}

describe('WebSessionPanel', () => {
  it('shows a loading state while the initial session list is pending', () => {
    const api = apiStub();
    vi.mocked(api.listWebSessions).mockReturnValueOnce(new Promise<WebSessionSummary[]>(() => undefined));

    render(<WebSessionPanel api={api} now={() => now} />);

    expect(screen.getByText('正在加载网页登录会话')).toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveAttribute('aria-live', 'polite');
  });

  it('shows a safe local error when loading sessions fails', async () => {
    const api = apiStub();
    vi.mocked(api.listWebSessions).mockRejectedValueOnce(new Error('token leaked by server'));

    render(<WebSessionPanel api={api} now={() => now} />);

    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
    expect(screen.getByRole('alert')).toHaveTextContent('无法加载网页登录会话');
    expect(screen.getByRole('alert')).not.toHaveTextContent('token leaked by server');
  });

  it('renders only active unexpired sessions and never renders secret fields', async () => {
    const response = [{
      ...active,
      token: 'token-secret',
      cookie: 'cookie-secret',
      proof: 'proof-secret',
      digest: 'digest-secret',
    }] as unknown as WebSessionSummary[];
    const api = apiStub(response);

    render(<WebSessionPanel api={api} now={() => now} />);

    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());
    expect(screen.queryByTestId('web-session-item-session-expired')).not.toBeInTheDocument();
    expect(screen.queryByTestId('web-session-item-session-revoked')).not.toBeInTheDocument();
    expect(document.body.textContent).toContain(active.origin!);
    expect(document.body.textContent).not.toMatch(/token-secret|cookie-secret|proof-secret|digest-secret|token|cookie|proof|digest/i);
  });

  it('revokes one session and preserves the rest', async () => {
    const second = { ...active, id: 'session-second', origin: 'https://second.example' };
    const api = apiStub([active, second]);
    render(<WebSessionPanel api={api} now={() => now} />);
    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());

    fireEvent.click(within(screen.getByTestId('web-session-item-session-active')).getByRole('button', { name: '撤销' }));
    await waitFor(() => expect(api.revokeWebSession).toHaveBeenCalledWith(active.id));
    await waitFor(() => expect(screen.queryByTestId('web-session-item-session-active')).not.toBeInTheDocument());
    expect(screen.getByTestId('web-session-item-session-second')).toBeInTheDocument();
  });

  it('keeps a session and reports a local error when revoke fails', async () => {
    const api = apiStub();
    vi.mocked(api.revokeWebSession).mockRejectedValueOnce(new Error('secret failure'));
    render(<WebSessionPanel api={api} now={() => now} />);
    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: '撤销' }));
    await waitFor(() => expect(screen.getByRole('alert')).toBeInTheDocument());
    expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument();
    expect(screen.getByRole('alert')).not.toHaveTextContent('secret failure');
  });

  it('disables duplicate actions while a revoke is pending', async () => {
    let release!: () => void;
    const api = apiStub();
    vi.mocked(api.revokeWebSession).mockReturnValueOnce(new Promise<void>((resolve) => { release = resolve; }));
    render(<WebSessionPanel api={api} now={() => now} />);
    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());

    const revoke = screen.getByRole('button', { name: '撤销' });
    fireEvent.click(revoke);
    fireEvent.click(revoke);
    expect(api.revokeWebSession).toHaveBeenCalledTimes(1);
    expect(revoke).toBeDisabled();
    release();
    await waitFor(() => expect(screen.queryByTestId('web-session-item-session-active')).not.toBeInTheDocument());
  });

  it('revokes all active sessions', async () => {
    const api = apiStub();
    render(<WebSessionPanel api={api} now={() => now} />);
    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: '撤销全部会话' }));
    await waitFor(() => expect(api.revokeAllWebSessions).toHaveBeenCalledOnce());
    await waitFor(() => expect(screen.queryByTestId('web-session-item-session-active')).not.toBeInTheDocument());
    expect(screen.getByText('没有有效的网页登录会话')).toBeInTheDocument();
  });

  it('disables every session action while revoking all sessions', async () => {
    let release!: () => void;
    const api = apiStub();
    vi.mocked(api.revokeAllWebSessions).mockReturnValueOnce(new Promise<void>((resolve) => { release = resolve; }));
    render(<WebSessionPanel api={api} now={() => now} />);
    await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());

    const revokeAll = screen.getByRole('button', { name: '撤销全部会话' });
    const revoke = screen.getByRole('button', { name: '撤销' });
    fireEvent.click(revokeAll);
    fireEvent.click(revokeAll);

    expect(api.revokeAllWebSessions).toHaveBeenCalledOnce();
    expect(revokeAll).toBeDisabled();
    expect(revoke).toBeDisabled();
    release();
    await waitFor(() => expect(screen.getByText('没有有效的网页登录会话')).toBeInTheDocument());
  });

  it('calls auth recovery for 401 from list, revoke, and revoke-all', async () => {
    const operations: Array<'list' | 'revoke' | 'all'> = ['list', 'revoke', 'all'];
    for (const operation of operations) {
      const api = apiStub();
      const onAuthRequired = vi.fn();
      if (operation === 'list') vi.mocked(api.listWebSessions).mockRejectedValueOnce(new ApiError(401, 'AUTH', 'expired'));
      if (operation === 'revoke') vi.mocked(api.revokeWebSession).mockRejectedValueOnce(new ApiError(401, 'AUTH', 'expired'));
      if (operation === 'all') vi.mocked(api.revokeAllWebSessions).mockRejectedValueOnce(new ApiError(401, 'AUTH', 'expired'));
      const { unmount } = render(<WebSessionPanel api={api} now={() => now} onAuthRequired={onAuthRequired} />);
      if (operation !== 'list') {
        await waitFor(() => expect(screen.getByTestId('web-session-item-session-active')).toBeInTheDocument());
        fireEvent.click(screen.getByRole('button', { name: operation === 'revoke' ? '撤销' : '撤销全部会话' }));
      }
      await waitFor(() => expect(onAuthRequired).toHaveBeenCalledOnce());
      unmount();
    }
  });
});

describe('UserMenu session integration', () => {
  it('does not mount a blank session surface when the API is unavailable', () => {
    render(<UserMenu />);

    fireEvent.click(screen.getByRole('button', { name: '用户菜单' }));

    expect(screen.queryByText('网页登录会话')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '退出登录' })).toBeInTheDocument();
  });

  it('keeps escape/outside focus behavior and supports logout beside sessions', async () => {
    const api = apiStub([]);
    const onLogout = vi.fn();
    render(<UserMenu sessionApi={api} now={() => now} onLogout={onLogout} />);

    const trigger = screen.getByRole('button', { name: '用户菜单' });
    fireEvent.click(trigger);
    await waitFor(() => expect(screen.getByText('网页登录会话')).toBeInTheDocument());
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();

    fireEvent.click(trigger);
    fireEvent.mouseDown(document.body);
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();

    fireEvent.click(trigger);
    fireEvent.click(screen.getByRole('button', { name: '退出登录' }));
    expect(onLogout).toHaveBeenCalledOnce();
  });
});
