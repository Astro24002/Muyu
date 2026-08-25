import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../src/api/client';
import { QrLoginController, type QrLoginOptions } from '../src/auth/qr-login';
import { isSessionExpiredError } from '../src/auth/web-session';
import { QrLoginView } from '../src/ui/qr-login-view';

vi.mock('qrcode', () => ({ default: { toCanvas: vi.fn().mockResolvedValue(undefined) } }));

const challenge = {
  challenge_id: 'challenge-1',
  qr_payload: '{"challenge_id":"challenge-1","scan_nonce":"scan"}',
  origin: 'https://app.test',
  safety_code: '123456',
  expires_at: '2026-08-25T12:05:00.000Z',
};

function apiStub() {
  return {
    createWebChallenge: vi.fn().mockResolvedValue(challenge),
    getWebChallengeStatus: vi.fn().mockResolvedValue({ challenge_id: challenge.challenge_id, status: 'PENDING', expires_at: challenge.expires_at }),
    exchangeWebChallenge: vi.fn().mockResolvedValue({ status: 'authenticated', expires_at: '2026-08-26T12:00:00.000Z' }),
  };
}

describe('QrLoginController', () => {
  afterEach(() => vi.restoreAllMocks());

  it('sends only a SHA-256 proof digest when it starts a challenge', async () => {
    const api = apiStub();
    const setInterval = vi.fn(() => 7 as unknown as ReturnType<typeof globalThis.setInterval>);
    const controller = new QrLoginController(api as never, {
      clock: () => Date.parse('2026-08-25T12:00:00.000Z'),
      setInterval,
      clearInterval: vi.fn(),
      origin: () => 'https://app.test',
      crypto: deterministicCrypto(),
    });

    await controller.start();

    expect(api.createWebChallenge).toHaveBeenCalledWith({ origin: 'https://app.test', browserProofHash: 'ae216c2ef5247a3782c135efa279a3e4cdc61094270f5d2be58c6204b7a612c9' });
    expect(JSON.stringify(api.createWebChallenge.mock.calls)).not.toContain('AQIDBA');
    expect(controller.state).toMatchObject({ kind: 'waiting_for_approval', challenge });
    expect(setInterval).toHaveBeenCalledWith(expect.any(Function), 2_000);
  });

  it('exchanges once after approval and clears the raw proof', async () => {
    const api = apiStub();
    api.getWebChallengeStatus.mockResolvedValue({ challenge_id: challenge.challenge_id, status: 'APPROVED', expires_at: challenge.expires_at });
    const clearInterval = vi.fn();
    const controller = new QrLoginController(api as never, options(clearInterval));
    const states: string[] = [];
    controller.subscribe((state) => states.push(state.kind));

    await controller.start();
    await controller.poll();
    await controller.poll();

    expect(states).toContain('exchanging');
    expect(controller.state).toMatchObject({ kind: 'signed_in' });
    expect(api.exchangeWebChallenge).toHaveBeenCalledTimes(1);
    expect(api.exchangeWebChallenge).toHaveBeenCalledWith('challenge-1', 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA');
    expect(clearInterval).toHaveBeenCalled();
    expect(JSON.stringify(controller)).not.toContain('AQIDBA');
  });

  it.each([
    ['EXPIRED', undefined],
    ['REVOKED', undefined],
    [undefined, new ApiError(401, 'web_login_expired', 'expired')],
    [undefined, new ApiError(410, 'web_login_expired', 'expired')],
  ])('stops polling and clears proof for terminal status %s', async (status, error) => {
    const api = apiStub();
    if (error) api.getWebChallengeStatus.mockRejectedValue(error);
    else api.getWebChallengeStatus.mockResolvedValue({ challenge_id: challenge.challenge_id, status, expires_at: challenge.expires_at });
    const clearInterval = vi.fn();
    const controller = new QrLoginController(api as never, options(clearInterval));

    await controller.start();
    await controller.poll();

    expect(controller.state).toMatchObject({ kind: 'expired' });
    expect(clearInterval).toHaveBeenCalled();
    expect(api.exchangeWebChallenge).not.toHaveBeenCalled();
    expect(JSON.stringify(controller)).not.toContain('AQIDBA');
  });

  it('uses a safe failure message and never includes API secrets', async () => {
    const api = apiStub();
    api.getWebChallengeStatus.mockRejectedValue(new ApiError(500, 'SERVER', 'proof=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA; cookie=secret'));
    const controller = new QrLoginController(api as never, options(vi.fn()));

    await controller.start();
    await controller.poll();

    expect(controller.state).toEqual({ kind: 'failure', message: '无法检查授权状态，请重试。' });
    expect(JSON.stringify(controller.state)).not.toContain('secret');
  });

  it('clears the proof when stopped or disposed', async () => {
    const api = apiStub();
    const controller = new QrLoginController(api as never, options(vi.fn()));

    await controller.start();
    controller.stop();
    expect(JSON.stringify(controller)).not.toContain('AQIDBA');
    await controller.start();
    controller.dispose();
    expect(JSON.stringify(controller)).not.toContain('AQIDBA');
  });

  it('ignores an exchange response after a newer QR challenge starts', async () => {
    const api = apiStub();
    const exchange = deferred<{ status: 'authenticated'; expires_at: string }>();
    api.getWebChallengeStatus.mockResolvedValue({
      challenge_id: challenge.challenge_id,
      status: 'APPROVED',
      expires_at: challenge.expires_at,
    });
    api.exchangeWebChallenge.mockReturnValueOnce(exchange.promise);
    api.createWebChallenge
      .mockResolvedValueOnce(challenge)
      .mockResolvedValueOnce({ ...challenge, challenge_id: 'challenge-2' });
    const controller = new QrLoginController(api as never, options(vi.fn()));

    await controller.start();
    const polling = controller.poll();
    await Promise.resolve();
    await controller.start();
    exchange.resolve({ status: 'authenticated', expires_at: '2026-08-26T12:00:00.000Z' });
    await polling;

    expect(controller.state).toMatchObject({
      kind: 'waiting_for_approval',
      challenge: { challenge_id: 'challenge-2' },
    });
  });

  it('allows a new challenge to poll while an obsolete poll is still pending', async () => {
    const api = apiStub();
    const obsoletePoll = deferred<{ challenge_id: string; status: 'PENDING'; expires_at: string }>();
    api.getWebChallengeStatus.mockReturnValueOnce(obsoletePoll.promise);
    api.createWebChallenge
      .mockResolvedValueOnce(challenge)
      .mockResolvedValueOnce({ ...challenge, challenge_id: 'challenge-2' });
    const controller = new QrLoginController(api as never, options(vi.fn()));

    await controller.start();
    const firstPoll = controller.poll();
    await Promise.resolve();
    await controller.start();
    await controller.poll();
    obsoletePoll.resolve({ challenge_id: challenge.challenge_id, status: 'PENDING', expires_at: challenge.expires_at });
    await firstPoll;

    expect(api.getWebChallengeStatus).toHaveBeenCalledTimes(2);
    expect(api.getWebChallengeStatus).toHaveBeenLastCalledWith('challenge-2');
  });
});

describe('web session errors', () => {
  it('recognizes session expiration without reading browser cookies', () => {
    expect(isSessionExpiredError(new ApiError(401, 'web_session_expired', 'expired'))).toBe(true);
    expect(isSessionExpiredError(new ApiError(401, 'other', 'expired'))).toBe(false);
  });
});

describe('QrLoginView', () => {
  it('renders safe challenge details and starts a new challenge from retry', async () => {
    const root = document.createElement('main');
    const start = vi.fn();
    const poll = vi.fn();
    const subscribe = vi.fn(() => () => undefined);
    QrLoginView.mount(root, { state: { kind: 'waiting_for_approval', challenge }, start, poll, subscribe } as unknown as QrLoginController, vi.fn());
    await Promise.resolve();

    expect(root.textContent).toContain('安全码');
    expect(root.textContent).toContain('123456');
    expect(root.textContent).toContain('https://app.test');
    expect(root.querySelector('canvas')).not.toBeNull();
    expect(root.textContent).not.toContain('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA');
    root.querySelector<HTMLButtonElement>('button[data-action="retry"]')!.click();
    expect(start).toHaveBeenCalledOnce();
    root.querySelector<HTMLButtonElement>('button[data-action="poll"]')!.click();
    expect(poll).toHaveBeenCalledOnce();
  });
});

function options(clearInterval: NonNullable<QrLoginOptions['clearInterval']>): QrLoginOptions {
  return {
    clock: () => Date.parse('2026-08-25T12:00:00.000Z'),
    setInterval: vi.fn(() => 7 as unknown as ReturnType<typeof globalThis.setInterval>),
    clearInterval,
    origin: () => 'https://app.test',
    crypto: deterministicCrypto(),
  };
}

function deterministicCrypto(): Crypto {
  return {
    getRandomValues: <T extends ArrayBufferView | null>(array: T): T => {
      if (array instanceof Uint8Array) array.set(Array.from({ length: array.length }, (_, index) => index + 1));
      return array;
    },
    subtle: {
      digest: vi.fn().mockResolvedValue(hexBuffer('ae216c2ef5247a3782c135efa279a3e4cdc61094270f5d2be58c6204b7a612c9')),
    },
  } as unknown as Crypto;
}

function hexBuffer(value: string): ArrayBuffer {
  return Uint8Array.from(value.match(/.{2}/g)!, (byte) => Number.parseInt(byte, 16)).buffer;
}

function deferred<T>(): { promise: Promise<T>; resolve(value: T): void } {
  let resolve!: (value: T) => void;
  return {
    promise: new Promise<T>((done) => { resolve = done; }),
    resolve: (value) => resolve(value),
  };
}
