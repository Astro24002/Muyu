import { ApiError, type ApiClient } from '../api/client';
import type { TaskItem, WorkspaceChange, WorkspaceSnapshot } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';
import { upsertTask } from '../tasks/task-model';

export interface WorkspaceSyncState {
  snapshot: WorkspaceSnapshot | null;
  cursor: number;
  loading: boolean;
  stale: boolean;
  error: string | null;
  conflicts: TaskConflict[];
  authRequired: boolean;
}

export interface WorkspaceSyncOptions {
  requestIdFactory?: () => string;
}

type Listener = (state: WorkspaceSyncState) => void;
type TaskWriteResult = TaskItem & { cursor: number };

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
  private readonly requestIdFactory: () => string;

  constructor(private readonly api: Pick<ApiClient, 'getWorkspaceSnapshot' | 'getWorkspaceChanges' | 'createTask' | 'patchTask' | 'resolveConflict'>, options: WorkspaceSyncOptions = {}) {
    this.requestIdFactory = options.requestIdFactory ?? createRequestId;
  }

  get state(): WorkspaceSyncState { return this.currentState; }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.clear();
  }

  async loadSnapshot(): Promise<void> {
    await this.run('无法加载工作区，请检查网络后重试。', async () => {
      const snapshot = await this.api.getWorkspaceSnapshot();
      this.setState({ snapshot, cursor: snapshot.cursor, conflicts: normalizeConflicts(snapshot.conflicts), stale: false, error: null, authRequired: false });
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

  async createTask(title: string, description: string): Promise<void> {
    await this.write('无法创建任务，请检查网络后重试。', () => this.api.createTask({ requestId: this.requestIdFactory(), title, description }));
  }

  async patchTask(taskId: string, changes: EditableTaskChanges): Promise<void> {
    const task = this.currentState.snapshot?.tasks.find((item) => item.id === taskId);
    if (!task) {
      this.setState({ error: '任务不存在，请刷新后重试。' });
      return;
    }
    const fields = Object.keys(changes);
    const baseFieldVersions = Object.fromEntries(fields.map((field) => [field, task.field_versions[field] ?? 1]));
    await this.write('无法更新任务，请检查网络后重试。', () => this.api.patchTask(taskId, {
      requestId: this.requestIdFactory(),
      changes,
      baseFieldVersions,
    }));
  }

  async resolveConflict(taskId: string, conflictId: string, resolution: 'current' | 'proposed'): Promise<void> {
    await this.write('无法解决冲突，请检查网络后重试。', () => this.api.resolveConflict(taskId, conflictId, {
      requestId: this.requestIdFactory(),
      resolution,
    }));
  }

  private async write(message: string, operation: () => Promise<TaskWriteResult>): Promise<void> {
    const cursorBeforeWrite = this.currentState.cursor;
    await this.run(message, async () => {
      const result = await operation();
      this.mergeTask(result, result.cursor);
      if (result.cursor > cursorBeforeWrite) await this.pullFrom(cursorBeforeWrite);
    });
  }

  private async pullFrom(afterCursor: number): Promise<void> {
    await this.run('同步失败，请检查网络后重试。', async () => {
      const changes = await this.api.getWorkspaceChanges(afterCursor);
      if (!areContiguous(changes.changes, afterCursor) || (changes.changes.length === 0 && changes.cursor !== afterCursor)) {
        await this.loadSnapshot();
        return;
      }
      for (const change of changes.changes) this.applyChange(change);
      this.setState({ cursor: Math.max(this.currentState.cursor, changes.cursor), stale: false, error: null, authRequired: false });
    }, true);
  }

  private applyChange(change: WorkspaceChange): void {
    if (change.resource_type !== 'task' || !change.resource) return;
    this.mergeTask(change.resource, change.cursor, false);
  }

  private mergeTask(task: TaskItem, cursor: number, updateCursor = true): void {
    const snapshot = this.currentState.snapshot;
    if (!snapshot) return;
    const nextSnapshot = { ...snapshot, tasks: upsertTask(snapshot.tasks, task), cursor: updateCursor ? cursor : snapshot.cursor };
    this.setState({ snapshot: nextSnapshot, cursor: updateCursor ? cursor : this.currentState.cursor, stale: false, error: null, authRequired: false });
  }

  private async run(message: string, operation: () => Promise<void>, nested = false): Promise<void> {
    if (!nested) this.setState({ loading: true, error: null });
    try {
      await operation();
    } catch (error) {
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
      if (!nested) this.setState({ loading: false });
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

function createRequestId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
