import { ApiError, type ApiClient, type TaskWriteResult } from '../api/client';
import type { ApprovalActionResult, PendingApproval, TaskApprovalRequest, TaskComment, TaskItem, WorkspaceChange, WorkspaceChanges, WorkspaceSnapshot } from '../api/types';
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

interface PendingPull {
  generation: number;
  cursorHint?: number;
  afterCursor?: number;
  isCurrent?: IsCurrent;
  waiters: Array<() => void>;
}

interface PullResult {
  cursor: number;
  recovered: boolean;
}

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
  private activeTopLevelOperations = 0;
  private pendingPulls: PendingPull[] = [];
  private pullDrain: Promise<void> | undefined;
  private readonly pullRequests = new Set<PendingPull>();
  private unhintedPull: PendingPull | undefined;

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
      created = approval;
      this.mergeApproval(approval);
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
      result = approvals;
      this.mergeApprovals(approvals);
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
      else this.mergeComment(response);
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
    await this.run('同步失败，请检查网络后重试。', async (isCurrent) => {
      const changes = await this.api.getWorkspaceChanges(afterCursor);
      if (!isCurrent()) return;
      if (!isValidChangesEnvelope(changes, afterCursor)) {
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
    if (appliedCursor === undefined
      && !this.disposed
      && operationGeneration === this.generation
      && (!parentIsCurrent || parentIsCurrent())) {
      return { cursor: this.currentState.cursor, recovered };
    }
    return appliedCursor === undefined ? undefined : { cursor: appliedCursor, recovered };
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
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks: upsertTask(snapshot.tasks, parseTaskItem(task)), cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeApproval(approval: TaskApprovalRequest, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const approvals = [...(snapshot.approval_requests ?? [])]
      .filter((item) => item.id !== approval.id);
    approvals.push(approval);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, approval_requests: approvals, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
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
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, comments, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, comments, approvals: nextSnapshot.approval_requests, stale: false, error: null, authRequired: false });
  }

  private mergeApprovalResult(result: ApprovalActionResult, updateCursor = true): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const approvals = [...(snapshot.approval_requests ?? [])].filter((item) => item.id !== result.approval_request.id);
    approvals.push(result.approval_request);
    const tasks = result.task ? upsertTask(snapshot.tasks, parseTaskItem(result.task)) : snapshot.tasks;
    const comments = result.comment
      ? [...(snapshot.comments ?? [])].filter((item) => item.id !== result.comment!.id).concat(result.comment)
      : snapshot.comments ?? [];
    const cursor = updateCursor && typeof result.cursor === 'number' && result.cursor > snapshot.cursor ? result.cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks, comments, approval_requests: approvals, cursor };
    this.setState({ snapshot: nextSnapshot, cursor, approvals, comments, stale: false, error: null, authRequired: false });
  }

  private async run(message: string, operation: (isCurrent: IsCurrent) => Promise<void>, nested = false, parentIsCurrent?: IsCurrent): Promise<void> {
    const generation = this.generation;
    const isCurrent = () => !this.disposed && generation === this.generation && (!parentIsCurrent || parentIsCurrent());
    if (!isCurrent()) return;
    if (!nested) {
      this.activeTopLevelOperations += 1;
      this.setState({ loading: true, error: null });
    }
    try {
      await operation(isCurrent);
    } catch (error) {
      if (!isCurrent()) return;
      if (error instanceof ApiError && error.status === 410 && error.code === 'sync_cursor_expired') {
        if (!isCurrent()) return;
        await this.loadSnapshot(isCurrent);
        return;
      }
      if (error instanceof ApiError && error.status === 409 && error.code === 'field_conflict') {
        this.setState({ conflicts: conflictsFromError(error), error: null, stale: false });
        return;
      }
      this.setState({ error: message, stale: this.currentState.snapshot !== null, authRequired: error instanceof ApiError && error.status === 401 });
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
        waiters: [resolve],
      };
      this.pullRequests.add(request);
      if (canCoalesce) this.unhintedPull = request;
      this.pendingPulls.push(request);
      this.startPullDrain();
    });
  }

  private startPullDrain(): void {
    if (this.disposed || this.pullDrain || this.pendingPulls.length === 0) return;
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
    if (!this.disposed && this.generation === generation && this.pendingPulls.length > 0) this.startPullDrain();
  }

  private async drainPulls(generation: number): Promise<void> {
    while (!this.disposed && this.generation === generation && this.pendingPulls.length > 0) {
      const batch = this.pendingPulls.splice(0);
      try {
        await this.processPullBatch(batch, generation);
      } finally {
        for (const request of batch) this.resolvePull(request);
      }
    }
  }

  private async processPullBatch(batch: PendingPull[], generation: number): Promise<void> {
    const active = batch.filter((request) => request.generation === generation && (!request.isCurrent || request.isCurrent()));
    if (active.length === 0) return;

    const isCurrent = (): boolean => !this.disposed
      && this.generation === generation
      && active.some((request) => !request.isCurrent || request.isCurrent());
    const highestHint = active.reduce<number | undefined>((highest, request) => {
      if (request.cursorHint === undefined) return highest;
      return highest === undefined ? request.cursorHint : Math.max(highest, request.cursorHint);
    }, undefined);

    if (!this.currentState.snapshot) {
      await this.loadSnapshot(isCurrent);
      if (!isCurrent() || !this.currentState.snapshot) return;
    }

    const currentCursor = this.currentState.cursor;
    const writeRequests = active.filter((request) => request.afterCursor !== undefined);
    const needsWritePull = writeRequests.length > 0;
    const needsHintPull = active.some((request) => request.afterCursor === undefined
      && (request.cursorHint === undefined || (highestHint !== undefined && highestHint > currentCursor)));
    if (!needsWritePull && !needsHintPull) return;

    let afterCursor = needsWritePull
      ? Math.min(currentCursor, Math.min(...writeRequests.map((request) => request.afterCursor!)))
      : currentCursor;
    while (isCurrent()) {
      const beforeCursor = this.currentState.cursor;
      const result = await this.pullChanges(afterCursor, isCurrent);
      if (!isCurrent()) return;
      if (!result || result.recovered) return;
      if (highestHint === undefined || this.currentState.cursor >= highestHint) return;
      if (this.currentState.cursor <= beforeCursor) return;
      afterCursor = this.currentState.cursor;
    }
  }

  private resolvePull(request: PendingPull): void {
    if (!this.pullRequests.delete(request)) return;
    if (this.unhintedPull === request) this.unhintedPull = undefined;
    const waiters = request.waiters.splice(0);
    for (const resolve of waiters) resolve();
  }

  private resolvePulls(): void {
    this.pendingPulls = [];
    this.pullDrain = undefined;
    this.unhintedPull = undefined;
    for (const request of Array.from(this.pullRequests)) this.resolvePull(request);
  }
}

function isValidChangesEnvelope(value: unknown, afterCursor: number): value is WorkspaceChanges {
  if (!value || typeof value !== 'object') return false;
  const envelope = value as { cursor?: unknown; changes?: unknown };
  if (!isValidCursor(envelope.cursor) || !Array.isArray(envelope.changes)) return false;
  if (!areContiguous(envelope.changes, afterCursor)) return false;
  const lastCursor = envelope.changes.length === 0
    ? afterCursor
    : envelope.changes[envelope.changes.length - 1].cursor;
  return envelope.cursor === lastCursor;
}

function areContiguous(changes: unknown[], afterCursor: number): changes is WorkspaceChange[] {
  return changes.every((value, index) => {
    if (!value || typeof value !== 'object') return false;
    const change = value as Partial<WorkspaceChange>;
    return isValidCursor(change.cursor)
      && change.cursor === afterCursor + index + 1
      && (change.resource === null || (typeof change.resource === 'object' && change.resource !== null));
  });
}

function isValidCursor(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
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
