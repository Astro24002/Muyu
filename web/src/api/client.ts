import { API_BASE_URL } from '../config';
import type { TaskItem, WebChallenge, WebChallengeStatus, WebSessionExchange, WebSessionRevokeAllResult, WebSessionSummary, WorkspaceChanges, WorkspaceSnapshot } from './types';
export type TaskWriteResult = TaskItem & { cursor: number };

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
    let payload: unknown;
    const rawBody = await response.text();
    if (rawBody.trim() !== '') {
      try { payload = JSON.parse(rawBody); } catch { payload = undefined; }
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
  listWebSessions(): Promise<WebSessionSummary[]> { return this.request('/api/v1/web-sessions'); }
  revokeWebSession(id: string): Promise<void> { return this.request<void>(`/api/v1/web-sessions/${encodeURIComponent(id)}/revoke`, { method: 'POST' }); }
  revokeAllWebSessions(): Promise<WebSessionRevokeAllResult> { return this.request('/api/v1/web-sessions/revoke-all', { method: 'POST' }); }
  getWorkspaceSnapshot(): Promise<WorkspaceSnapshot> { return this.request('/api/v1/workspaces/current/snapshot'); }
  getWorkspaceChanges(afterCursor: number): Promise<WorkspaceChanges> { return this.request(`/api/v1/workspaces/current/changes?after_cursor=${encodeURIComponent(afterCursor)}`); }
  createTask(input: { requestId: string; title: string; description: string }): Promise<TaskItem & { cursor: number }> { return this.request('/api/v1/tasks', { method: 'POST', body: { request_id: input.requestId, title: input.title, description: input.description } }); }
  patchTask(id: string, input: { requestId: string; changes: Record<string, unknown>; baseFieldVersions: Record<string, number> }): Promise<TaskItem & { cursor: number }> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, changes: input.changes, base_field_versions: input.baseFieldVersions } }); }
  resolveConflict(taskId: string, conflictId: string, input: { requestId: string; resolution: 'current' | 'proposed' }): Promise<TaskItem & { cursor: number }> { return this.request(`/api/v1/tasks/${encodeURIComponent(taskId)}/conflicts/${encodeURIComponent(conflictId)}/resolve`, { method: 'POST', body: { request_id: input.requestId, resolution: input.resolution } }); }
  transitionTask(id: string, input: { requestId: string; targetStatus: string; baseStatusVersion: number; blockedReason?: string; resumeHandlerId?: string; waitingForUserId?: string }): Promise<TaskWriteResult> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/transition`, { method: 'POST', body: { request_id: input.requestId, target_status: input.targetStatus, base_status_version: input.baseStatusVersion, blocked_reason: input.blockedReason, resume_handler_id: input.resumeHandlerId, waiting_for_user_id: input.waitingForUserId } }); }
  getTaskComments(id: string): Promise<Array<Record<string, unknown>>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/comments`); }
  addTaskComment(id: string, input: { requestId: string; body: string }): Promise<Record<string, unknown>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/comments`, { method: 'POST', body: { request_id: input.requestId, body: input.body } }); }
  getTaskDelays(id: string): Promise<Array<Record<string, unknown>>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/delays`); }
  addTaskDelay(id: string, input: { requestId: string; newDueAt: string; reason: string; note?: string }): Promise<Record<string, unknown>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/delays`, { method: 'POST', body: { request_id: input.requestId, new_due_at: input.newDueAt, reason: input.reason, note: input.note } }); }
  getTaskActivity(id: string): Promise<Array<Record<string, unknown>>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/activity`); }
}
