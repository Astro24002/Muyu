import { API_BASE_URL } from '../config';
import type { TaskItem, WebChallenge, WebChallengeStatus, WebSessionExchange, WorkspaceChanges, WorkspaceSnapshot } from './types';

export type ApiRequestInit = Omit<RequestInit, 'body'> & { body?: unknown };

export class ApiError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string, public readonly details: unknown = {}) {
    super(message);
    this.name = 'ApiError';
  }
}

export class ApiClient {
  private readonly baseUrl: string;

  constructor(baseUrl = API_BASE_URL) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
  }

  async request<T>(path: string, init?: ApiRequestInit): Promise<T> {
    const { body, ...requestInit } = init ?? {};
    const headers = { Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...this.headers(init?.headers) };
    const response = await fetch(this.baseUrl + path, {
      ...requestInit,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'include',
      headers,
    });
    if (response.status === 204) return undefined as T;
    const hasBody = response.headers.get('content-length') !== '0' && response.status !== 204;
    let payload: unknown;
    if (hasBody) {
      try { payload = await response.json(); } catch { payload = undefined; }
    }
    if (!response.ok) {
      const problem = payload && typeof payload === 'object' ? payload as Record<string, unknown> : {};
      throw new ApiError(response.status, typeof problem.code === 'string' ? problem.code : 'REQUEST_FAILED', typeof problem.message === 'string' ? problem.message : '请求失败，请稍后重试', problem.details ?? {});
    }
    return payload as T;
  }

  private headers(value?: HeadersInit): Record<string, string> {
    if (!value) return {};
    if (value instanceof Headers) return Object.fromEntries(value.entries());
    if (Array.isArray(value)) return Object.fromEntries(value);
    return value as Record<string, string>;
  }

  createWebChallenge(input: { origin: string; browserProofHash: string }): Promise<WebChallenge> { return this.request('/api/v1/web-login/challenges', { method: 'POST', body: { origin: input.origin, browser_proof_hash: input.browserProofHash } }); }
  getWebChallengeStatus(id: string): Promise<WebChallengeStatus> { return this.request(`/api/v1/web-login/challenges/${encodeURIComponent(id)}`); }
  exchangeWebChallenge(id: string, browserProof: string): Promise<WebSessionExchange> { return this.request(`/api/v1/web-login/challenges/${encodeURIComponent(id)}/exchange`, { method: 'POST', body: { browser_proof: browserProof } }); }
  logoutWebSession(): Promise<void> { return this.request<void>('/api/v1/web-login/logout', { method: 'POST' }); }
  getWorkspaceSnapshot(): Promise<WorkspaceSnapshot> { return this.request('/api/v1/workspaces/current/snapshot'); }
  getWorkspaceChanges(afterCursor: number): Promise<WorkspaceChanges> { return this.request(`/api/v1/workspaces/current/changes?after_cursor=${encodeURIComponent(afterCursor)}`); }
  createTask(input: { requestId: string; title: string; description: string }): Promise<TaskItem & { cursor: number }> { return this.request('/api/v1/tasks', { method: 'POST', body: { request_id: input.requestId, title: input.title, description: input.description } }); }
  patchTask(id: string, input: { requestId: string; changes: Record<string, unknown>; baseFieldVersions: Record<string, number> }): Promise<TaskItem & { cursor: number }> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, changes: input.changes, base_field_versions: input.baseFieldVersions } }); }
  resolveConflict(taskId: string, conflictId: string, input: { requestId: string; resolution: 'current' | 'proposed' }): Promise<TaskItem & { cursor: number }> { return this.request(`/api/v1/tasks/${encodeURIComponent(taskId)}/conflicts/${encodeURIComponent(conflictId)}/resolve`, { method: 'POST', body: { request_id: input.requestId, resolution: input.resolution } }); }
}
