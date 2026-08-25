import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiClient, ApiError } from '../src/api/client';

describe('ApiClient', () => {
  afterEach(() => vi.restoreAllMocks());

  it('sends same-origin JSON requests with credentials and endpoint body', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ challenge_id: 'c1' }), { status: 201 }),
    );
    const client = new ApiClient();

    await expect(client.createWebChallenge({ origin: 'https://app.test', browserProofHash: 'a'.repeat(64) })).resolves.toEqual({ challenge_id: 'c1' });
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/web-login/challenges', expect.objectContaining({
      credentials: 'include',
      body: JSON.stringify({ origin: 'https://app.test', browser_proof_hash: 'a'.repeat(64) }),
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    }));
  });

  it('parses API problems for non-2xx responses', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ code: 'AUTH_REQUIRED', message: 'login required', details: { reason: 'cookie' } }), { status: 401 }));
    await expect(new ApiClient().request('/api/v1/tasks')).rejects.toMatchObject({ status: 401, code: 'AUTH_REQUIRED', message: 'login required', details: { reason: 'cookie' } });
  });

  it('uses a stable fallback for non-JSON failures without exposing headers', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('not json', { status: 503, headers: { Authorization: 'secret' } }));
    const error = await new ApiClient().request('/api/v1/tasks').catch((value) => value);
    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 503, code: 'REQUEST_FAILED', message: '请求失败，请稍后重试' });
    expect(JSON.stringify(error)).not.toContain('secret');
  });

  it('returns undefined for a 204 response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 204 }));
    await expect(new ApiClient().logoutWebSession()).resolves.toBeUndefined();
  });
});
