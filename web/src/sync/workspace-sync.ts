import { ApiError, type ApiClient, type TaskWriteResult } from '../api/client';
import type { ApprovalActionResult, PendingApproval, TaskApprovalRequest, TaskComment, TaskItem, WorkspaceChange, WorkspaceChanges, WorkspaceSnapshot } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';
import { isCanonicalTaskStatus, isTaskQuadrant, parseTaskItem, upsertTask } from '../tasks/task-model';

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

interface PendingPull {
  generation: number;
  cursorHint?: number;
  afterCursor?: number;
  isCurrent?: IsCurrent;
  retryAttempt: number;
  waiters: Array<() => void>;
}

interface PullResult {
  cursor: number;
  recovered: boolean;
  failed: boolean;
}

type RunOutcome = 'completed' | 'recovered' | 'failed' | 'cancelled';

const PULL_RETRY_DELAYS_MS = [1_000, 2_000, 5_000] as const;

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
  private snapshotRequestSequence = 0;
  private snapshotIdentity = 0;
  private activeTopLevelOperations = 0;
  private pendingPulls: PendingPull[] = [];
  private pullDrain: Promise<void> | undefined;
  private readonly pullRequests = new Set<PendingPull>();
  private unhintedPull: PendingPull | undefined;
  private pullRetryTimer: ReturnType<typeof globalThis.setTimeout> | undefined;
  private pullRetryRequests: PendingPull[] | undefined;

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
    this.activeTopLevelOperations = 0;
    this.resolvePulls();
    this.listeners.clear();
  }

  clear(): void {
    this.generation += 1;
    this.activeTopLevelOperations = 0;
    this.resolvePulls();
    this.currentState = INITIAL_STATE;
    for (const listener of this.listeners) listener(this.currentState);
  }

  async loadSnapshot(parentIsCurrent?: IsCurrent): Promise<void> {
    const sequence = ++this.snapshotRequestSequence;
    const snapshotIsCurrent = (): boolean => sequence === this.snapshotRequestSequence && (!parentIsCurrent || parentIsCurrent());
    await this.run('无法加载工作区，请检查网络后重试。', async (isCurrent) => {
      const snapshot = await this.api.getWorkspaceSnapshot();
      if (!isCurrent()) return;
      const normalized = normalizeSnapshot(snapshot);
      const activeSnapshot = this.currentState.snapshot;
      if (activeSnapshot && normalized.cursor < this.currentState.cursor) return;
      this.snapshotIdentity += 1;
      this.setState({ snapshot: normalized, cursor: normalized.cursor, approvals: normalized.approval_requests, comments: normalized.comments, conflicts: normalizeConflicts(normalized.conflicts), stale: false, error: null, authRequired: false });
    }, false, snapshotIsCurrent);
  }

  async pull(cursorHint?: number): Promise<void> {
    if (this.disposed) return;
    if (cursorHint !== undefined && !isValidCursor(cursorHint)) return;
    if (this.currentState.snapshot && cursorHint !== undefined && cursorHint <= this.currentState.cursor) return;
    await this.enqueuePull(cursorHint);
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
    if (!isCanonicalTaskStatus(targetStatus)) {
      this.setState({ error: '无法更新任务状态，请检查网络后重试。' });
      return undefined;
    }
    return this.write('无法更新任务状态，请检查网络后重试。', () => this.api.transitionTask(taskId, { requestId: this.requestIdFactory(), targetStatus, baseStatusVersion: task.status_version, ...payload }));
  }

  async addComment(taskId: string, body: string): Promise<void> {
    const cursorBeforeWrite = this.currentState.cursor;
    await this.run('无法添加评论，请检查网络后重试。', async (isCurrent) => {
      const result = await this.api.addTaskComment(taskId, { requestId: this.requestIdFactory(), body });
      if (!isCurrent()) return;
      const cursor = result && typeof result.cursor === 'number' ? result.cursor : cursorBeforeWrite;
      if (cursor > cursorBeforeWrite) {
        if (!isCurrent()) return;
        await this.pullFrom(cursorBeforeWrite, isCurrent, cursor);
      }
    });
  }

  async addDelay(taskId: string, newDueAt: string, reason: string, note?: string): Promise<void> {
    const cursorBeforeWrite = this.currentState.cursor;
    await this.run('无法延期任务，请检查网络后重试。', async (isCurrent) => {
      const response = await this.api.addTaskDelay(taskId, { requestId: this.requestIdFactory(), newDueAt, reason, note });
      if (!isCurrent()) return;
      const cursor = cursorFrom(response as { cursor?: number | null });
      await this.pullFrom(cursorBeforeWrite, isCurrent, cursor > cursorBeforeWrite ? cursor : undefined);
    });
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
    await this.run('无法提交审批请求，请检查网络后重试。', async (isCurrent) => {
      const approval = await this.api.createApprovalRequest!({
        workspaceId: snapshot.workspace_id,
        requestId: this.requestIdFactory(),
        taskId,
        commentId: input.commentId,
        requestType: input.requestType,
        proposedChanges: input.proposedChanges,
        baseFieldVersions: input.baseFieldVersions,
      });
      if (!isCurrent()) return;
      created = normalizeApprovalResource(approval, snapshot.workspace_id);
      this.mergeApproval(created);
      const cursor = cursorFrom(approval);
      if (cursor > cursorBeforeWrite) {
        if (!isCurrent()) return;
        await this.pullFrom(cursorBeforeWrite, isCurrent, cursor);
      }
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
    await this.run('无法加载审批请求，请检查网络后重试。', async (isCurrent) => {
      const approvals = await this.api.listApprovalRequests!(snapshot.workspace_id, box);
      if (!isCurrent()) return;
      result = approvals.map((approval) => normalizeApprovalResource(approval, snapshot.workspace_id));
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
    await this.run('无法删除评论，请检查网络后重试。', async (isCurrent) => {
      const response = await this.api.deleteTaskComment!(taskId, commentId, { requestId: this.requestIdFactory(), baseVersion });
      if (!isCurrent()) return;
      result = response;
      if (isPendingApproval(response)) this.mergeApproval(response.approval_request);
      else this.mergeComment(response, cursorFrom(response), false, taskId);
      const cursor = cursorFrom(response);
      if (cursor > cursorBeforeWrite) {
        if (!isCurrent()) return;
        await this.pullFrom(cursorBeforeWrite, isCurrent, cursor);
      }
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
      if (!isCurrent()) return;
      result = response;
      if (isPendingApproval(response)) {
        this.mergeApproval(response.approval_request);
      } else {
        this.mergeTask(response, response.cursor, false);
      }
      onSuccess?.();
      if (response.cursor > cursorBeforeWrite) {
        if (!isCurrent()) return;
        await this.pullFrom(cursorBeforeWrite, isCurrent, response.cursor);
      }
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
    await this.run('无法处理审批请求，请检查网络后重试。', async (isCurrent) => {
      const input = { workspaceId: snapshot.workspace_id, requestId: this.requestIdFactory() };
      const response = action === 'approve'
        ? await this.api.approveApproval!(approvalId, input)
        : action === 'reject'
          ? await this.api.rejectApproval!(approvalId, { ...input, reason })
          : await this.api.cancelApproval!(approvalId, input);
      if (!isCurrent()) return;
      result = response;
      const cursor = cursorFrom(response);
      this.mergeApprovalResult(response, cursor <= cursorBeforeAction);
      if (cursor > cursorBeforeAction) {
        if (!isCurrent()) return;
        await this.pullFrom(cursorBeforeAction, isCurrent, cursor);
      }
    });
    return result;
  }

  private async pullFrom(afterCursor: number, parentIsCurrent?: IsCurrent, cursorHint?: number): Promise<void> {
    if (parentIsCurrent && !parentIsCurrent()) return;
    await this.enqueuePull(cursorHint, afterCursor, parentIsCurrent);
  }

  private async pullChanges(afterCursor: number, parentIsCurrent?: IsCurrent): Promise<PullResult | undefined> {
    const operationGeneration = this.generation;
    let appliedCursor: number | undefined;
    let recovered = false;
    const outcome = await this.run('同步失败，请检查网络后重试。', async (isCurrent) => {
      const changes = await this.api.getWorkspaceChanges(afterCursor);
      if (!isCurrent()) return;
      const activeSnapshot = this.currentState.snapshot;
      if (!activeSnapshot || !isValidChangesEnvelope(changes, afterCursor, activeSnapshot.workspace_id)) {
        if (!isCurrent()) return;
        recovered = true;
        await this.loadSnapshot(isCurrent);
        if (isCurrent()) appliedCursor = this.currentState.cursor;
        return;
      }
      for (const change of changes.changes) {
        if (!isCurrent()) return;
        this.applyChange(change);
      }
      if (!isCurrent()) return;
      const lastReturnedCursor = changes.changes.length === 0
        ? afterCursor
        : changes.changes[changes.changes.length - 1].cursor;
      const cursor = Math.max(this.currentState.cursor, lastReturnedCursor);
      const snapshot = this.currentState.snapshot;
      this.setState({ snapshot: snapshot ? { ...snapshot, cursor } : null, cursor, approvals: snapshot?.approval_requests, comments: snapshot?.comments, stale: false, error: null, authRequired: false });
      appliedCursor = cursor;
    }, true, parentIsCurrent);
    if (outcome === 'cancelled') return undefined;
    if (appliedCursor === undefined
      && !this.disposed
      && operationGeneration === this.generation
      && (!parentIsCurrent || parentIsCurrent())) {
      return { cursor: this.currentState.cursor, recovered, failed: outcome === 'failed' };
    }
    return appliedCursor === undefined ? undefined : { cursor: appliedCursor, recovered, failed: outcome === 'failed' };
  }

  private applyChange(change: WorkspaceChange): void {
    if (change.resource_type === 'task_conflict') {
      const action = change.action.toUpperCase();
      if (action === 'DELETED' || change.resource === null) {
        this.removeConflict(change.resource_id);
      } else if (isTaskConflict(change.resource, this.currentState.snapshot?.workspace_id)) {
        this.mergeConflict(change.resource, change.cursor, false);
      }
      return;
    }
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
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks: upsertTask(snapshot.tasks, normalizeTaskResource(task, snapshot.workspace_id)), cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApproval(approval: TaskApprovalRequest, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const normalizedApproval = normalizeApprovalResource(approval, snapshot.workspace_id);
    const approvals = [...(snapshot.approval_requests ?? [])]
      .filter((item) => item.id !== normalizedApproval.id);
    approvals.push(normalizedApproval);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, approval_requests: approvals, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApprovals(approvals: TaskApprovalRequest[]): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const merged = [...(snapshot.approval_requests ?? [])];
    for (const approval of approvals) {
      const normalizedApproval = normalizeApprovalResource(approval, snapshot.workspace_id);
      const index = merged.findIndex((item) => item.id === normalizedApproval.id);
      if (index === -1) merged.push(normalizedApproval);
      else merged[index] = normalizedApproval;
    }
    const nextSnapshot = { ...snapshot, approval_requests: merged };
    this.setState({ snapshot: nextSnapshot, approvals: merged, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeComment(comment: TaskComment, cursor = this.currentState.cursor, updateCursor = false, taskId?: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const normalizedComment = normalizeCommentResource(comment, taskId);
    const comments = [...(snapshot.comments ?? [])].filter((item) => item.id !== normalizedComment.id);
    comments.push(normalizedComment);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, comments, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, comments, approvals: nextSnapshot.approval_requests, stale: false, error: null, authRequired: false });
  }

  private mergeConflict(conflict: TaskConflict, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const normalized = normalizeConflicts([conflict])[0];
    if (!normalized) return;
    const conflicts = normalizeConflicts(snapshot.conflicts).filter((item) => item.id !== normalized.id);
    if (normalized.status === 'OPEN') conflicts.push(normalized);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, conflicts, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, conflicts, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeConflict(conflictId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const conflicts = normalizeConflicts(snapshot.conflicts).filter((item) => item.id !== conflictId);
    const nextSnapshot = { ...snapshot, conflicts };
    this.setState({ snapshot: nextSnapshot, conflicts: nextSnapshot.conflicts, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApprovalResult(result: ApprovalActionResult, updateCursor = true): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const approval = normalizeApprovalResource(result.approval_request, snapshot.workspace_id);
    const task = result.task ? normalizeTaskResource(result.task, snapshot.workspace_id) : undefined;
    const comment = result.comment ? normalizeCommentResource(result.comment, approval.task_id) : undefined;
    const approvals = [...(snapshot.approval_requests ?? [])].filter((item) => item.id !== approval.id);
    approvals.push(approval);
    const tasks = task ? upsertTask(snapshot.tasks, task) : snapshot.tasks;
    const comments = comment
      ? [...(snapshot.comments ?? [])].filter((item) => item.id !== comment.id).concat(comment)
      : snapshot.comments ?? [];
    const cursor = updateCursor && typeof result.cursor === 'number' && result.cursor > snapshot.cursor ? result.cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks, comments, approval_requests: approvals, cursor };
    this.setState({ snapshot: nextSnapshot, cursor, approvals, comments, stale: false, error: null, authRequired: false });
  }

  private async run(message: string, operation: (isCurrent: IsCurrent) => Promise<void>, nested = false, parentIsCurrent?: IsCurrent): Promise<RunOutcome> {
    const generation = this.generation;
    const isCurrent = () => !this.disposed && generation === this.generation && (!parentIsCurrent || parentIsCurrent());
    if (!isCurrent()) return 'cancelled';
    if (!nested) {
      this.activeTopLevelOperations += 1;
      this.setState({ loading: true, error: null });
    }
    try {
      await operation(isCurrent);
      return 'completed';
    } catch (error) {
      if (!isCurrent()) return 'cancelled';
      if (error instanceof ApiError && error.status === 410 && error.code === 'sync_cursor_expired') {
        await this.loadSnapshot(isCurrent);
        return isCurrent() ? 'recovered' : 'cancelled';
      }
      if (error instanceof ApiError && error.status === 409 && error.code === 'field_conflict') {
        const merged = await this.mergeConflictError(error, isCurrent);
        if (merged) {
          return 'failed';
        }
        await this.loadSnapshot(isCurrent);
        return 'failed';
      }
      this.setState({ error: message, stale: this.currentState.snapshot !== null, authRequired: error instanceof ApiError && error.status === 401 });
      return 'failed';
    } finally {
      if (!nested && generation === this.generation) {
        this.activeTopLevelOperations = Math.max(0, this.activeTopLevelOperations - 1);
        if (this.activeTopLevelOperations === 0) this.setState({ loading: false });
      }
    }
  }

  private setState(update: Partial<WorkspaceSyncState>): void {
    if (this.disposed) return;
    this.currentState = { ...this.currentState, ...update };
    for (const listener of this.listeners) listener(this.currentState);
  }

  private async mergeConflictError(error: ApiError, isCurrent: IsCurrent): Promise<boolean> {
    const snapshot = this.currentState.snapshot;
    const details = error.details;
    if (!snapshot || !isRecord(details)) return false;
    if (!isValidCursor(details.cursor)) return false;
    const rawConflicts = details.conflicts;
    if (!Array.isArray(rawConflicts) || rawConflicts.length === 0 || !rawConflicts.every(isRecord)) return false;
    const incoming = conflictsFromError(error);
    if (incoming.length !== rawConflicts.length) return false;
    const valid = rawConflicts.every((conflict) => isCompleteConflictProjection(conflict, snapshot.workspace_id));
    if (!valid) return false;
    const cursorBefore = this.currentState.cursor;
    const conflicts = normalizeConflicts(snapshot.conflicts)
      .filter((item) => !incoming.some((conflict) => conflict.id === item.id));
    for (const conflict of incoming) {
      const normalized = { ...conflict, status: conflict.status ?? 'OPEN' };
      if (normalized.status === 'OPEN') conflicts.push(normalized);
    }
    const tasks = [...snapshot.tasks];
    for (const conflict of incoming) {
      if (conflict.current_snapshot && isTaskItem(conflict.current_snapshot)) {
        const currentTask = normalizeTaskResource(conflict.current_snapshot, snapshot.workspace_id);
        const mergedTasks = upsertTask(tasks, currentTask);
        tasks.splice(0, tasks.length, ...mergedTasks);
      }
    }
    const nextSnapshot = { ...snapshot, tasks, conflicts };
    this.setState({ snapshot: nextSnapshot, conflicts, error: null, stale: false });
    const cursor = cursorFromConflictError(error);
    if (cursor > cursorBefore && isCurrent()) {
      await this.pullFrom(cursorBefore, isCurrent, cursor);
    }
    return true;
  }

  private async enqueuePull(cursorHint?: number, afterCursor?: number, isCurrent?: IsCurrent): Promise<void> {
    if (this.disposed || (isCurrent && !isCurrent())) return;
    await new Promise<void>((resolve) => {
      const canCoalesce = cursorHint === undefined && afterCursor === undefined && isCurrent === undefined;
      const existing = canCoalesce && this.unhintedPull?.generation === this.generation
        ? this.unhintedPull
        : undefined;
      if (existing) {
        existing.waiters.push(resolve);
        return;
      }
      const request: PendingPull = {
        generation: this.generation,
        cursorHint,
        afterCursor,
        isCurrent,
        retryAttempt: 0,
        waiters: [resolve],
      };
      this.pullRequests.add(request);
      if (canCoalesce) this.unhintedPull = request;
      this.pendingPulls.push(request);
      this.startPullDrain();
    });
  }

  private startPullDrain(): void {
    if (this.disposed || this.pullDrain || this.pullRetryTimer !== undefined || this.pendingPulls.length === 0) return;
    const generation = this.generation;
    let resolveDrain!: () => void;
    let rejectDrain!: (error: unknown) => void;
    const drain = new Promise<void>((resolve, reject) => {
      resolveDrain = resolve;
      rejectDrain = reject;
    });
    this.pullDrain = drain;
    void this.drainPulls(generation).then(resolveDrain, rejectDrain);
    void drain.then(
      () => this.finishPullDrain(drain, generation),
      () => this.finishPullDrain(drain, generation),
    );
  }

  private finishPullDrain(drain: Promise<void>, generation: number): void {
    if (this.pullDrain !== drain) return;
    this.pullDrain = undefined;
    if (!this.disposed
      && this.generation === generation
      && this.pullRetryTimer === undefined
      && this.pendingPulls.length > 0) this.startPullDrain();
  }

  private async drainPulls(generation: number): Promise<void> {
    while (!this.disposed
      && this.generation === generation
      && this.pullRetryTimer === undefined
      && this.pendingPulls.length > 0) {
      const batch = this.pendingPulls.splice(0);
      let retained: PendingPull[] = [];
      try {
        retained = await this.processPullBatch(batch, generation);
      } finally {
        const retainedRequests = new Set(retained);
        for (const request of batch) {
          if (!retainedRequests.has(request)) this.resolvePull(request);
        }
      }
    }
  }

  private async processPullBatch(batch: PendingPull[], generation: number): Promise<PendingPull[]> {
    const active = batch.filter((request) => request.generation === generation && (!request.isCurrent || request.isCurrent()));
    if (active.length === 0) return [];

    const batchIsCurrent = (): boolean => !this.disposed
      && this.generation === generation
      && active.some((request) => !request.isCurrent || request.isCurrent());
    const highestHint = active.reduce<number | undefined>((highest, request) => {
      if (request.cursorHint === undefined) return highest;
      return highest === undefined ? request.cursorHint : Math.max(highest, request.cursorHint);
    }, undefined);

    if (!this.currentState.snapshot) {
      await this.loadSnapshot(batchIsCurrent);
      if (!batchIsCurrent() || !this.currentState.snapshot) return [];
    }

    const pullSnapshotIdentity = this.snapshotIdentity;
    const isCurrent = (): boolean => batchIsCurrent() && this.snapshotIdentity === pullSnapshotIdentity;
    const currentCursor = this.currentState.cursor;
    const writeRequests = active.filter((request) => request.afterCursor !== undefined);
    const needsWritePull = writeRequests.length > 0;
    const needsHintPull = active.some((request) => request.afterCursor === undefined
      && (request.cursorHint === undefined || (highestHint !== undefined && highestHint > currentCursor)));
    if (!needsWritePull && !needsHintPull) return [];

    let afterCursor = needsWritePull
      ? Math.min(currentCursor, Math.min(...writeRequests.map((request) => request.afterCursor!)))
      : currentCursor;
    while (isCurrent()) {
      const beforeCursor = this.currentState.cursor;
      const result = await this.pullChanges(afterCursor, isCurrent);
      if (!isCurrent()) return [];
      if (!result || result.recovered) return [];
      if (result.failed) return this.schedulePullRetry(active, generation);
      if (highestHint === undefined || this.currentState.cursor >= highestHint) return [];
      if (this.currentState.cursor <= beforeCursor) return [];
      afterCursor = this.currentState.cursor;
    }
    return [];
  }

  private schedulePullRetry(requests: PendingPull[], generation: number): PendingPull[] {
    const nextAttempt = Math.max(...requests.map((request) => request.retryAttempt)) + 1;
    const delay = PULL_RETRY_DELAYS_MS[nextAttempt - 1];
    if (delay === undefined) return [];

    for (const request of requests) request.retryAttempt = nextAttempt;
    this.pullRetryRequests = requests;
    this.pullRetryTimer = globalThis.setTimeout(() => {
      const retryRequests = this.pullRetryRequests;
      this.pullRetryRequests = undefined;
      this.pullRetryTimer = undefined;
      if (!retryRequests) return;
      if (this.disposed || this.generation !== generation) {
        for (const request of retryRequests) this.resolvePull(request);
        return;
      }
      for (const request of retryRequests) {
        if (this.pullRequests.has(request)) this.pendingPulls.push(request);
      }
      this.startPullDrain();
    }, delay);
    return requests;
  }

  private resolvePull(request: PendingPull): void {
    if (!this.pullRequests.delete(request)) return;
    if (this.unhintedPull === request) this.unhintedPull = undefined;
    const waiters = request.waiters.splice(0);
    for (const resolve of waiters) resolve();
  }

  private resolvePulls(): void {
    if (this.pullRetryTimer !== undefined) globalThis.clearTimeout(this.pullRetryTimer);
    this.pullRetryTimer = undefined;
    this.pullRetryRequests = undefined;
    this.pendingPulls = [];
    this.pullDrain = undefined;
    this.unhintedPull = undefined;
    for (const request of Array.from(this.pullRequests)) this.resolvePull(request);
  }
}

function isValidChangesEnvelope(value: unknown, afterCursor: number, workspaceId: string): value is WorkspaceChanges {
  if (!isRecord(value)) return false;
  const envelope = value as { workspace_id?: unknown; cursor?: unknown; changes?: unknown };
  if (envelope.workspace_id !== workspaceId || !isValidCursor(envelope.cursor) || !Array.isArray(envelope.changes)) return false;
  if (!areContiguous(envelope.changes, afterCursor, workspaceId)) return false;
  const lastCursor = envelope.changes.length === 0
    ? afterCursor
    : envelope.changes[envelope.changes.length - 1].cursor;
  return envelope.cursor === lastCursor;
}

function areContiguous(changes: unknown[], afterCursor: number, workspaceId: string): changes is WorkspaceChange[] {
  return changes.every((value, index) => {
    if (!isRecord(value)) return false;
    const change = value as Partial<WorkspaceChange>;
    if (!isValidCursor(change.cursor)
      || change.cursor !== afterCursor + index + 1
      || typeof change.resource_type !== 'string'
      || change.resource_type.length === 0
      || typeof change.resource_id !== 'string'
      || change.resource_id.length === 0
      || !isChangeAction(change.action)
      || (change.operation_id !== null && typeof change.operation_id !== 'string')) return false;
    return isValidChangeResource(change.resource_type, change.resource, workspaceId)
      && (change.resource === null
        || !isRecord(change.resource)
        || !('id' in change.resource)
        || change.resource.id === change.resource_id);
  });
}

function isValidCursor(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function normalizeConflicts(value: Array<Record<string, unknown>>): TaskConflict[] {
  return value.flatMap((item) => {
    if (typeof item.id !== 'string' || typeof item.task_id !== 'string' || typeof item.field !== 'string') return [];
    return [{
      ...item,
      id: item.id,
      task_id: item.task_id,
      field: item.field,
      base: item.base ?? item.baseline,
      current: item.current,
      proposed: item.proposed ?? item.proposed_payload,
      status: typeof item.status === 'string' ? item.status : typeof item.state === 'string' ? item.state : undefined,
    }];
  });
}

function conflictsFromError(error: ApiError): TaskConflict[] {
  const details = error.details;
  if (!details || typeof details !== 'object' || !Array.isArray((details as { conflicts?: unknown }).conflicts)) return [];
  const raw = (details as { conflicts: unknown[] }).conflicts;
  if (!raw.every((item) => isRecord(item) && isTaskConflict(item, undefined, false))) return [];
  return normalizeConflicts(raw);
}

function normalizeSnapshot(value: unknown): WorkspaceSnapshot {
  if (!isRecord(value)) throw new Error('workspace snapshot is not an object');

  const workspaceId = value.workspace_id;
  const workspace = value.workspace;
  const members = value.members;
  const tasks = value.tasks;
  const conflicts = value.conflicts;
  const cursor = value.cursor;
  const comments = value.comments ?? [];
  const approvalRequests = value.approval_requests ?? [];

  if (typeof workspaceId !== 'string'
    || workspaceId.length === 0
    || !isRecord(workspace)
    || workspace.id !== workspaceId
    || !isNullableString(workspace.name)
    || typeof workspace.status !== 'string'
    || !isValidCursor(cursor)
    || !Array.isArray(members)
    || !members.every(isWorkspaceMember)
    || !Array.isArray(tasks)
    || !tasks.every((item) => isTaskItem(item) && item.workspace_id === workspaceId)
    || !Array.isArray(conflicts)
    || !conflicts.every((item) => isRecord(item) && conflictWorkspaceMatches(item, workspaceId))
    || !Array.isArray(comments)
    || !comments.every(isTaskComment)
    || !Array.isArray(approvalRequests)
    || !approvalRequests.every((item) => isApprovalRequest(item) && item.workspace_id === workspaceId)) {
    throw new Error('workspace snapshot is invalid');
  }

  const viewerUserId = value.viewer_user_id;
  if (viewerUserId !== undefined && !isNullableString(viewerUserId)) {
    throw new Error('workspace snapshot viewer is invalid');
  }

  return {
    ...value,
    workspace_id: workspaceId,
    workspace: {
      id: workspaceId,
      name: workspace.name,
      status: workspace.status,
    },
    members,
    tasks: tasks.map(parseTaskItem),
    conflicts,
    cursor,
    viewer_user_id: viewerUserId === undefined ? null : viewerUserId,
    comments,
    approval_requests: approvalRequests,
  };
}

function normalizeTaskResource(value: unknown, workspaceId: string): TaskItem {
  if (!isRecord(value)) throw new Error('task response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isTaskItem(candidate) || candidate.workspace_id !== workspaceId) {
    throw new Error('task response belongs to another workspace');
  }
  return parseTaskItem(candidate);
}

function normalizeApprovalResource(value: unknown, workspaceId: string): TaskApprovalRequest {
  if (!isRecord(value)) throw new Error('approval response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isApprovalRequest(candidate) || candidate.workspace_id !== workspaceId) {
    throw new Error('approval response belongs to another workspace');
  }
  return candidate;
}

function normalizeCommentResource(value: unknown, taskId?: string): TaskComment {
  if (!isRecord(value)) throw new Error('comment response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isTaskComment(candidate) || (taskId !== undefined && candidate.task_id !== taskId)) {
    throw new Error('comment response belongs to another task');
  }
  return candidate;
}

function isPendingApproval(value: TaskWriteResult | TaskComment | PendingApproval | undefined): value is PendingApproval {
  return Boolean(value && typeof value === 'object' && 'pending' in value && value.pending === true && 'approval_request' in value);
}

function isTaskItem(value: unknown): value is TaskItem {
  if (!isRecord(value)
    || typeof value.id !== 'string'
    || value.id.length === 0
    || typeof value.workspace_id !== 'string'
    || value.workspace_id.length === 0
    || typeof value.title !== 'string'
    || typeof value.description !== 'string'
    || !isNullableString(value.parent_task_id)
    || !isNullableString(value.due_at)
    || !isTaskStatus(value.status)
    || typeof value.current_handler_id !== 'string'
    || !isNullableString(value.blocked_reason)
    || !isNullableString(value.blocked_since)
    || !isNullableString(value.resume_handler_id)
    || !isNullableString(value.waiting_for_user_id)
    || !isOptionalNullableString(value.reviewer_user_id)
    || !isOptionalNullableString(value.review_submitted_at)
    || !isOptionalNullableString(value.reviewed_at)
    || !isOptionalNullableString(value.review_rejection_reason)
    || !isNullableString(value.planned_start_at)
    || !isNullableNumber(value.estimated_minutes)
    || !isNullableString(value.completed_at)
    || typeof value.created_by !== 'string'
    || typeof value.created_at !== 'string'
    || typeof value.updated_at !== 'string'
    || !isNonNegativeSafeInteger(value.delay_count)
    || !isNonNegativeSafeInteger(value.total_delay_minutes)
    || !isPositiveSafeInteger(value.version)
    || !isPositiveSafeInteger(value.status_version)
    || !isNumberRecord(value.field_versions)
    || !isPositiveSafeInteger(value.lifecycle_version)
    || !isNullableString(value.deleted_at)
    || !isTaskQuadrant(value.quadrant)
    || (value.labels !== undefined && !Array.isArray(value.labels))
    || (value.task_number !== undefined && value.task_number !== null && typeof value.task_number !== 'string')
    || (value.progress !== undefined && !isNullableNumber(value.progress))) return false;
  try {
    parseTaskItem(value);
    return true;
  } catch {
    return false;
  }
}

function isApprovalRequest(value: unknown): value is TaskApprovalRequest {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && typeof value.task_id === 'string'
    && value.task_id.length > 0
    && isNullableString(value.comment_id)
    && typeof value.requester_id === 'string'
    && value.requester_id.length > 0
    && typeof value.approver_id === 'string'
    && value.approver_id.length > 0
    && isApprovalRequestType(value.request_type)
    && isRecord(value.proposed_changes)
    && isNumberRecord(value.base_field_versions)
    && typeof value.request_id === 'string'
    && value.request_id.length > 0
    && isApprovalRequestStatus(value.status)
    && typeof value.created_at === 'string'
    && isNullableString(value.reviewed_at)
    && isNullableString(value.reviewed_by)
    && isNullableString(value.rejection_reason)
    && (value.resolved_cursor === null || isValidCursor(value.resolved_cursor));
}

function isTaskComment(value: unknown): value is TaskComment {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.task_id === 'string'
    && value.task_id.length > 0
    && typeof value.author_user_id === 'string'
    && value.author_user_id.length > 0
    && typeof value.body === 'string'
    && isPositiveSafeInteger(value.version)
    && isNullableString(value.deleted_at)
    && isNullableString(value.deleted_by)
    && (value.created_at === null || typeof value.created_at === 'string');
}

function isWorkspaceMember(value: unknown): value is WorkspaceSnapshot['members'][number] {
  if (!isRecord(value)
    || typeof value.user_id !== 'string'
    || value.user_id.length === 0
    || !isPositiveSafeInteger(value.member_slot)) return false;
  return (value.membership_status === undefined || typeof value.membership_status === 'string')
    && (value.status === undefined || typeof value.status === 'string');
}

function isValidChangeResource(resourceType: string, resource: unknown, workspaceId: string): boolean {
  // A null resource is only meaningful for action-first conflict tombstones.
  if (resource === null) return resourceType === 'task_conflict';
  if (!isRecord(resource)) return false;
  if (resourceType === 'task') return isTaskItem(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'task_conflict') {
    return isTaskConflict(resource, workspaceId) && resource.workspace_id === workspaceId;
  }
  if (resourceType === 'approval_request') return isApprovalRequest(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'comment') return isTaskComment(resource);
  return false;
}

function isTaskConflict(value: unknown, workspaceId?: string, requireStatus = true): value is TaskConflict {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.task_id === 'string'
    && value.task_id.length > 0
    && typeof value.field === 'string'
    && value.field.length > 0
    && (workspaceId === undefined || conflictWorkspaceMatches(value, workspaceId))
    && (!requireStatus || isConflictStatus(value.status ?? value.state));
}

function isConflictStatus(value: unknown): value is 'OPEN' | 'RESOLVED' | 'REJECTED' {
  return value === 'OPEN' || value === 'RESOLVED' || value === 'REJECTED';
}

function conflictWorkspaceMatches(value: Record<string, unknown>, workspaceId: string): boolean {
  if (value.workspace_id !== undefined && value.workspace_id !== workspaceId) return false;
  const currentSnapshot = value.current_snapshot;
  if (currentSnapshot === undefined || currentSnapshot === null) return true;
  if (!isRecord(currentSnapshot)) return false;
  if (currentSnapshot.workspace_id !== undefined && currentSnapshot.workspace_id !== workspaceId) return false;
  return currentSnapshot.id === undefined || currentSnapshot.id === value.task_id;
}

function isCompleteConflictProjection(value: unknown, workspaceId: string): boolean {
  if (!isTaskConflict(value, workspaceId) || value.workspace_id !== workspaceId || value.status !== 'OPEN') return false;
  const currentSnapshot = value.current_snapshot;
  return isTaskItem(currentSnapshot)
    && currentSnapshot.workspace_id === workspaceId
    && isCanonicalTaskStatus(currentSnapshot.status)
    && currentSnapshot.id === value.task_id;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === 'object' && !Array.isArray(value));
}

function isNumberRecord(value: unknown): value is Record<string, number> {
  return isRecord(value) && Object.values(value).every((item) => isPositiveSafeInteger(item));
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

function isOptionalNullableString(value: unknown): value is string | null | undefined {
  return value === undefined || isNullableString(value);
}

function isNullableNumber(value: unknown): value is number | null {
  return value === null || (typeof value === 'number' && Number.isFinite(value));
}

function isSafeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value);
}

function isNonNegativeSafeInteger(value: unknown): value is number {
  return isSafeInteger(value) && value >= 0;
}

function isPositiveSafeInteger(value: unknown): value is number {
  return isSafeInteger(value) && value > 0;
}

function isChangeAction(value: unknown): value is 'CREATED' | 'UPDATED' | 'DELETED' | 'RESTORED' {
  return value === 'CREATED' || value === 'UPDATED' || value === 'DELETED' || value === 'RESTORED';
}

function isTaskStatus(value: unknown): value is TaskItem['status'] {
  return isCanonicalTaskStatus(value) || value === 'WAITING' || value === 'COMPLETED';
}

function isApprovalRequestType(value: unknown): value is TaskApprovalRequest['request_type'] {
  return value === 'TASK_UPDATE'
    || value === 'QUADRANT_UPDATE'
    || value === 'STATUS_UPDATE'
    || value === 'TASK_DELETE'
    || value === 'TASK_RESTORE'
    || value === 'COMMENT_DELETE'
    || value === 'HANDLER_TRANSFER';
}

function isApprovalRequestStatus(value: unknown): value is TaskApprovalRequest['status'] {
  return value === 'PENDING' || value === 'APPROVED' || value === 'REJECTED' || value === 'CONFLICTED' || value === 'CANCELLED';
}

function cursorFrom(value: { cursor?: number | null } | undefined): number {
  return typeof value?.cursor === 'number' ? value.cursor : 0;
}

function cursorFromConflictError(error: ApiError): number {
  const details = error.details;
  if (!isRecord(details) || !isValidCursor(details.cursor)) return 0;
  return details.cursor;
}

function createRequestId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
