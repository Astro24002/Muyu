import { ApiError, type ApiClient, type TaskWriteResult } from '../api/client';
import type { Anniversary, ApprovalActionResult, Habit, HabitCheckin, HomeApprovalItem, HomeApprovalSection, HomeEntries, HomeEntryCounts, HomeMoment, HomeResponse, HomeTaskSection, HomeWeek, LedgerEntry, PendingApproval, TaskApprovalRequest, TaskComment, TaskItem, WorkspaceChange, WorkspaceChanges, WorkspaceClassification, WorkspaceSnapshot } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';
import { classificationNames as approvedClassificationNames } from '../tasks/classification';
import { isCanonicalTaskStatus, isTaskQuadrant, isTaskTransitionAllowed, normalizeTaskStatus, parseTaskItem, parseTaskLabels, upsertTask } from '../tasks/task-model';

export interface WorkspaceSyncState {
  snapshot: WorkspaceSnapshot | null;
  cursor: number;
  loading: boolean;
  stale: boolean;
  error: string | null;
  conflicts: TaskConflict[];
  authRequired: boolean;
  /** Server-authoritative today projection, when the API version provides it. */
  home?: HomeResponse;
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
  | 'createTaskInvitation'
  | 'patchTask'
  | 'resolveConflict'
  | 'transitionTask'
  | 'addTaskComment'
  | 'addTaskDelay'
> & Partial<Pick<ApiClient,
  | 'getHome'
  | 'requestAgreementUpdate'
  | 'requestTaskCancellation'
  | 'createApprovalRequest'
  | 'listApprovalRequests'
  | 'approveApproval'
  | 'rejectApproval'
  | 'cancelApproval'
  | 'deleteTaskComment'
  | 'createWorkspaceClassification'
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
    let loaded = false;
    const outcome = await this.run('无法加载工作区，请检查网络后重试。', async (isCurrent) => {
      const snapshot = await this.api.getWorkspaceSnapshot();
      if (!isCurrent()) return;
      const normalized = normalizeSnapshot(snapshot);
      const activeSnapshot = this.currentState.snapshot;
      if (activeSnapshot && normalized.cursor < this.currentState.cursor) return;
      const previousHome = activeSnapshot?.workspace_id === normalized.workspace_id
        ? this.currentState.home
        : undefined;
      this.snapshotIdentity += 1;
      this.setState({ snapshot: normalized, cursor: normalized.cursor, approvals: normalized.approval_requests, comments: normalized.comments, conflicts: normalizeConflicts(normalized.conflicts), home: previousHome, stale: false, error: null, authRequired: false });
      loaded = true;
    }, false, snapshotIsCurrent);
    if (outcome === 'completed' && loaded && snapshotIsCurrent()) await this.loadHome(snapshotIsCurrent);
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

