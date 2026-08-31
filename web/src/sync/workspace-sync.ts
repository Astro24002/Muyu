import { ApiError, type ApiClient, type TaskWriteResult } from '../api/client';
import type { ApprovalActionResult, PendingApproval, TaskApprovalRequest, TaskComment, TaskItem, WorkspaceChange, WorkspaceSnapshot } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';
import { parseTaskItem, upsertTask } from '../tasks/task-model';

export interface WorkspaceSyncState {
  snapshot: WorkspaceSnapshot | null;
  cursor: number;
  loading: boolean;
  stale: boolean;
  error: string | null;
  conflicts: TaskConflict[];
  authRequired: boolean;
  /** A convenient view of snapshot.approval_requests for approval UI consumers. */
  approvals?: TaskApprovalRequest[];
  /** A convenient view of snapshot.comments for detail UI consumers. */
  comments?: TaskComment[];
}

export interface WorkspaceSyncOptions {
  requestIdFactory?: () => string;
}

type Listener = (state: WorkspaceSyncState) => void;
type IsCurrent = () => boolean;

export type WorkspaceSyncApi = Pick<ApiClient,
  | 'getWorkspaceSnapshot'
  | 'getWorkspaceChanges'
  | 'createTask'
  | 'patchTask'
  | 'resolveConflict'
  | 'transitionTask'
  | 'addTaskComment'
  | 'addTaskDelay'
> & Partial<Pick<ApiClient,
  | 'createApprovalRequest'
  | 'listApprovalRequests'
  | 'approveApproval'
  | 'rejectApproval'
  | 'cancelApproval'
  | 'deleteTaskComment'
>>;

const INITIAL_STATE: WorkspaceSyncState = {
  snapshot: null,
  cursor: 0,
  loading: false,
  stale: false,
  error: null,
  conflicts: [],
  authRequired: false,
};

export class WorkspaceSyncController {
  private currentState = INITIAL_STATE;
  private readonly listeners = new Set<Listener>();
  private disposed = false;
  private generation = 0;
  private readonly requestIdFactory: () => string;

  constructor(private readonly api: WorkspaceSyncApi, options: WorkspaceSyncOptions = {}) {
    this.requestIdFactory = options.requestIdFactory ?? createRequestId;
  }

  get state(): WorkspaceSyncState { return this.currentState; }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  dispose(): void {
    this.generation += 1;
    this.disposed = true;
    this.listeners.clear();
  }

  clear(): void {
    this.generation += 1;
    this.currentState = INITIAL_STATE;
    for (const listener of this.listeners) listener(this.currentState);
  }

  async loadSnapshot(): Promise<void> {
    await this.run('无法加载工作区，请检查网络后重试。', async (isCurrent) => {
      const snapshot = await this.api.getWorkspaceSnapshot();
      if (!isCurrent()) return;
      const normalized = normalizeSnapshot(snapshot);
      this.setState({ snapshot: normalized, cursor: normalized.cursor, approvals: normalized.approval_requests, comments: normalized.comments, conflicts: normalizeConflicts(normalized.conflicts), stale: false, error: null, authRequired: false });
    });
  }

  async pull(): Promise<void> {
    if (!this.currentState.snapshot) {
      await this.loadSnapshot();
      return;
    }
    await this.pullFrom(this.currentState.cursor);
  }

  async refresh(): Promise<void> {
    await this.loadSnapshot();
  }

  async createTask(title: string, description: string, quadrant: TaskItem['quadrant'], labels: string[] = []): Promise<void> {
    await this.write('无法创建任务，请检查网络后重试。', () => this.api.createTask({ requestId: this.requestIdFactory(), title, description, quadrant, labels }));
  }

  async patchTask(taskId: string, changes: EditableTaskChanges): Promise<TaskWriteResult | undefined> {
    const task = this.currentState.snapshot?.tasks.find((item) => item.id === taskId);
    if (!task) {
      this.setState({ error: '任务不存在，请刷新后重试。' });
      return undefined;
    }
    const fields = Object.keys(changes);
    const baseFieldVersions = Object.fromEntries(fields.map((field) => [field, task.field_versions[field] ?? 1]));
    return this.write('无法更新任务，请检查网络后重试。', () => this.api.patchTask(taskId, {
      requestId: this.requestIdFactory(),
      changes,
      baseFieldVersions,
    }));
  }

