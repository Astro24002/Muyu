import { API_BASE_URL } from '../config';
import type {
  ApprovalActionResult,
  ActivityEvent,
  Anniversary,
  Habit,
  LedgerEntry,
  LedgerEntryType,
  LedgerSummary,
  PreparationTaskResult,
  HomeResponse,
  PendingApproval,
  TaskApprovalRequest,
  TaskComment,
  TaskItem,
  TaskApprovalRequestType,
  WebChallenge,
  WebChallengeStatus,
  WebSessionExchange,
  WebSessionRevokeAllResult,
  WebSessionSummary,
  WorkspaceChanges,
  WorkspaceClassification,
  WorkspaceSnapshot,
} from './types';
export type AppliedTaskWriteResult = TaskItem & { cursor: number };
export type TaskWriteResult = AppliedTaskWriteResult | PendingApproval;

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
    const headers = { Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...this.headers(init?.headers), 'X-Muyu-Client-Contract': '2026-09-v1' };
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
    const entries = value instanceof Headers ? [...value.entries()] : Array.isArray(value) ? value : Object.entries(value);
    const result: Record<string, string> = {};
    for (const [key, item] of entries) {
      if (key.toLowerCase() === 'x-muyu-client-contract') continue;
      result[key] = item;
    }
    return result;
  }

  createWebChallenge(input: { origin: string; browserProofHash: string }): Promise<WebChallenge> { return this.request('/api/v1/web-login/challenges', { method: 'POST', body: { origin: input.origin, browser_proof_hash: input.browserProofHash } }); }
  getWebChallengeStatus(id: string): Promise<WebChallengeStatus> { return this.request(`/api/v1/web-login/challenges/${encodeURIComponent(id)}`); }
  exchangeWebChallenge(id: string, browserProof: string): Promise<WebSessionExchange> { return this.request(`/api/v1/web-login/challenges/${encodeURIComponent(id)}/exchange`, { method: 'POST', body: { browser_proof: browserProof } }); }
  logoutWebSession(): Promise<void> { return this.request<void>('/api/v1/web-login/logout', { method: 'POST' }); }
  listWebSessions(): Promise<WebSessionSummary[]> { return this.request('/api/v1/web-sessions'); }
  revokeWebSession(id: string): Promise<void> { return this.request<void>(`/api/v1/web-sessions/${encodeURIComponent(id)}/revoke`, { method: 'POST' }); }
  revokeAllWebSessions(): Promise<WebSessionRevokeAllResult> { return this.request('/api/v1/web-sessions/revoke-all', { method: 'POST' }); }
  getHome(): Promise<HomeResponse> { return this.request('/api/v1/home'); }
  getWorkspaceSnapshot(): Promise<WorkspaceSnapshot> { return this.request('/api/v1/workspaces/current/snapshot'); }
  getWorkspaceClassifications(): Promise<WorkspaceClassification[]> { return this.request('/api/v1/workspaces/current/classifications'); }
  getWorkspaceChanges(afterCursor: number): Promise<WorkspaceChanges> { return this.request(`/api/v1/workspaces/current/changes?after_cursor=${encodeURIComponent(afterCursor)}`); }
  createTask(input: { requestId: string; title: string; description: string; quadrant: 'Q1' | 'Q2' | 'Q3' | 'Q4'; labels?: string[]; nextStepText?: string; acceptanceCriteria?: string; targetHandlerId?: string }): Promise<AppliedTaskWriteResult> { return this.request('/api/v1/tasks', { method: 'POST', body: { request_id: input.requestId, title: input.title, description: input.description, quadrant: input.quadrant, labels: input.labels ?? [], ...(input.nextStepText === undefined ? {} : { next_step_text: input.nextStepText }), ...(input.acceptanceCriteria === undefined ? {} : { acceptance_criteria: input.acceptanceCriteria }), ...(input.targetHandlerId === undefined ? {} : { target_handler_id: input.targetHandlerId }) } }); }
  createTaskInvitation(input: { requestId: string; title: string; description: string; quadrant: 'Q1' | 'Q2' | 'Q3' | 'Q4'; labels: string[]; nextStepText: string; acceptanceCriteria: string; targetHandlerId: string }): Promise<PendingApproval> { return this.request('/api/v1/task-invitations', { method: 'POST', body: { request_id: input.requestId, title: input.title, description: input.description, quadrant: input.quadrant, labels: input.labels, next_step_text: input.nextStepText, acceptance_criteria: input.acceptanceCriteria, target_handler_id: input.targetHandlerId } }); }
  listLedger(input: { month: string; type?: LedgerEntryType; category?: string }): Promise<LedgerEntry[]> { return this.request<{ items: LedgerEntry[] }>(`/api/v1/ledger?month=${encodeURIComponent(input.month)}${input.type ? `&type=${encodeURIComponent(input.type)}` : ''}${input.category ? `&category=${encodeURIComponent(input.category)}` : ''}`).then((value) => value.items); }
  getLedgerSummary(month: string): Promise<LedgerSummary> { return this.request(`/api/v1/ledger/summary?month=${encodeURIComponent(month)}`); }
  createLedger(input: { requestId: string; type: LedgerEntryType; amount: string; title: string; category: string; payerOrPayeeId: string; date: string; note?: string }): Promise<LedgerEntry> { return this.request('/api/v1/ledger', { method: 'POST', body: { request_id: input.requestId, type: input.type, amount: input.amount, title: input.title, category: input.category, payer_or_payee_id: input.payerOrPayeeId, date: input.date, ...(input.note ? { note: input.note } : {}) } }); }
  patchLedger(id: string, input: { requestId: string; expectedVersion: number; changes: Record<string, unknown> }): Promise<LedgerEntry> { return this.request(`/api/v1/ledger/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, expected_version: input.expectedVersion, changes: input.changes } }); }
  deleteLedger(id: string, input: { requestId: string; expectedVersion: number; confirm: boolean }): Promise<LedgerEntry> { return this.request(`/api/v1/ledger/${encodeURIComponent(id)}`, { method: 'DELETE', body: { request_id: input.requestId, expected_version: input.expectedVersion, confirm: input.confirm } }); }
  listHabits(owner: 'mine' | 'other' | 'all' = 'mine'): Promise<Habit[]> { return this.request<{ items: Habit[] }>(`/api/v1/habits?owner=${encodeURIComponent(owner)}`).then((value) => value.items); }
  createHabit(input: { requestId: string; title: string; frequency: 'DAILY' | 'WEEKLY' | 'MONTHLY'; startDate?: string; note?: string }): Promise<Habit> { return this.request('/api/v1/habits', { method: 'POST', body: { request_id: input.requestId, title: input.title, frequency: input.frequency, ...(input.startDate ? { start_date: input.startDate } : {}), ...(input.note ? { note: input.note } : {}) } }); }
  patchHabit(id: string, input: { requestId: string; expectedVersion: number; changes: Record<string, unknown> }): Promise<Habit> { return this.request(`/api/v1/habits/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, expected_version: input.expectedVersion, changes: input.changes } }); }
  habitAction(id: string, action: 'checkin' | 'undo' | 'pause' | 'resume', input: { requestId: string; expectedVersion: number }): Promise<Habit> { return this.request<Record<string, unknown>>(`/api/v1/habits/${encodeURIComponent(id)}/${action}`, { method: 'POST', body: { request_id: input.requestId, expected_version: input.expectedVersion } }).then((value) => (value.habit && typeof value.habit === 'object' ? value.habit : value) as Habit); }
  deleteHabit(id: string, input: { requestId: string; expectedVersion: number; confirm: boolean }): Promise<Habit> { return this.request(`/api/v1/habits/${encodeURIComponent(id)}`, { method: 'DELETE', body: { request_id: input.requestId, expected_version: input.expectedVersion, confirm: input.confirm } }); }
  listAnniversaries(): Promise<Anniversary[]> { return this.request<{ items: Anniversary[] }>('/api/v1/anniversaries').then((value) => value.items); }
  createAnniversary(input: { requestId: string; title: string; anchorDate: string; kind: 'ANNIVERSARY' | 'BIRTHDAY' | 'IMPORTANT_DAY'; prepareDays: number; note?: string }): Promise<Anniversary> { return this.request('/api/v1/anniversaries', { method: 'POST', body: { request_id: input.requestId, title: input.title, anchor_date: input.anchorDate, kind: input.kind, prepare_days: input.prepareDays, ...(input.note ? { note: input.note } : {}) } }); }
  patchAnniversary(id: string, input: { requestId: string; expectedVersion: number; changes: Record<string, unknown> }): Promise<Anniversary> { return this.request(`/api/v1/anniversaries/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, expected_version: input.expectedVersion, changes: input.changes } }); }
  deleteAnniversary(id: string, input: { requestId: string; expectedVersion: number; confirm: boolean }): Promise<Anniversary> { return this.request(`/api/v1/anniversaries/${encodeURIComponent(id)}`, { method: 'DELETE', body: { request_id: input.requestId, expected_version: input.expectedVersion, confirm: input.confirm } }); }
  prepareAnniversary(id: string, requestId: string): Promise<PreparationTaskResult> { return this.request(`/api/v1/anniversaries/${encodeURIComponent(id)}/prepare`, { method: 'POST', body: { request_id: requestId } }); }
  patchTask(id: string, input: { requestId: string; changes: Record<string, unknown>; baseFieldVersions: Record<string, number> }): Promise<TaskWriteResult> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}`, { method: 'PATCH', body: { request_id: input.requestId, changes: input.changes, base_field_versions: input.baseFieldVersions } }); }
  requestAgreementUpdate(id: string, input: { requestId: string; acceptanceCriteria: string; baseFieldVersion: number }): Promise<PendingApproval> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/agreement-requests`, { method: 'POST', body: { request_id: input.requestId, acceptance_criteria: input.acceptanceCriteria, base_field_version: input.baseFieldVersion } }); }
  requestTaskCancellation(id: string, input: { requestId: string; reason: string; baseLifecycleVersion: number }): Promise<PendingApproval> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/cancellation-requests`, { method: 'POST', body: { request_id: input.requestId, reason: input.reason, base_lifecycle_version: input.baseLifecycleVersion } }); }
  resolveConflict(taskId: string, conflictId: string, input: { requestId: string; resolution: 'current' | 'proposed' }): Promise<AppliedTaskWriteResult> { return this.request(`/api/v1/tasks/${encodeURIComponent(taskId)}/conflicts/${encodeURIComponent(conflictId)}/resolve`, { method: 'POST', body: { request_id: input.requestId, resolution: input.resolution } }); }
  transitionTask(id: string, input: { requestId: string; targetStatus: string; baseStatusVersion: number; blockedReason?: string; resumeHandlerId?: string; waitingForUserId?: string; reviewRejectionReason?: string; reviewContent?: string }): Promise<TaskWriteResult> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/transition`, { method: 'POST', body: { request_id: input.requestId, target_status: input.targetStatus, base_status_version: input.baseStatusVersion, blocked_reason: input.blockedReason, resume_handler_id: input.resumeHandlerId, waiting_for_user_id: input.waitingForUserId, review_rejection_reason: input.reviewRejectionReason, review_content: input.reviewContent } }); }
  getTaskComments(id: string): Promise<TaskComment[]> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/comments`); }
  addTaskComment(id: string, input: { requestId: string; body: string }): Promise<TaskComment & { cursor?: number }> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/comments`, { method: 'POST', body: { request_id: input.requestId, body: input.body } }); }
  getTaskDelays(id: string): Promise<Array<Record<string, unknown>>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/delays`); }
  addTaskDelay(id: string, input: { requestId: string; newDueAt: string; reason: string; note?: string }): Promise<Record<string, unknown>> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/delays`, { method: 'POST', body: { request_id: input.requestId, new_due_at: input.newDueAt, reason: input.reason, note: input.note } }); }
  getTaskActivity(id: string): Promise<ActivityEvent[]> { return this.request(`/api/v1/tasks/${encodeURIComponent(id)}/activity`); }

  createApprovalRequest(input: {
    workspaceId?: string;
    requestId: string;
    taskId?: string | null;
    commentId?: string | null;
    requestType: TaskApprovalRequestType;
    proposedChanges: Record<string, unknown>;
    baseFieldVersions: Record<string, number>;
  }): Promise<TaskApprovalRequest & { cursor?: number }> {
    return this.request(this.approvalPath(input.workspaceId), {
      method: 'POST',
      body: {
        request_id: input.requestId,
        task_id: input.taskId ?? null,
        comment_id: input.commentId ?? null,
        request_type: input.requestType,
        proposed_changes: input.proposedChanges,
        base_field_versions: input.baseFieldVersions,
      },
    });
  }

  createWorkspaceClassification(input: { requestId: string; name: string }): Promise<PendingApproval> {
    return this.request('/api/v1/workspaces/current/classifications', {
      method: 'POST',
      body: { request_id: input.requestId, name: input.name },
    });
  }

  listApprovalRequests(workspaceId?: string | 'incoming' | 'outgoing' | { workspaceId?: string; box?: 'incoming' | 'outgoing' }, box?: 'incoming' | 'outgoing'): Promise<TaskApprovalRequest[]> {
    const options: { workspaceId?: string; box?: 'incoming' | 'outgoing' } = typeof workspaceId === 'object'
      ? workspaceId
      : workspaceId === 'incoming' || workspaceId === 'outgoing'
        ? { box: workspaceId }
        : { workspaceId, box };
    const query = options.box === undefined ? '' : `?box=${encodeURIComponent(options.box)}`;
    return this.request(`${this.approvalPath(options.workspaceId)}${query}`);
  }

  approveApproval(approvalId: string, input: { workspaceId?: string; requestId: string } | string): Promise<ApprovalActionResult> {
    return this.approvalAction('approve', approvalId, typeof input === 'string' ? { requestId: input } : input);
  }

  rejectApproval(approvalId: string, input: { workspaceId?: string; requestId: string; reason?: string | null } | string): Promise<ApprovalActionResult> {
    return this.approvalAction('reject', approvalId, typeof input === 'string' ? { requestId: input } : input);
  }

  cancelApproval(approvalId: string, input: { workspaceId?: string; requestId: string } | string): Promise<ApprovalActionResult> {
    return this.approvalAction('cancel', approvalId, typeof input === 'string' ? { requestId: input } : input);
  }

  deleteTaskComment(taskId: string, commentId: string, input: { requestId: string; baseVersion: number }): Promise<(TaskComment & { cursor?: number }) | PendingApproval> {
    return this.request(`/api/v1/tasks/${encodeURIComponent(taskId)}/comments/${encodeURIComponent(commentId)}`, {
      method: 'DELETE',
      body: { request_id: input.requestId, base_version: input.baseVersion },
    });
  }

  private approvalPath(workspaceId?: string): string {
    return `/api/v1/workspaces/${encodeURIComponent(workspaceId ?? 'current')}/approval-requests`;
  }

  private approvalAction(action: 'approve' | 'reject' | 'cancel', approvalId: string, input: { workspaceId?: string; requestId: string; reason?: string | null }): Promise<ApprovalActionResult> {
    const body: Record<string, unknown> = { request_id: input.requestId };
    if (action === 'reject' && input.reason !== undefined) body.reason = input.reason;
    return this.request(`${this.approvalPath(input.workspaceId)}/${encodeURIComponent(approvalId)}/${action}`, { method: 'POST', body });
  }
}

export function createRequestId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