  private async loadHome(parentIsCurrent?: IsCurrent): Promise<void> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || !this.api.getHome) {
      return;
    }
    const generation = this.generation;
    const isCurrent = (): boolean => !this.disposed
      && generation === this.generation
      && this.currentState.snapshot?.workspace_id === snapshot.workspace_id
      && (!parentIsCurrent || parentIsCurrent());
    try {
      const home = await this.api.getHome();
      if (!isCurrent()) return;
      this.setState({
        home: normalizeHomeResponse(
          home,
          snapshot.workspace_id,
          snapshot.classifications,
        ),
      });
    } catch (error) {
      if (!isCurrent()) return;
      this.setState({
        // Keep the last-known-good projection while the task snapshot remains
        // usable. A failed derived read must not turn a populated page empty.
        stale: true,
        error: '无法加载首页，请检查网络后重试。',
        ...(error instanceof ApiError && error.status === 401 ? { authRequired: true } : {}),
      });
    }
  }

  async createTask(title: string, description: string, quadrant: TaskItem['quadrant'], labels: string[] = [], nextStepText?: string, targetHandlerId?: string, acceptanceCriteria?: string): Promise<void> {
    const normalizedNextStepText = nextStepText === undefined ? undefined : nextStepText.trim();
    if (nextStepText !== undefined && (!normalizedNextStepText || Array.from(normalizedNextStepText).length > 90)) {
      this.setState({ error: '明确下一步不能为空且不能超过 90 个字符。' });
      return;
    }
    const normalizedCriteria = acceptanceCriteria?.trim();
    if (acceptanceCriteria !== undefined && (!normalizedCriteria || Array.from(normalizedCriteria).length > 500)) {
      this.setState({ error: '完成标准不能为空且不能超过 500 个字符。' });
      return;
    }
    const classifications = this.currentState.snapshot?.classifications ?? [];
    const available = approvedClassificationNames(classifications);
    if (!Array.isArray(labels) || labels.length !== 1 || typeof labels[0] !== 'string' || labels[0].trim().length === 0) {
      this.setState({ error: '任务必须选择一个已批准分类。' });
      return;
    }
    const classification = labels[0].trim();
    if (available.length === 0 || !available.some((name) => name.toLocaleLowerCase() === classification.toLocaleLowerCase())) {
      this.setState({ error: '任务只能选择已批准分类。' });
      return;
    }
    const approvedName = available.find((name) => name.toLocaleLowerCase() === classification.toLocaleLowerCase())!;
    const requestId = this.requestIdFactory();
    if (targetHandlerId !== undefined) {
      if (!normalizedNextStepText || !normalizedCriteria) {
        this.setState({ error: '邀请 TA 必须填写明确下一步和完成标准。' });
        return;
      }
      await this.write('无法发送任务邀请，请检查网络后重试。', () => this.api.createTaskInvitation({
        requestId,
        title,
        description,
        quadrant,
        labels: [approvedName],
        nextStepText: normalizedNextStepText,
        acceptanceCriteria: normalizedCriteria,
        targetHandlerId,
      }));
      return;
    }
    await this.write('无法创建任务，请检查网络后重试。', () => this.api.createTask({
      requestId,
      title,
      description,
      quadrant,
      labels: [approvedName],
      ...(normalizedNextStepText === undefined ? {} : { nextStepText: normalizedNextStepText }),
      ...(normalizedCriteria === undefined ? {} : { acceptanceCriteria: normalizedCriteria }),
    }));
  }

  async createClassification(name: string): Promise<PendingApproval | undefined> {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || !this.api.createWorkspaceClassification) return undefined;
    const normalized = name.trim();
    if (!normalized || Array.from(normalized).length > 5) {
      this.setState({ error: '分类名称不能为空且不能超过 5 个字符。' });
      return undefined;
    }
    const names = classificationNames(snapshot.classifications ?? []);
    if (names.has(normalized.toLocaleLowerCase())) {
      this.setState({ error: '该分类已存在。' });
      return undefined;
    }
    let result: PendingApproval | undefined;
    await this.run('无法提交分类审批，请检查网络后重试。', async (isCurrent) => {
      const response = await this.api.createWorkspaceClassification!({ requestId: this.requestIdFactory(), name: normalized });
      if (!isCurrent()) return;
      if (!isPendingApproval(response)) throw new Error('分类审批响应无效。');
      result = response;
      this.mergeApproval(response.approval_request);
    });
    return result;
  }

  async patchTask(taskId: string, changes: EditableTaskChanges): Promise<TaskWriteResult | undefined> {
    const task = this.currentState.snapshot?.tasks.find((item) => item.id === taskId);
    if (!task) {
      this.setState({ error: '任务不存在，请刷新后重试。' });
      return undefined;
    }
    const normalizedChanges: EditableTaskChanges = { ...changes };
    if (Object.prototype.hasOwnProperty.call(changes, 'next_step_text')) {
      const value: unknown = changes.next_step_text;
      if (typeof value !== 'string' || !value.trim() || Array.from(value.trim()).length > 90) {
        this.setState({ error: '明确下一步不能为空且不能超过 90 个字符。' });
        return undefined;
      }
      normalizedChanges.next_step_text = value.trim();
    }
    if (Object.prototype.hasOwnProperty.call(changes, 'labels')) {
      const value: unknown = changes.labels;
      if (!Array.isArray(value) || value.length !== 1 || typeof value[0] !== 'string' || value[0].trim().length === 0) {
        this.setState({ error: '任务必须选择一个已批准分类。' });
        return undefined;
      }
      const available = approvedClassificationNames(this.currentState.snapshot?.classifications ?? []);
      const requested = value[0].trim();
      const approvedName = available.find((name) => name.toLocaleLowerCase() === requested.toLocaleLowerCase());
      if (!approvedName) {
        this.setState({ error: '任务只能选择已批准分类。' });
        return undefined;
      }
      normalizedChanges.labels = [approvedName];
    }
    const fields = Object.keys(normalizedChanges);
    const baseFieldVersions = Object.fromEntries(fields.map((field) => [field, task.field_versions[field] ?? 1]));
    return this.write('无法更新任务，请检查网络后重试。', () => this.api.patchTask(taskId, {
      requestId: this.requestIdFactory(),
      changes: normalizedChanges,
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

  async transitionTask(taskId: string, targetStatus: string, payload: { blockedReason?: string; resumeHandlerId?: string; waitingForUserId?: string; reviewRejectionReason?: string; reviewContent?: string } = {}): Promise<TaskWriteResult | undefined> {
    const snapshot = this.currentState.snapshot;
    const task = snapshot?.tasks.find((item) => item.id === taskId);
    if (!task) {
      this.setState({ error: '任务不存在，请刷新后重试。' });
      return undefined;
    }
    if (!isCanonicalTaskStatus(targetStatus)) {
      this.setState({ error: '无法更新任务状态，请检查网络后重试。' });
      return undefined;
    }
    if (!isTaskTransitionAllowed(task, targetStatus, snapshot?.viewer_user_id)) {
      this.setState({ error: '当前用户不能执行该状态操作。' });
      return undefined;
    }
    const isReviewSubmission = normalizeTaskStatus(task.status) === 'IN_PROGRESS' && targetStatus === 'REVIEW';
    const isReviewReturn = normalizeTaskStatus(task.status) === 'REVIEW' && targetStatus === 'IN_PROGRESS';
    const reviewContent = payload.reviewContent?.trim();
    const reviewRejectionReason = payload.reviewRejectionReason?.trim();
    if (isReviewSubmission && !reviewContent) {
      this.setState({ error: '提交验收任务需要填写验收说明。' });
      return undefined;
    }
    if (isReviewReturn && !reviewRejectionReason) {
      this.setState({ error: '退回待验收任务需要填写退回原因。' });
      return undefined;
    }
    const { reviewContent: _reviewContent, reviewRejectionReason: _reviewRejectionReason, ...otherPayload } = payload;
    return this.write('无法更新任务状态，请检查网络后重试。', () => this.api.transitionTask(taskId, {
      requestId: this.requestIdFactory(),
      targetStatus,
      baseStatusVersion: task.status_version,
      ...otherPayload,
      ...(isReviewSubmission ? { reviewContent } : {}),
      ...(isReviewReturn ? { reviewRejectionReason } : {}),
    }));
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
    let proposedChanges: Record<string, unknown>;
    try {
      proposedChanges = normalizeApprovalChanges(
        input.proposedChanges,
        snapshot.classifications ?? [],
      );
    } catch (error) {
      this.setState({
        error: error instanceof Error ? error.message : '审批内容无效。',
      });
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
        proposedChanges,
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

  async requestAgreementUpdate(taskId: string, acceptanceCriteria: string): Promise<PendingApproval | undefined> {
    const snapshot = this.currentState.snapshot;
    const task = snapshot?.tasks.find((item) => item.id === taskId);
    if (!snapshot || !task) return undefined;
    const criteria = acceptanceCriteria.trim();
    if (!criteria || Array.from(criteria).length > 500) {
      this.setState({ error: '完成标准不能为空且不能超过 500 个字符。' });
      return undefined;
    }
    const cursorBeforeWrite = this.currentState.cursor;
    let result: PendingApproval | undefined;
    await this.run('无法提交约定修改，请检查网络后重试。', async (isCurrent) => {
      const requestId = this.requestIdFactory();
      const response = this.api.requestAgreementUpdate
        ? await this.api.requestAgreementUpdate(taskId, {
          requestId,
          acceptanceCriteria: criteria,
          baseFieldVersion: task.field_versions.acceptance_criteria ?? 1,
        })
        : this.api.createApprovalRequest
          ? {
            pending: true as const,
            approval_request: await this.api.createApprovalRequest({
              workspaceId: snapshot.workspace_id,
              requestId,
              taskId,
              requestType: 'TASK_UPDATE',
              proposedChanges: { acceptance_criteria: criteria, agreement_update: true },
              baseFieldVersions: { acceptance_criteria: task.field_versions.acceptance_criteria ?? 1 },
            }),
            cursor: 0,
          }
          : undefined;
      if (!response || !isCurrent()) return;
      const approval = normalizeApprovalResource(response.approval_request, snapshot.workspace_id);
      result = { ...response, approval_request: approval };
      this.mergeApproval(approval);
      const cursor = cursorFrom(response);
      if (cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite, isCurrent, cursor);
    });
    return result;
  }

  async requestTaskCancellation(taskId: string, reason: string): Promise<PendingApproval | undefined> {
    const snapshot = this.currentState.snapshot;
    const task = snapshot?.tasks.find((item) => item.id === taskId);
    if (!snapshot || !task) return undefined;
    const normalizedReason = reason.trim();
    if (!normalizedReason || Array.from(normalizedReason).length > 2000) {
      this.setState({ error: '取消原因不能为空且不能超过 2000 个字符。' });
      return undefined;
    }
    const cursorBeforeWrite = this.currentState.cursor;
    let result: PendingApproval | undefined;
    await this.run('无法提交取消申请，请检查网络后重试。', async (isCurrent) => {
      const requestId = this.requestIdFactory();
      const response = this.api.requestTaskCancellation
        ? await this.api.requestTaskCancellation(taskId, {
          requestId,
          reason: normalizedReason,
          baseLifecycleVersion: task.lifecycle_version,
        })
        : this.api.createApprovalRequest
          ? {
            pending: true as const,
            approval_request: await this.api.createApprovalRequest({
              workspaceId: snapshot.workspace_id,
              requestId,
              taskId,
              requestType: 'TASK_DELETE',
              proposedChanges: { cancellation_request: true, cancel_reason: normalizedReason },
              baseFieldVersions: { lifecycle_version: task.lifecycle_version },
            }),
            cursor: 0,
          }
          : undefined;
      if (!response || !isCurrent()) return;
      const approval = normalizeApprovalResource(response.approval_request, snapshot.workspace_id);
      result = { ...response, approval_request: approval };
      this.mergeApproval(approval);
      const cursor = cursorFrom(response);
      if (cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite, isCurrent, cursor);
    });
    return result;
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
    let appliedChanges = false;
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
      appliedChanges = changes.changes.length > 0;
      try {
        for (const change of changes.changes) {
          if (!isCurrent()) return;
          this.applyChange(change);
        }
      } catch {
        if (!isCurrent()) return;
        recovered = true;
        await this.loadSnapshot(isCurrent);
        if (isCurrent()) appliedCursor = this.currentState.cursor;
        return;
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
    if (outcome === 'completed'
      && appliedChanges
      && appliedCursor !== undefined
      && !this.disposed
      && operationGeneration === this.generation
      && (!parentIsCurrent || parentIsCurrent())) {
      await this.loadHome(parentIsCurrent);
    }
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
    if (!change.resource) {
      if (change.action.toUpperCase() === 'DELETED') {
        if (change.resource_type === 'ledger_entry') this.removeLedgerEntry(change.resource_id);
        else if (change.resource_type === 'habit') this.removeHabit(change.resource_id);
        else if (change.resource_type === 'habit_checkin') this.removeHabitCheckin(change.resource_id);
        else if (change.resource_type === 'anniversary') this.removeAnniversary(change.resource_id);
      }
      return;
    }
    if (change.resource_type === 'task' && isTaskItem(change.resource)) {
      this.mergeTask(change.resource, change.cursor, false);
    } else if (change.resource_type === 'approval_request' && isApprovalRequest(change.resource)) {
      this.mergeApproval(change.resource, change.cursor, false);
    } else if (change.resource_type === 'comment' && isTaskComment(change.resource)) {
      this.mergeComment(change.resource, change.cursor, false);
    } else if (change.resource_type === 'classification' && isWorkspaceClassification(change.resource)) {
      if (change.action.toUpperCase() === 'DELETED') this.removeClassification(change.resource_id);
      else this.mergeClassification(change.resource, change.cursor, false);
    } else if (change.resource_type === 'ledger_entry' && isLedgerEntry(change.resource)) {
      this.mergeLedgerEntry(change.resource, change.action, change.cursor, false);
    } else if (change.resource_type === 'habit' && isHabit(change.resource)) {
      this.mergeHabit(change.resource, change.action, change.cursor, false);
    } else if (change.resource_type === 'habit_checkin' && isHabitCheckin(change.resource)) {
      this.mergeHabitCheckin(change.resource, change.action, change.cursor, false);
    } else if (change.resource_type === 'anniversary' && isAnniversary(change.resource)) {
      this.mergeAnniversary(change.resource, change.action, change.cursor, false);
    }
  }

  private mergeTask(task: TaskItem, cursor: number, updateCursor = true): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = {
      ...snapshot,
      tasks: upsertTask(
        snapshot.tasks,
        normalizeTaskResource(task, snapshot.workspace_id, snapshot.classifications),
      ),
      cursor: nextCursor,
    };
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
    const normalizedComment = normalizeCommentResource(comment, snapshot.workspace_id, taskId);
    const comments = [...(snapshot.comments ?? [])].filter((item) => item.id !== normalizedComment.id);
    comments.push(normalizedComment);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, comments, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, comments, approvals: nextSnapshot.approval_requests, stale: false, error: null, authRequired: false });
  }

  private mergeClassification(classification: WorkspaceClassification, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const normalized = normalizeClassificationResource(classification, snapshot.workspace_id);
    const classifications = upsertClassification(snapshot.classifications ?? [], normalized);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, classifications, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeClassification(classificationId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const classifications = (snapshot.classifications ?? []).filter((item) => item.id !== classificationId);
    if (classifications.length === (snapshot.classifications ?? []).length) return;
    const nextSnapshot = { ...snapshot, classifications };
    this.setState({ snapshot: nextSnapshot, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeLedgerEntry(entry: LedgerEntry, action: string, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || entry.workspace_id !== snapshot.workspace_id) return;
    const entries = [...(snapshot.ledger_entries ?? [])].filter((item) => item.id !== entry.id);
    if (action.toUpperCase() !== 'DELETED') entries.push(entry);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, ledger_entries: entries, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeLedgerEntry(entryId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const entries = (snapshot.ledger_entries ?? []).filter((item) => item.id !== entryId);
    if (entries.length === (snapshot.ledger_entries ?? []).length) return;
    const nextSnapshot = { ...snapshot, ledger_entries: entries };
    this.setState({ snapshot: nextSnapshot, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeHabit(habit: Habit, action: string, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || habit.workspace_id !== snapshot.workspace_id) return;
    const habits = [...(snapshot.habits ?? [])].filter((item) => item.id !== habit.id);
    if (action.toUpperCase() !== 'DELETED') habits.push(habit);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, habits, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeHabit(habitId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const habits = (snapshot.habits ?? []).filter((item) => item.id !== habitId);
    if (habits.length === (snapshot.habits ?? []).length) return;
    const nextSnapshot = { ...snapshot, habits };
    this.setState({ snapshot: nextSnapshot, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeHabitCheckin(checkin: HabitCheckin, action: string, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || checkin.workspace_id !== snapshot.workspace_id) return;
    const checkins = [...(snapshot.habit_checkins ?? [])].filter((item) => item.id !== checkin.id);
    if (action.toUpperCase() !== 'DELETED' && checkin.revoked_at === null) checkins.push(checkin);
    const habits = (snapshot.habits ?? []).map((habit) => action.toUpperCase() === 'DELETED'
      ? removeCheckinFromHabit(habit, checkin.id, checkin)
      : mergeCheckinIntoHabit(habit, checkin));
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, habits, habit_checkins: checkins, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeHabitCheckin(checkinId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const checkins = (snapshot.habit_checkins ?? []).filter((item) => item.id !== checkinId);
    const removed = snapshot.habit_checkins?.find((item) => item.id === checkinId);
    const habits = (snapshot.habits ?? []).map((habit) => removeCheckinFromHabit(habit, checkinId, removed));
    if (checkins.length === (snapshot.habit_checkins ?? []).length
      && habits.every((habit, index) => habit === snapshot.habits?.[index])) return;
    const nextSnapshot = { ...snapshot, habits, habit_checkins: checkins };
    this.setState({ snapshot: nextSnapshot, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private mergeAnniversary(anniversary: Anniversary, action: string, cursor = this.currentState.cursor, updateCursor = false): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot || anniversary.workspace_id !== snapshot.workspace_id) return;
    const anniversaries = [...(snapshot.anniversaries ?? [])].filter((item) => item.id !== anniversary.id);
    if (action.toUpperCase() !== 'DELETED') anniversaries.push(anniversary);
    const nextCursor = updateCursor ? Math.max(snapshot.cursor, cursor) : snapshot.cursor;
    const nextSnapshot = { ...snapshot, anniversaries, cursor: nextCursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? Math.max(this.currentState.cursor, nextCursor) : this.currentState.cursor, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
  }

  private removeAnniversary(anniversaryId: string): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const anniversaries = (snapshot.anniversaries ?? []).filter((item) => item.id !== anniversaryId);
    if (anniversaries.length === (snapshot.anniversaries ?? []).length) return;
    const nextSnapshot = { ...snapshot, anniversaries };
    this.setState({ snapshot: nextSnapshot, approvals: nextSnapshot.approval_requests, comments: nextSnapshot.comments, stale: false, error: null, authRequired: false });
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
    const task = result.task
      ? normalizeTaskResource(
        result.task,
        snapshot.workspace_id,
        snapshot.classifications,
      )
      : undefined;
    const comment = result.comment ? normalizeCommentResource(result.comment, snapshot.workspace_id, approval.task_id ?? undefined) : undefined;
    const classification = result.classification ? normalizeClassificationResource(result.classification, snapshot.workspace_id) : undefined;
    const approvals = [...(snapshot.approval_requests ?? [])].filter((item) => item.id !== approval.id);
    approvals.push(approval);
    const tasks = task ? upsertTask(snapshot.tasks, task) : snapshot.tasks;
    const comments = comment
      ? [...(snapshot.comments ?? [])].filter((item) => item.id !== comment.id).concat(comment)
      : snapshot.comments ?? [];
    const classifications = classification
      ? upsertClassification(snapshot.classifications ?? [], classification)
      : snapshot.classifications;
    const cursor = updateCursor && typeof result.cursor === 'number' && result.cursor > snapshot.cursor ? result.cursor : snapshot.cursor;
    const nextSnapshot = { ...snapshot, tasks, comments, approval_requests: approvals, classifications, cursor };
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
    if (!isValidCursor(details.cursor) || details.cursor < this.currentState.cursor) return false;
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
        const currentTask = normalizeTaskResource(
          conflict.current_snapshot,
          snapshot.workspace_id,
          snapshot.classifications,
        );
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
    return isValidChangeResource(change.resource_type, change.resource, workspaceId, change.action)
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
  const classifications = value.classifications;
  const ledgerEntries = value.ledger_entries;
  const habits = value.habits;
  const habitCheckins = value.habit_checkins;
  const anniversaries = value.anniversaries;

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
    || !comments.every((item) => isTaskComment(item) && item.workspace_id === workspaceId)
    || !Array.isArray(approvalRequests)
    || !approvalRequests.every((item) => isApprovalRequest(item) && item.workspace_id === workspaceId)
    || (ledgerEntries !== undefined && (!Array.isArray(ledgerEntries) || !ledgerEntries.every((item) => isLedgerEntry(item) && item.workspace_id === workspaceId)))
    || (habits !== undefined && (!Array.isArray(habits) || !habits.every((item) => isHabit(item) && item.workspace_id === workspaceId)))
    || (habitCheckins !== undefined && (!Array.isArray(habitCheckins) || !habitCheckins.every((item) => isHabitCheckin(item) && item.workspace_id === workspaceId)))
    || (anniversaries !== undefined && (!Array.isArray(anniversaries) || !anniversaries.every((item) => isAnniversary(item) && item.workspace_id === workspaceId)))) {
    throw new Error('workspace snapshot is invalid');
  }

  if (classifications !== undefined
    && (!Array.isArray(classifications)
      || !classifications.every((item) => isWorkspaceClassification(item) && item.workspace_id === workspaceId))) {
    throw new Error('workspace snapshot classifications are invalid');
  }

  const parsedClassifications = classifications as WorkspaceClassification[] | undefined;
  const parsedTasks = tasks.map(parseTaskItem);
  ensureTaskClassificationsApproved(parsedTasks, parsedClassifications);

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
    tasks: parsedTasks,
    conflicts,
    cursor,
    viewer_user_id: viewerUserId === undefined ? null : viewerUserId,
    comments,
    approval_requests: approvalRequests,
    classifications: parsedClassifications,
    ledger_entries: ledgerEntries as LedgerEntry[] | undefined,
    habits: habits as Habit[] | undefined,
    habit_checkins: habitCheckins as HabitCheckin[] | undefined,
    anniversaries: anniversaries as Anniversary[] | undefined,
  };
}

function normalizeHomeResponse(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
): HomeResponse {
  if (!isRecord(value)) {
    throw new Error('home response is invalid');
  }

  const hasLegacy = ['current_tasks', 'blocked_tasks', 'review_tasks', 'pending_approval_count']
    .every((key) => hasOwn(value, key));
  const hasCanonical = hasOwn(value, 'viewer_user_id')
    || hasOwn(value, 'as_of')
    || hasOwn(value, 'week')
    || hasOwn(value, 'entry_counts')
    || hasOwn(value, 'entries')
    || hasCanonicalMoment(value.moment);
  if (!hasLegacy && !hasCanonical) throw new Error('home response is invalid');

  const canonicalKeys = ['viewer_user_id', 'as_of', 'week', 'entry_counts', 'moment', 'entries'];
  if (hasCanonical && !canonicalKeys.every((key) => hasOwn(value, key))) {
    throw new Error('home response is missing canonical fields');
  }

  const normalized = { ...value } as HomeResponse;
  const currentTasks = hasOwn(value, 'current_tasks')
    ? normalizeHomeTaskSection(value.current_tasks, workspaceId, classifications)
    : undefined;
  const blockedTasks = hasOwn(value, 'blocked_tasks')
    ? normalizeHomeTaskSection(value.blocked_tasks, workspaceId, classifications)
    : undefined;
  const reviewTasks = hasOwn(value, 'review_tasks')
    ? normalizeHomeTaskSection(value.review_tasks, workspaceId, classifications)
    : undefined;
  if (currentTasks) normalized.current_tasks = currentTasks;
  if (blockedTasks) normalized.blocked_tasks = blockedTasks;
  if (reviewTasks) normalized.review_tasks = reviewTasks;

  const rawPending = value.pending_approval_count;
  if (rawPending !== undefined && !isNonNegativeSafeInteger(rawPending)) {
    throw new Error('home pending approval count is invalid');
  }

  let moment: HomeMoment | undefined;
  let entries: HomeEntries | undefined;
  let entryCounts: HomeEntryCounts | undefined;
  if (hasCanonical) {
    if (typeof value.viewer_user_id !== 'string' || value.viewer_user_id.trim().length === 0) {
      throw new Error('home viewer is invalid');
    }
    if (!isIsoTimestamp(value.as_of)) throw new Error('home as_of is invalid');
    if (!isRecord(value.week)) throw new Error('home week is invalid');
    const week = normalizeHomeWeek(value.week);
    entryCounts = normalizeHomeEntryCounts(value.entry_counts);
    moment = normalizeHomeMoment(value.moment, workspaceId, classifications, true);
    entries = normalizeHomeEntries(value.entries, workspaceId, classifications);
    normalized.viewer_user_id = value.viewer_user_id;
    normalized.as_of = value.as_of;
    normalized.week = week;
    normalized.entry_counts = entryCounts;
    normalized.moment = moment;
    normalized.entries = entries;
  } else if (hasOwn(value, 'moment')) {
    moment = normalizeHomeMoment(value.moment, workspaceId, classifications, false);
    normalized.moment = moment;
  }

  if (rawPending !== undefined) {
    normalized.pending_approval_count = rawPending;
  } else if (entryCounts) {
    normalized.pending_approval_count = entryCounts.needs_me;
  }

  normalizeOptionalHomeCount(value.needs_action_count, 'needs_action_count');
  normalizeOptionalHomeCount(value.waiting_on_other_count, 'waiting_on_other_count');
  normalizeOptionalHomeCount(value.week_due_count, 'week_due_count');
  return normalized;
}

function normalizeHomeTaskSection(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
  allowedStatuses?: ReadonlySet<string>,
): HomeTaskSection {
  if (!isRecord(value)
    || !Array.isArray(value.items)
    || typeof value.has_more !== 'boolean'
    || !value.items.every((item) => isTaskItem(item) && item.workspace_id === workspaceId)) {
    throw new Error('home task section is invalid');
  }
  const items = value.items.map(parseTaskItem);
  if (allowedStatuses && !items.every((item) => allowedStatuses.has(item.status))) {
    throw new Error('home task section status is invalid');
  }
  ensureTaskClassificationsApproved(items, classifications);
  return { items, has_more: value.has_more };
}

function normalizeHomeMoment(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
  requireCanonical = false,
): HomeMoment {
  if (!isRecord(value)) throw new Error('home moment is invalid');
  const hasBlocked = hasOwn(value, 'blocked');
  const hasMine = hasOwn(value, 'mine');
  const hasOther = hasOwn(value, 'other');
  if (requireCanonical && (!hasBlocked || !hasMine || !hasOther)) {
    throw new Error('home moment is missing canonical sections');
  }

  const normalized: HomeMoment = {};
  if (hasBlocked) {
    normalized.blocked = normalizeHomeTaskSection(
      value.blocked,
      workspaceId,
      classifications,
      new Set(['BLOCKED']),
    );
  } else if (hasOwn(value, 'blocked_tasks')) {
    normalized.blocked_tasks = normalizeHomeTaskSection(value.blocked_tasks, workspaceId, classifications);
  }
  if (hasMine) {
    normalized.mine = normalizeHomeTaskSection(
      value.mine,
      workspaceId,
      classifications,
      new Set(['TODO', 'IN_PROGRESS']),
    );
  } else if (hasOwn(value, 'my_tasks')) {
    normalized.my_tasks = normalizeHomeTaskSection(value.my_tasks, workspaceId, classifications);
  }
  if (hasOther) {
    normalized.other = normalizeHomeTaskSection(
      value.other,
      workspaceId,
      classifications,
      new Set(['TODO', 'IN_PROGRESS']),
    );
  } else if (hasOwn(value, 'other_tasks')) {
    normalized.other_tasks = normalizeHomeTaskSection(value.other_tasks, workspaceId, classifications);
  }
  if (hasOwn(value, 'blocked_tasks') && hasBlocked) {
    normalized.blocked_tasks = normalizeHomeTaskSection(value.blocked_tasks, workspaceId, classifications);
  }
  if (hasOwn(value, 'my_tasks') && hasMine) {
    normalized.my_tasks = normalizeHomeTaskSection(value.my_tasks, workspaceId, classifications);
  }
  if (hasOwn(value, 'other_tasks') && hasOther) {
    normalized.other_tasks = normalizeHomeTaskSection(value.other_tasks, workspaceId, classifications);
  }
  if (hasOwn(value, 'all_tasks_has_more')) {
    if (typeof value.all_tasks_has_more !== 'boolean') throw new Error('home moment has_more is invalid');
    normalized.all_tasks_has_more = value.all_tasks_has_more;
  }
  return normalized;
}

function normalizeHomeEntries(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
): HomeEntries {
  if (!isRecord(value)
    || !hasOwn(value, 'needs_me')
    || !hasOwn(value, 'waiting_on_other')
    || !hasOwn(value, 'due_this_week')) {
    throw new Error('home entries are invalid');
  }
  return {
    needs_me: normalizeHomeApprovalSection(value.needs_me, workspaceId, classifications),
    waiting_on_other: normalizeHomeApprovalSection(value.waiting_on_other, workspaceId, classifications),
    due_this_week: normalizeHomeTaskSection(
      value.due_this_week,
      workspaceId,
      classifications,
      new Set(['TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW']),
    ),
  };
}

function normalizeHomeApprovalSection(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
): HomeApprovalSection {
  if (!isRecord(value) || !Array.isArray(value.items) || typeof value.has_more !== 'boolean') {
    throw new Error('home approval section is invalid');
  }
  return {
    items: value.items.map((item) => normalizeHomeApprovalItem(item, workspaceId, classifications)),
    has_more: value.has_more,
  };
}

function normalizeHomeApprovalItem(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
): HomeApprovalItem {
  if (!isRecord(value) || !isRecord(value.approval_request)) {
    throw new Error('home approval item is invalid');
  }
  const approval = value.approval_request;
  if (!isApprovalRequest(approval)
    || approval.workspace_id !== workspaceId
    || approval.status !== 'PENDING') {
    throw new Error('home approval request is invalid');
  }
  const rawTask = value.task;
  if (rawTask === null || rawTask === undefined) {
    if (approval.task_id !== null) {
      throw new Error('home approval task is missing');
    }
    return { approval_request: approval, task: null };
  }
  if (!isTaskItem(rawTask)
    || rawTask.workspace_id !== workspaceId
    || rawTask.deleted_at !== null
    || approval.task_id !== rawTask.id
    || !isCanonicalTaskStatus(normalizeTaskStatus(rawTask.status))) {
    throw new Error('home approval task is invalid');
  }
  const task = parseTaskItem(rawTask);
  ensureTaskClassificationsApproved([task], classifications);
  return { approval_request: approval, task };
}

function normalizeHomeWeek(value: Record<string, unknown>): HomeWeek {
  if (value.timezone !== 'UTC' || !isIsoTimestamp(value.start) || !isIsoTimestamp(value.end)) {
    throw new Error('home week is invalid');
  }
  if (Date.parse(value.end) <= Date.parse(value.start)) {
    throw new Error('home week boundaries are invalid');
  }
  return { timezone: 'UTC', start: value.start, end: value.end };
}

function normalizeHomeEntryCounts(value: unknown): HomeEntryCounts {
  if (!isRecord(value)
    || !isNonNegativeSafeInteger(value.needs_me)
    || !isNonNegativeSafeInteger(value.waiting_on_other)
    || !isNonNegativeSafeInteger(value.due_this_week)) {
    throw new Error('home entry counts are invalid');
  }
  return {
    needs_me: value.needs_me,
    waiting_on_other: value.waiting_on_other,
    due_this_week: value.due_this_week,
  };
}

function normalizeOptionalHomeCount(value: unknown, name: string): void {
  if (value !== undefined && !isNonNegativeSafeInteger(value)) {
    throw new Error(`home ${name} is invalid`);
  }
}

function isIsoTimestamp(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value));
}

function hasCanonicalMoment(value: unknown): boolean {
  return isRecord(value) && (hasOwn(value, 'blocked') || hasOwn(value, 'mine') || hasOwn(value, 'other'));
}

function normalizeTaskResource(
  value: unknown,
  workspaceId: string,
  classifications?: WorkspaceClassification[],
): TaskItem {
  if (!isRecord(value)) throw new Error('task response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isTaskItem(candidate) || candidate.workspace_id !== workspaceId) {
    throw new Error('task response belongs to another workspace');
  }
  const task = parseTaskItem(candidate);
  ensureTaskClassificationsApproved([task], classifications);
  return task;
}

function normalizeApprovalResource(value: unknown, workspaceId: string): TaskApprovalRequest {
  if (!isRecord(value)) throw new Error('approval response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isApprovalRequest(candidate) || candidate.workspace_id !== workspaceId) {
    throw new Error('approval response belongs to another workspace');
  }
  return candidate;
}

function normalizeClassificationResource(value: unknown, workspaceId: string): WorkspaceClassification {
  if (!isWorkspaceClassification(value) || value.workspace_id !== workspaceId) {
    throw new Error('classification response belongs to another workspace');
  }
  return value;
}

function normalizeCommentResource(value: unknown, workspaceId: string, taskId?: string): TaskComment {
  if (!isRecord(value)) throw new Error('comment response is not an object');
  const { cursor: _ackCursor, ...candidate } = value;
  if (!isTaskComment(candidate)
    || candidate.workspace_id !== workspaceId
    || (taskId !== undefined && candidate.task_id !== taskId)) {
    throw new Error('comment response belongs to another workspace or task');
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
    && ((typeof value.task_id === 'string' && value.task_id.length > 0)
      || (value.task_id === null && (value.request_type === 'CLASSIFICATION_CREATE' || value.request_type === 'TASK_INVITATION')))
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

function isWorkspaceClassification(value: unknown): value is WorkspaceClassification {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && typeof value.name === 'string'
    && value.name.trim().length > 0
    && Array.from(value.name.trim()).length <= 5
    && typeof value.created_by === 'string'
    && value.created_by.length > 0
    && (value.created_at === null || typeof value.created_at === 'string');
}

function isTaskComment(value: unknown): value is TaskComment {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
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

function isLedgerEntry(value: unknown): value is LedgerEntry {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && (value.type === 'EXPENSE' || value.type === 'INCOME')
    && isPositiveSafeInteger(value.amount_minor)
    && typeof value.amount === 'string'
    && typeof value.currency === 'string'
    && typeof value.title === 'string'
    && typeof value.category === 'string'
    && typeof value.payer_or_payee_id === 'string'
    && typeof value.date === 'string'
    && isNullableString(value.note)
    && typeof value.created_by === 'string'
    && typeof value.updated_by === 'string'
    && isPositiveSafeInteger(value.version)
    && isNullableString(value.deleted_at);
}

function isHabitCheckin(value: unknown): value is HabitCheckin {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.habit_id === 'string'
    && value.habit_id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && typeof value.actor_id === 'string'
    && value.actor_id.length > 0
    && (value.frequency_snapshot === 'DAILY' || value.frequency_snapshot === 'WEEKLY' || value.frequency_snapshot === 'MONTHLY')
    && typeof value.period_key === 'string'
    && value.period_key.length > 0
    && typeof value.day === 'string'
    && typeof value.occurred_at === 'string'
    && isNullableString(value.revoked_at);
}

function isHabit(value: unknown): value is Habit {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && typeof value.owner_id === 'string'
    && value.owner_id.length > 0
    && typeof value.title === 'string'
    && isNullableString(value.note)
    && (value.frequency === 'DAILY' || value.frequency === 'WEEKLY' || value.frequency === 'MONTHLY')
    && typeof value.start_date === 'string'
    && (value.status === 'ACTIVE' || value.status === 'PAUSED' || value.status === 'DELETED')
    && isPositiveSafeInteger(value.version)
    && typeof value.current_period_key === 'string'
    && typeof value.checked_in === 'boolean'
    && (value.current_checkin === null || isHabitCheckin(value.current_checkin))
    && Array.isArray(value.checkins)
    && value.checkins.every(isHabitCheckin)
    && (value.recent_days === undefined || (Array.isArray(value.recent_days) && value.recent_days.every((day) => typeof day === 'string')))
    && (value.recent_checkin_days === undefined || (Array.isArray(value.recent_checkin_days) && value.recent_checkin_days.every((day) => typeof day === 'string')))
    && isNullableString(value.deleted_at);
}

function isAnniversary(value: unknown): value is Anniversary {
  return isRecord(value)
    && typeof value.id === 'string'
    && value.id.length > 0
    && typeof value.workspace_id === 'string'
    && value.workspace_id.length > 0
    && typeof value.title === 'string'
    && typeof value.anchor_date === 'string'
    && (value.kind === 'ANNIVERSARY' || value.kind === 'BIRTHDAY' || value.kind === 'IMPORTANT_DAY')
    && isNonNegativeSafeInteger(value.prepare_days)
    && isNullableString(value.note)
    && typeof value.next_occurrence === 'string'
    && isNonNegativeSafeInteger(value.days_until)
    && typeof value.is_today === 'boolean'
    && isPositiveSafeInteger(value.version)
    && isNullableString(value.deleted_at);
}

function isWorkspaceMember(value: unknown): value is WorkspaceSnapshot['members'][number] {
  if (!isRecord(value)
    || typeof value.user_id !== 'string'
    || value.user_id.length === 0
    || !isPositiveSafeInteger(value.member_slot)) return false;
  return (value.membership_status === undefined || typeof value.membership_status === 'string')
    && (value.status === undefined || typeof value.status === 'string');
}

function isValidChangeResource(resourceType: string, resource: unknown, workspaceId: string, action?: string): boolean {
  // Action-first tombstones carry only a resource id. Life resources use this
  // form when the deleted row is no longer readable from the changes query.
  if (resource === null) {
    return resourceType === 'task_conflict'
      || (action?.toUpperCase() === 'DELETED' && isLifeResourceType(resourceType));
  }
  if (!isRecord(resource)) return false;
  if (resourceType === 'task') return isTaskItem(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'task_conflict') {
    return isTaskConflict(resource, workspaceId) && resource.workspace_id === workspaceId;
  }
  if (resourceType === 'approval_request') return isApprovalRequest(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'comment') return isTaskComment(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'classification') return isWorkspaceClassification(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'ledger_entry') return isLedgerEntry(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'habit') return isHabit(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'habit_checkin') return isHabitCheckin(resource) && resource.workspace_id === workspaceId;
  if (resourceType === 'anniversary') return isAnniversary(resource) && resource.workspace_id === workspaceId;
  return false;
}

function isLifeResourceType(resourceType: string): boolean {
  return resourceType === 'ledger_entry'
    || resourceType === 'habit'
    || resourceType === 'habit_checkin'
    || resourceType === 'anniversary';
}

function mergeCheckinIntoHabit(habit: Habit, checkin: HabitCheckin): Habit {
  if (habit.id !== checkin.habit_id) return habit;
  const checkins = [...habit.checkins.filter((item) => item.id !== checkin.id), checkin];
  const current = checkins.find((item) => item.frequency_snapshot === habit.frequency
    && item.period_key === habit.current_period_key
    && item.revoked_at === null) ?? null;
  const recentCheckinDays = new Set(habit.recent_checkin_days ?? []);
  if ((habit.recent_days ?? []).includes(checkin.day)) {
    if (checkin.revoked_at === null) recentCheckinDays.add(checkin.day);
    else if (!checkins.some((item) => item.day === checkin.day && item.revoked_at === null)) {
      recentCheckinDays.delete(checkin.day);
    }
  }
  return {
    ...habit,
    checkins,
    current_checkin: current,
    checked_in: current !== null,
    recent_checkin_days: (habit.recent_days ?? []).filter((day) => recentCheckinDays.has(day)),
  };
}

function removeCheckinFromHabit(habit: Habit, checkinId: string, removed?: HabitCheckin): Habit {
  if (!removed && !habit.checkins.some((item) => item.id === checkinId)
    && habit.current_checkin?.id !== checkinId) return habit;
  const prior = removed ?? habit.checkins.find((item) => item.id === checkinId) ?? habit.current_checkin ?? undefined;
  const checkins = habit.checkins.filter((item) => item.id !== checkinId);
  const current = checkins.find((item) => item.frequency_snapshot === habit.frequency
    && item.period_key === habit.current_period_key
    && item.revoked_at === null) ?? null;
  const recentCheckinDays = new Set(habit.recent_checkin_days ?? []);
  if (prior && (habit.recent_days ?? []).includes(prior.day)
    && !checkins.some((item) => item.day === prior.day && item.revoked_at === null)) {
    recentCheckinDays.delete(prior.day);
  }
  return {
    ...habit,
    checkins,
    current_checkin: current,
    checked_in: current !== null,
    recent_checkin_days: (habit.recent_days ?? []).filter((day) => recentCheckinDays.has(day)),
  };
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

function hasOwn(value: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
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
  // Accept retired values only at the wire/read boundary; parseTaskItem
  // normalizes them before they reach the rest of the application.
  return isCanonicalTaskStatus(value) || value === 'WAITING' || value === 'COMPLETED';
}

function isApprovalRequestType(value: unknown): value is TaskApprovalRequest['request_type'] {
  return value === 'TASK_UPDATE'
    || value === 'QUADRANT_UPDATE'
    || value === 'STATUS_UPDATE'
    || value === 'TASK_DELETE'
    || value === 'TASK_RESTORE'
    || value === 'COMMENT_DELETE'
    || value === 'HANDLER_TRANSFER'
    || value === 'CLASSIFICATION_CREATE';
}

function classificationNames(classifications: WorkspaceClassification[]): Set<string> {
  return new Set(classifications.map((classification) => classification.name.trim().toLocaleLowerCase()));
}

function ensureTaskClassificationsApproved(
  tasks: TaskItem[],
  classifications?: WorkspaceClassification[],
): void {
  // Older cached snapshots did not carry the classifications resource. Keep
  // them readable until the next authoritative snapshot replaces them.
  if (classifications === undefined) return;
  const approved = classificationNames(classifications);
  for (const task of tasks) {
    if (task.labels.length === 0) continue;
    if (task.labels.length !== 1
      || !approved.has(task.labels[0].trim().toLocaleLowerCase())) {
      throw new Error('任务包含未批准分类。');
    }
  }
}

function normalizeApprovalChanges(
  proposedChanges: Record<string, unknown>,
  classifications: WorkspaceClassification[],
): Record<string, unknown> {
  if (!Object.prototype.hasOwnProperty.call(proposedChanges, 'labels')) {
    return { ...proposedChanges };
  }
  const labels = parseTaskLabels(proposedChanges.labels);
  if (labels.length !== 1) {
    throw new Error('任务必须选择一个已批准分类。');
  }
  const approved = approvedClassificationNames(classifications).find(
    (name) => name.toLocaleLowerCase() === labels[0].toLocaleLowerCase(),
  );
  if (!approved) {
    throw new Error('任务只能选择已批准分类。');
  }
  return { ...proposedChanges, labels: [approved] };
}

function upsertClassification(classifications: WorkspaceClassification[], classification: WorkspaceClassification): WorkspaceClassification[] {
  const index = classifications.findIndex((item) => item.id === classification.id);
  if (index === -1) return [...classifications, classification];
  return classifications.map((item) => item.id === classification.id ? classification : item);
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