  async resolveConflict(taskId: string, conflictId: string, resolution: 'current' | 'proposed'): Promise<void> {
    await this.write('无法解决冲突，请检查网络后重试。', () => this.api.resolveConflict(taskId, conflictId, {
      requestId: this.requestIdFactory(),
      resolution,
    }), () => this.setState({
      conflicts: this.currentState.conflicts.filter((conflict) => conflict.task_id !== taskId || conflict.id !== conflictId),
    }));
  }

  async transitionTask(taskId: string, targetStatus: string, payload: { blockedReason?: string; resumeHandlerId?: string; waitingForUserId?: string } = {}): Promise<TaskWriteResult | undefined> {
    const task = this.currentState.snapshot?.tasks.find((item) => item.id === taskId);
    if (!task) {
      this.setState({ error: '任务不存在，请刷新后重试。' });
      return undefined;
    }
    return this.write('无法更新任务状态，请检查网络后重试。', () => this.api.transitionTask(taskId, { requestId: this.requestIdFactory(), targetStatus, baseStatusVersion: task.status_version, ...payload }));
  }

  async addComment(taskId: string, body: string): Promise<void> {
    const cursorBeforeWrite = this.currentState.cursor;
    await this.run('无法添加评论，请检查网络后重试。', async () => {
      const result = await this.api.addTaskComment(taskId, { requestId: this.requestIdFactory(), body });
      const cursor = result && typeof result.cursor === 'number' ? result.cursor : cursorBeforeWrite;
      if (cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite);
    });
  }

  async addDelay(taskId: string, newDueAt: string, reason: string, note?: string): Promise<void> {
    await this.run('无法延期任务，请检查网络后重试。', async () => { await this.api.addTaskDelay(taskId, { requestId: this.requestIdFactory(), newDueAt, reason, note }); await this.pull(); });
  }

