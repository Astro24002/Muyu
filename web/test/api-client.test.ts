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

  it('uses the WebSession management endpoints with browser credentials', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const path = String(input);
      if (path.endsWith('/api/v1/web-sessions')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      if (path.includes('/api/v1/web-sessions/session-1/revoke')) {
        return new Response(null, { status: 204 });
      }
      return new Response(JSON.stringify({ revoked_count: 1 }), { status: 200 });
    });
    const client = new ApiClient();

    await expect(client.listWebSessions()).resolves.toEqual([]);
    await expect(client.revokeWebSession('session-1')).resolves.toBeUndefined();
    await expect(client.revokeAllWebSessions()).resolves.toEqual({ revoked_count: 1 });

    expect(fetchMock).toHaveBeenCalledTimes(3);
    for (const [, init] of fetchMock.mock.calls) expect(init).toEqual(expect.objectContaining({ credentials: 'include' }));
    expect(fetchMock.mock.calls[1][0]).toBe('/api/v1/web-sessions/session-1/revoke');
  });

  it('normalizes a root base URL without producing protocol-relative paths', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ workspace_id: 'w1' }), { status: 200 }),
    );

    await new ApiClient('/').getWorkspaceSnapshot();

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/workspaces/current/snapshot', expect.anything());
  });

  it('requests the authoritative home projection with browser credentials', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({
        current_tasks: { items: [], has_more: false },
        blocked_tasks: { items: [], has_more: false },
        review_tasks: { items: [], has_more: false },
        pending_approval_count: 0,
      }), { status: 200 }),
    );

    await expect(new ApiClient().getHome()).resolves.toEqual({
      current_tasks: { items: [], has_more: false },
      blocked_tasks: { items: [], has_more: false },
      review_tasks: { items: [], has_more: false },
      pending_approval_count: 0,
    });
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/home', expect.objectContaining({ credentials: 'include' }));
  });

  it('keeps a 202 task write as an explicit pending approval result', async () => {
    const pending = { pending: true, approval_request: { id: 'approval-1' }, cursor: 8 };
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify(pending), { status: 202 }));

    await expect(new ApiClient().patchTask('task-1', {
      requestId: 'request-1',
      changes: { labels: ['工作', '婚礼'] },
      baseFieldVersions: { labels: 1 },
    })).resolves.toEqual(pending);
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/tasks/task-1', expect.objectContaining({
      body: JSON.stringify({ request_id: 'request-1', changes: { labels: ['工作', '婚礼'] }, base_field_versions: { labels: 1 } }),
    }));
  });

  it('sends the required quadrant and complete label array when creating a task', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ id: 'task-1', cursor: 2 }), { status: 201 }),
    );
    await new ApiClient().createTask({ requestId: 'request-1', title: 'Task', description: '', quadrant: 'Q2', labels: ['工作', '婚礼'] });
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/tasks', expect.objectContaining({
      body: JSON.stringify({ request_id: 'request-1', title: 'Task', description: '', quadrant: 'Q2', labels: ['工作', '婚礼'] }),
    }));
  });

  it('sends a review return reason with a status transition', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ id: 'task-1', cursor: 2 }), { status: 200 }),
    );

    await new ApiClient().transitionTask('task-1', {
      requestId: 'request-1',
      targetStatus: 'IN_PROGRESS',
      baseStatusVersion: 3,
      reviewRejectionReason: '请补充验收材料',
    });

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/tasks/task-1/transition', expect.objectContaining({
      body: JSON.stringify({
        request_id: 'request-1',
        target_status: 'IN_PROGRESS',
        base_status_version: 3,
        blocked_reason: undefined,
        resume_handler_id: undefined,
        waiting_for_user_id: undefined,
        review_rejection_reason: '请补充验收材料',
      }),
    }));
  });
});
