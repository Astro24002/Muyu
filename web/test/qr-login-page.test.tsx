import { fireEvent, screen } from '@testing-library/react';
import { act } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { QrLoginController, QrLoginState } from '../src/auth/qr-login';
import { QrLoginPage } from '../src/pages/QrLoginPage';
import { render } from './react-test-helpers';

vi.mock('qrcode', () => ({ default: { toCanvas: vi.fn().mockResolvedValue(undefined) } }));

const challenge = {
  challenge_id: 'challenge-1',
  qr_payload: '{"challenge_id":"challenge-1","scan_nonce":"scan"}',
  origin: 'https://app.test',
  safety_code: '123456',
  expires_at: '2026-08-31T12:05:00.000Z',
};

describe('QrLoginPage', () => {
  it('renders the safe QR challenge details and exposes poll and regenerate actions', async () => {
    const login = fakeLogin({ kind: 'waiting_for_approval', challenge });

    render(<QrLoginPage controller={login} />);
    await act(async () => { await Promise.resolve(); });

    expect(screen.getByRole('main', { name: '二维码登录' })).toBeInTheDocument();
    expect(screen.getByRole('img', { name: '登录二维码' })).toBeInTheDocument();
    expect(screen.getByText('安全码')).toBeInTheDocument();
    expect(screen.getByText('123456')).toBeInTheDocument();
    expect(screen.getByText('当前站点')).toBeInTheDocument();
    expect(screen.getByText('https://app.test')).toBeInTheDocument();
    expect(screen.getByText('过期时间')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '检查授权状态' })).toBeEnabled();
    expect(screen.getByRole('button', { name: '重新生成二维码' })).toBeEnabled();
    expect(document.body).not.toHaveTextContent('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA');

    fireEvent.click(screen.getByRole('button', { name: '检查授权状态' }));
    fireEvent.click(screen.getByRole('button', { name: '重新生成二维码' }));
    expect(login.poll).toHaveBeenCalledOnce();
    expect(login.start).toHaveBeenCalledOnce();
  });

  it('shows creating, exchanging, expired, failure, and signed-out states without leaking challenge data', () => {
    const login = fakeLogin({ kind: 'creating' });
    const { rerender } = render(<QrLoginPage controller={login} />);

    expect(screen.getByText('正在生成二维码。')).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: '登录二维码' })).toBeNull();

    const challengeState: QrLoginState = { kind: 'exchanging', challenge };
    (login as unknown as { state: QrLoginState }).state = challengeState;
    rerender(<QrLoginPage controller={login} state={challengeState} />);
    expect(screen.getByText('正在完成登录。')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '检查授权状态' })).toBeDisabled();
    expect(screen.queryByRole('button', { name: '重新生成二维码' })).toBeNull();

    const expiredState: QrLoginState = { kind: 'expired', message: '二维码已失效，请重新生成。' };
    rerender(<QrLoginPage controller={login} state={expiredState} />);
    expect(screen.getByRole('alert')).toHaveTextContent('二维码已失效，请重新生成。');
    expect(screen.getByRole('button', { name: '重新生成二维码' })).toBeEnabled();

    const failureState: QrLoginState = { kind: 'failure', message: '无法检查授权状态，请重试。' };
    rerender(<QrLoginPage controller={login} state={failureState} />);
    expect(screen.getByRole('alert')).toHaveTextContent('无法检查授权状态，请重试。');

    rerender(<QrLoginPage controller={login} state={{ kind: 'signed_out' }} />);
    expect(screen.getByText('请生成二维码登录。')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '重新生成二维码' })).toBeEnabled();
    expect(document.body).not.toHaveTextContent('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA');
  });
});

function fakeLogin(state: QrLoginState): QrLoginController {
  return {
    state,
    start: vi.fn().mockResolvedValue(undefined),
    poll: vi.fn().mockResolvedValue(undefined),
    stop: vi.fn(),
    dispose: vi.fn(),
    subscribe: vi.fn(() => () => undefined),
  } as unknown as QrLoginController;
}