  async createApprovalRequest(taskId: string, input: {
    requestType: TaskApprovalRequest['request_type'];
    proposedChanges: Record<string, unknown>;
    baseFieldVersions: Record<string, number>;
    commentId?: string | null;
  }): Promise<TaskApprovalRequest | undefined> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return undefined;
    if (!this.api.createApprovalRequest) {
      this.setState({ error: '当前 API 不支持审批操作，请刷新页面后重试。' });
      return undefined;
    }
    const cursorBeforeWrite = this.currentState.cursor;
    let created: TaskApprovalRequest | undefined;
    await this.run('无法提交审批请求，请检查网络后重试。', async () => {
      const approval = await this.api.createApprovalRequest!({
        workspaceId: snapshot.workspace_id,
        requestId: this.requestIdFactory(),
        taskId,
        commentId: input.commentId,
        requestType: input.requestType,
        proposedChanges: input.proposedChanges,
        baseFieldVersions: input.baseFieldVersions,
      });
      created = approval;
      this.mergeApproval(approval);
      const cursor = cursorFrom(approval);
      if (cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite);
    });
    return created;
  }

  async listApprovalRequests(box?: 'incoming' | 'outgoing'): Promise<TaskApprovalRequest[]> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return [];
    if (!this.api.listApprovalRequests) {
      this.setState({ error: '当前 API 不支持审批操作，请刷新页面后重试。' });
      return [];
    }
    let result: TaskApprovalRequest[] = [];
    await this.run('无法加载审批请求，请检查网络后重试。', async () => {
      result = await this.api.listApprovalRequests!(snapshot.workspace_id, box);
      this.mergeApprovals(result);
    });
    return result;
  }

  async approveApproval(approvalId: string): Promise<ApprovalActionResult | undefined> {
    return this.runApprovalAction('approve', approvalId);
  }

  async rejectApproval(approvalId: string, reason?: string): Promise<ApprovalActionResult | undefined> {
    return this.runApprovalAction('reject', approvalId, reason);
  }

  async cancelApproval(approvalId: string): Promise<ApprovalActionResult | undefined> {
    return this.runApprovalAction('cancel', approvalId);
  }

  async deleteTaskComment(taskId: string, commentId: string, baseVersion: number): Promise<(TaskComment & { cursor?: number }) | PendingApproval | undefined> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return undefined;
    if (!this.api.deleteTaskComment) {
      this.setState({ error: '当前 API 不支持评论删除，请刷新页面后重试。' });
      return undefined;
    }
    const cursorBeforeWrite = this.currentState.cursor;
    let result: (TaskComment & { cursor?: number }) | PendingApproval | undefined;
    await this.run('无法删除评论，请检查网络后重试。', async () => {
      const response = await this.api.deleteTaskComment!(taskId, commentId, { requestId: this.requestIdFactory(), baseVersion });
      result = response;
      if (isPendingApproval(response)) this.mergeApproval(response.approval_request);
      else this.mergeComment(response);
      const cursor = cursorFrom(response);
      if (cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite);
    });
    return result;
  }

  /** Alias retained for callers that use the shorter task-detail action name. */
  deleteComment(taskId: string, commentId: string, baseVersion: number): Promise<(TaskComment & { cursor?: number }) | PendingApproval | undefined> {
    return this.deleteTaskComment(taskId, commentId, baseVersion);
  }

  private async write(message: string, operation: () => Promise<TaskWriteResult>, onSuccess?: () => void): Promise<TaskWriteResult | undefined> {
    const cursorBeforeWrite = this.currentState.cursor;
    let result: TaskWriteResult | undefined;
    await this.run(message, async (isCurrent) => {
      const response = await operation();
      result = response;
      if (!isCurrent()) return;
      if (isPendingApproval(response)) {
        this.mergeApproval(response.approval_request);
      } else {
        this.mergeTask(response, response.cursor);
      }
      onSuccess?.();
      if (response.cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite);
    });
    return result;
  }

  private async runApprovalAction(action: 'approve' | 'reject' | 'cancel', approvalId: string, reason?: string): Promise<ApprovalActionResult | undefined> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return undefined;
    const approvalMethod = action === 'approve'
      ? this.api.approveApproval
      : action === 'reject'
        ? this.api.rejectApproval
        : this.api.cancelApproval;
    if (!approvalMethod) {
      this.setState({ error: '当前 API 不支持审批操作，请刷新页面后重试。' });
      return undefined;
    }
    const cursorBeforeAction = this.currentState.cursor;
    let result: ApprovalActionResult | undefined;
    await this.run('无法处理审批请求，请检查网络后重试。', async () => {
      const input = { workspaceId: snapshot.workspace_id, requestId: this.requestIdFactory() };
      const response = action === 'approve'
        ? await this.api.approveApproval!(approvalId, input)
        : action === 'reject'
          ? await this.api.rejectApproval!(approvalId, { ...input, reason })
          : await this.api.cancelApproval!(approvalId, input);
      result = response;
      const cursor = cursorFrom(response);
      if (cursor > cursorBeforeAction) await this.pullFrom(cursorBeforeAction);
      this.mergeApprovalResult(response);
    });
    return result;
  }

  private async pullFrom(afterCursor: number): Promise<void> {
    await this.run('同步失败，请检查网络后重试。', async (isCurrent) => {
      const changes = await this.api.getWorkspaceChanges(afterCursor);
      if (!isCurrent()) return;
      if (!areContiguous(changes.changes, afterCursor) || (changes.changes.length === 0 && changes.cursor !== afterCursor)) {
        await this.loadSnapshot();
        return;
      }
      for (const change of changes.changes) this.applyChange(change);
      const cursor = Math.max(this.currentState.cursor, changes.cursor);
      const snapshot = this.currentState.snapshot;
      this.setState({ snapshot: snapshot ? { ...snapshot, cursor } : null, cursor, approvals: snapshot?.approval_requests, comments: snapshot?.comments, stale: false, error: null, authRequired: false });
    }, true);
  }

  private applyChange(change: WorkspaceChange): void {
    if (!change.resource) return;
    if (change.resource_type === 'task' && isTaskItem(change.resource)) {
      this.mergeTask(change.resource, change.cursor, false);
    } else if (change.resource_type === 'approval_request' && isApprovalRequest(change.resource)) {
      this.mergeApproval(change.resource, change.cursor, false);
    } else if (change.resource_type === 'comment' && isTaskComment(change.resource)) {
      this.mergeComment(change.resource, change.cursor, false);
    }
  }

  private mergeTask(task: TaskItem, cursor: number, updateCursor = true): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const nextSnapshot = { ...snapshot, tasks: upsertTask(snapshot.tasks, parseTaskItem(task)), cursor: updateCursor ? cursor : snapshot.cursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? cursor : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApproval(approval: TaskApprovalRequest, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const approvals = [...(snapshot.approval_requests ?? [])]
      .filter((item) => item.id !== approval.id);
    approvals.push(approval);
    const nextCursor = updateCursor ? cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, approval_requests: approvals, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? cursor : this.currentState.cursor, approvals, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApprovals(approvals: TaskApprovalRequest[]): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const merged = [...(snapshot.approval_requests ?? [])];
    for (const approval of approvals) {
      const index = merged.findIndex((item) => item.id === approval.id);
      if (index === -1) merged.push(approval);
      else merged[index] = approval;
    }
    const nextSnapshot = { ...snapshot, approval_requests: merged };
    this.setState({ snapshot: nextSnapshot, approvals: merged, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeComment(comment: TaskComment, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const comments = [...(snapshot.comments ?? [])].filter((item) => item.id !== comment.id);
    comments.push(comment);
    const nextCursor = updateCursor ? cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, comments, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? cursor : this.currentState.cursor, comments, approvals: nextSnapshot.approval_requests, stale: false, error: null, authRequired: false });
  }

  private mergeApprovalResult(result: ApprovalActionResult): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const approvals = [...(snapshot.approval_requests ?? [])].filter((item) => item.id !== result.approval_request.id);
    approvals.push(result.approval_request);
    const tasks = result.task ? upsertTask(snapshot.tasks, parseTaskItem(result.task)) : snapshot.tasks;
    const comments = result.comment
      ? [...(snapshot.comments ?? [])].filter((item) => item.id !== result.comment!.id).concat(result.comment)
      : snapshot.comments ?? [];
    const cursor = typeof result.cursor === 'number' && result.cursor > snapshot.cursor ? result.cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks, comments, approval_requests: approvals, cursor };
    this.setState({ snapshot: nextSnapshot, cursor, approvals, comments, stale: false, error: null, authRequired: false });
  }

  private async run(message: string, operation: (isCurrent: IsCurrent) => Promise<void>, nested = false): Promise<void> {
    const generation = this.generation;
    const isCurrent = () => !this.disposed && generation === this.generation;
    if (!nested) this.setState({ loading: true, error: null });
    try {
      await operation(isCurrent);
    } catch (error) {
      if (!isCurrent()) return;
      if (error instanceof ApiError && error.status === 410 && error.code === 'sync_cursor_expired') {
        await this.loadSnapshot();
        return;
      }
      if (error instanceof ApiError && error.status === 409 && error.code === 'field_conflict') {
        this.setState({ conflicts: conflictsFromError(error), error: null, stale: false });
        return;
      }
      this.setState({ error: message, stale: this.currentState.snapshot !== null, authRequired: error instanceof ApiError && error.status === 401 });
    } finally {
      if (!nested && isCurrent()) this.setState({ loading: false });
    }
  }

  private setState(update: Partial<WorkspaceSyncState>): void {
    if (this.disposed) return;
    this.currentState = { ...this.currentState, ...update };
    for (const listener of this.listeners) listener(this.currentState);
  }
}

function areContiguous(changes: WorkspaceChange[], afterCursor: number): boolean {
  return changes.every((change, index) => change.cursor === afterCursor + index + 1);
}

function normalizeConflicts(value: Array<Record<string, unknown>>): TaskConflict[] {
  return value.flatMap((item) => {
    if (typeof item.id !== 'string' || typeof item.task_id !== 'string' || typeof item.field !== 'string') return [];
    return [{
      id: item.id,
      task_id: item.task_id,
      field: item.field,
      base: item.base,
      current: item.current,
      proposed: item.proposed,
      status: typeof item.status === 'string' ? item.status : undefined,
    }];
  });
}

function conflictsFromError(error: ApiError): TaskConflict[] {
  const details = error.details;
  if (!details || typeof details !== 'object' || !Array.isArray((details as { conflicts?: unknown }).conflicts)) return [];
  return normalizeConflicts((details as { conflicts: Array<Record<string, unknown>> }).conflicts);
}

function normalizeSnapshot(snapshot: WorkspaceSnapshot): WorkspaceSnapshot {
  return {
    ...snapshot,
    tasks: snapshot.tasks.map(parseTaskItem),
    comments: snapshot.comments ?? [],
    approval_requests: snapshot.approval_requests ?? [],
  };
}

function isPendingApproval(value: TaskWriteResult | TaskComment | PendingApproval | undefined): value is PendingApproval {
  return Boolean(value && typeof value === 'object' && 'pending' in value && value.pending === true && 'approval_request' in value);
}

function isTaskItem(value: TaskItem | TaskApprovalRequest | TaskComment): value is TaskItem {
  return 'title' in value && 'workspace_id' in value && 'field_versions' in value;
}

function isApprovalRequest(value: TaskItem | TaskApprovalRequest | TaskComment): value is TaskApprovalRequest {
  return 'request_type' in value && 'proposed_changes' in value;
}

function isTaskComment(value: TaskItem | TaskApprovalRequest | TaskComment): value is TaskComment {
  return 'author_user_id' in value && 'body' in value && 'deleted_at' in value;
}

function cursorFrom(value: { cursor?: number | null } | undefined): number {
  return typeof value?.cursor === 'number' ? value.cursor : 0;
}

function createRequestId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
