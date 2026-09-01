import { test as base, expect, type Route } from '@playwright/test';
import type {
  ActivityEvent,
  TaskApprovalRequest,
  TaskComment,
  TaskItem,
  WebChallenge,
  WebSessionSummary,
  WorkspaceSnapshot,
} from '../src/api/types';

export interface VisualFixtureOptions {
  authenticated?: boolean;
  todayFocus?: boolean;
  conflicts?: boolean;
}

export interface WorkbenchFixture {
  setup(options?: VisualFixtureOptions): Promise<void>;
  goto(route?: string): Promise<void>;
}

interface FixtureState {
  authenticated: boolean;
  tasks: TaskItem[];
  approvals: TaskApprovalRequest[];
  comments: TaskComment[];
  conflicts: Array<Record<string, unknown>>;
  activities: Record<string, ActivityEvent[]>;
  sessions: WebSessionSummary[];
  cursor: number;
  challenge: WebChallenge;
}

export const test = base.extend<{ workbench: WorkbenchFixture }>({
  workbench: async ({ page }, use) => {
    const state = createFixtureState();

    await page.addInitScript(() => {
      class DeterministicWebSocket extends EventTarget {
        static readonly CONNECTING = 0;
        static readonly OPEN = 1;
        static readonly CLOSING = 2;
        static readonly CLOSED = 3;

        readonly url: string;
        readonly protocol = '';
        readonly extensions = '';
        readonly bufferedAmount = 0;
        binaryType: BinaryType = 'blob';
        readyState = DeterministicWebSocket.CONNECTING;
        onopen: ((event: Event) => void) | null = null;
        onclose: ((event: CloseEvent) => void) | null = null;
        onerror: ((event: Event) => void) | null = null;
        onmessage: ((event: MessageEvent) => void) | null = null;

        constructor(url: string, _protocols?: string | string[]) {
          super();
          this.url = url;
          queueMicrotask(() => {
            if (this.readyState !== DeterministicWebSocket.CONNECTING) return;
            this.readyState = DeterministicWebSocket.OPEN;
            const event = new Event('open');
            this.onopen?.(event);
            this.dispatchEvent(event);
          });
        }

        send(_data: unknown): void {
          // The visual suite only needs a stable open connection.
        }

        close(): void {
          if (this.readyState === DeterministicWebSocket.CLOSED) return;
          this.readyState = DeterministicWebSocket.CLOSING;
          this.readyState = DeterministicWebSocket.CLOSED;
          const event = new CloseEvent('close');
          this.onclose?.(event);
          this.dispatchEvent(event);
        }
      }

      Object.defineProperty(window, 'WebSocket', {
        configurable: true,
        writable: true,
        value: DeterministicWebSocket,
      });
    });

    await page.route('**/api/v1/**', (route) => fulfillApi(route, state));

    const setup = async (options: VisualFixtureOptions = {}): Promise<void> => {
      const next = createFixtureState(options);
      state.authenticated = next.authenticated;
      state.tasks = next.tasks;
      state.approvals = next.approvals;
      state.comments = next.comments;
      state.conflicts = next.conflicts;
      state.activities = next.activities;
      state.sessions = next.sessions;
      state.cursor = next.cursor;
      state.challenge = next.challenge;
    };

    const goto = async (route = '#/today'): Promise<void> => {
      const target = route.startsWith('#')
        ? `/${route}`
        : route.startsWith('/')
          ? route
          : `/#/${route}`;
      await page.goto(target);
      await page.waitForLoadState('domcontentloaded');
    };

    await use({ setup, goto });
  },
});

export { expect };

function createFixtureState(options: VisualFixtureOptions = {}): FixtureState {
  const todayFocus = options.todayFocus ?? true;
  const focusTask = makeTask({
    id: 'task-focus',
    task_number: '26090001',
    title: '整理周末晚餐',
    description: '列出需要购买的食材，确认周六晚餐安排。',
    due_at: '2026-09-02T12:00:00Z',
    status: todayFocus ? 'IN_PROGRESS' : 'TODO',
    updated_at: '2026-09-01T09:00:00Z',
    quadrant: 'Q2',
    labels: ['生活'],
    progress: todayFocus ? 40 : null,
  });
  const nextTask = makeTask({
    id: 'task-next',
    task_number: '26090002',
    title: '写工作计划',
    description: '整理本周三件最重要的工作。',
    due_at: '2026-09-03T09:00:00Z',
    quadrant: 'Q1',
    labels: ['工作'],
    updated_at: '2026-09-01T08:30:00Z',
  });
  const waitingTask = makeTask({
    id: 'task-waiting',
    task_number: '26090003',
    title: '等待书单确认',
    description: '等协作成员确认下一步。',
    status: 'WAITING',
    current_handler_id: 'partner',
    assignee_ids: ['partner'],
    blocked_reason: '等待对方确认',
    resume_handler_id: 'viewer',
    quadrant: 'Q3',
    labels: ['阅读'],
  });
  const doneTask = makeTask({
    id: 'task-done',
    task_number: '26090004',
    title: '已完成的整理',
    description: '',
    status: 'DONE',
    completed_at: '2026-08-31T16:00:00Z',
    quadrant: 'Q4',
    labels: [],
  });
  const tasks = [focusTask, nextTask, waitingTask, doneTask];

  const incomingApproval = makeApproval({
    id: 'approval-incoming',
    task_id: focusTask.id,
    requester_id: 'partner',
    approver_id: 'viewer',
    proposed_changes: { title: '伙伴提出的新标题' },
    request_id: 'request-incoming',
  });
  const outgoingApproval = makeApproval({
    id: 'approval-outgoing',
    task_id: nextTask.id,
    requester_id: 'viewer',
    approver_id: 'partner',
    proposed_changes: { description: '我提出的下一步描述' },
    request_id: 'request-outgoing',
  });

  return {
    authenticated: options.authenticated ?? true,
    tasks,
    approvals: [incomingApproval, outgoingApproval],
    comments: [{
      id: 'comment-focus',
      task_id: focusTask.id,
      author_user_id: 'viewer',
      body: '已经列出主要食材。',
      version: 1,
      deleted_at: null,
      deleted_by: null,
      created_at: '2026-09-01T08:45:00Z',
    }],
    conflicts: options.conflicts === false ? [] : [{
      id: 'conflict-title',
      task_id: focusTask.id,
      field: 'title',
      base: '整理周末晚餐',
      current: '整理周末晚餐',
      proposed: '周末晚餐准备',
      status: 'OPEN',
    }],
    activities: {
      [focusTask.id]: [
        { kind: 'operation', id: 'event-focus-update', task_id: focusTask.id, created_at: '2026-09-01T09:00:00Z', operation_type: 'UPDATE', actor_user_id: 'viewer', body: '已更新任务信息' },
        { kind: 'comment', id: 'event-focus-comment', task_id: focusTask.id, created_at: '2026-09-01T08:45:00Z', author_user_id: 'viewer', body: '已经列出主要食材。' },
      ],
      [nextTask.id]: [
        { kind: 'operation', id: 'event-next-create', task_id: nextTask.id, created_at: '2026-09-01T08:30:00Z', operation_type: 'CREATE', actor_user_id: 'viewer' },
      ],
      [waitingTask.id]: [
        { kind: 'delay', id: 'event-wait-delay', task_id: waitingTask.id, created_at: '2026-08-31T17:00:00Z', reason: '等待协作确认', actor_user_id: 'partner', note: '确认后继续。' },
      ],
    },
    sessions: [
      { id: 'session-current', status: 'ACTIVE', origin: 'http://127.0.0.1:4173', created_at: '2026-09-01T08:00:00Z', expires_at: '2099-01-01T00:00:00Z' },
      { id: 'session-expired', status: 'EXPIRED', origin: '旧浏览器', created_at: '2026-08-01T08:00:00Z', expires_at: '2026-08-02T00:00:00Z' },
      { id: 'session-revoked', status: 'REVOKED', origin: '已撤销设备', created_at: '2026-08-01T08:00:00Z', expires_at: '2099-01-01T00:00:00Z' },
    ],
    cursor: 8,
    challenge: {
      challenge_id: 'challenge-visual',
      qr_payload: '{"challenge_id":"challenge-visual","purpose":"visual-test"}',
      origin: 'http://127.0.0.1:4173',
      safety_code: '4812',
      expires_at: '2099-01-01T00:00:00Z',
    },
  };
}

function makeTask(overrides: Partial<TaskItem>): TaskItem {
  return {
    id: 'task-default',
    workspace_id: 'workspace-visual',
    parent_task_id: null,
    task_number: '26090000',
    title: '未命名任务',
    description: '',
    due_at: null,
    status: 'TODO',
    current_handler_id: 'viewer',
    blocked_reason: null,
    blocked_since: null,
    resume_handler_id: null,
    waiting_for_user_id: null,
    planned_start_at: null,
    estimated_minutes: 30,
    completed_at: null,
    created_by: 'viewer',
    created_at: '2026-08-30T08:00:00Z',
    updated_at: '2026-08-30T08:00:00Z',
    assignee_ids: ['viewer'],
    delay_count: 0,
    total_delay_minutes: 0,
    version: 1,
    status_version: 1,
    field_versions: { title: 1, description: 1 },
    lifecycle_version: 1,
    deleted_at: null,
    quadrant: 'Q2',
    labels: [],
    progress: null,
    ...overrides,
  };
}

function makeApproval(overrides: Partial<TaskApprovalRequest>): TaskApprovalRequest {
  return {
    id: 'approval-default',
    workspace_id: 'workspace-visual',
    task_id: 'task-default',
    comment_id: null,
    requester_id: 'partner',
    approver_id: 'viewer',
    request_type: 'TASK_UPDATE',
    proposed_changes: {},
    base_field_versions: { title: 1 },
    request_id: 'request-default',
    status: 'PENDING',
    created_at: '2026-09-01T08:00:00Z',
    reviewed_at: null,
    reviewed_by: null,
    rejection_reason: null,
    resolved_cursor: null,
    ...overrides,
  };
}

function snapshotFor(state: FixtureState): WorkspaceSnapshot {
  return {
    workspace_id: 'workspace-visual',
    workspace: { id: 'workspace-visual', name: '木鱼工作区', status: 'ACTIVE' },
    members: [
      { user_id: 'viewer', member_slot: 1 },
      { user_id: 'partner', member_slot: 2 },
    ],
    tasks: state.tasks,
    conflicts: state.conflicts,
    cursor: state.cursor,
    viewer_user_id: 'viewer',
    comments: state.comments,
    approval_requests: state.approvals,
  };
}

async function fulfillApi(route: Route, state: FixtureState): Promise<void> {
  const request = route.request();
  const method = request.method();
  const url = new URL(request.url());
  const pathname = url.pathname;

  if (pathname === '/api/v1/web-login/challenges' && method === 'POST') {
    await json(route, 201, state.challenge);
    return;
  }

  const challengeStatusMatch = /^\/api\/v1\/web-login\/challenges\/([^/]+)$/.exec(pathname);
  if (challengeStatusMatch && method === 'GET') {
    await json(route, 200, {
      challenge_id: decodeSegment(challengeStatusMatch[1]),
      status: 'PENDING',
      expires_at: state.challenge.expires_at,
    });
    return;
  }

  const challengeExchangeMatch = /^\/api\/v1\/web-login\/challenges\/([^/]+)\/exchange$/.exec(pathname);
  if (challengeExchangeMatch && method === 'POST') {
    state.authenticated = true;
    await json(route, 200, { status: 'authenticated', expires_at: '2099-01-01T00:00:00Z' });
    return;
  }

  if (pathname === '/api/v1/web-login/logout' && method === 'POST') {
    state.authenticated = false;
    await route.fulfill({ status: 204 });
    return;
  }

  if (pathname === '/api/v1/workspaces/current/snapshot' && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    await json(route, 200, snapshotFor(state));
    return;
  }

  if (pathname === '/api/v1/workspaces/current/changes' && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    await json(route, 200, { workspace_id: 'workspace-visual', cursor: Number(url.searchParams.get('after_cursor') ?? state.cursor), changes: [] });
    return;
  }

  if (pathname === '/api/v1/web-sessions' && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    await json(route, 200, state.sessions);
    return;
  }

  const revokeSessionMatch = /^\/api\/v1\/web-sessions\/([^/]+)\/revoke$/.exec(pathname);
  if (revokeSessionMatch && method === 'POST') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const id = decodeSegment(revokeSessionMatch[1]);
    state.sessions = state.sessions.filter((session) => session.id !== id);
    await route.fulfill({ status: 204 });
    return;
  }

  if (pathname === '/api/v1/web-sessions/revoke-all' && method === 'POST') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const revokedCount = state.sessions.length;
    state.sessions = [];
    await json(route, 200, { revoked_count: revokedCount });
    return;
  }

  const approvalListMatch = /^\/api\/v1\/workspaces\/([^/]+)\/approval-requests$/.exec(pathname);
  if (approvalListMatch && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const box = url.searchParams.get('box');
    const approvals = box === 'incoming'
      ? state.approvals.filter((approval) => approval.approver_id === 'viewer')
      : box === 'outgoing'
        ? state.approvals.filter((approval) => approval.requester_id === 'viewer')
        : state.approvals;
    await json(route, 200, approvals);
    return;
  }

  const approvalActionMatch = /^\/api\/v1\/workspaces\/([^/]+)\/approval-requests\/([^/]+)\/(approve|reject|cancel)$/.exec(pathname);
  if (approvalActionMatch && method === 'POST') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const id = decodeSegment(approvalActionMatch[2]);
    const action = approvalActionMatch[3];
    const body = postBody(route);
    const approval = state.approvals.find((item) => item.id === id);
    if (!approval) {
      await json(route, 404, { code: 'NOT_FOUND', message: '审批请求不存在。' });
      return;
    }
    const updated: TaskApprovalRequest = {
      ...approval,
      status: action === 'approve' ? 'APPROVED' : action === 'reject' ? 'REJECTED' : 'CANCELLED',
      reviewed_at: '2026-09-01T10:00:00Z',
      reviewed_by: 'viewer',
      rejection_reason: action === 'reject' && typeof body.reason === 'string' ? body.reason : approval.rejection_reason,
      resolved_cursor: state.cursor,
    };
    state.approvals = state.approvals.map((item) => item.id === id ? updated : item);
    await json(route, 200, { approval_request: updated, cursor: state.cursor });
    return;
  }

  const activityMatch = /^\/api\/v1\/tasks\/([^/]+)\/activity$/.exec(pathname);
  if (activityMatch && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    await json(route, 200, state.activities[decodeSegment(activityMatch[1])] ?? []);
    return;
  }

  const commentsMatch = /^\/api\/v1\/tasks\/([^/]+)\/comments$/.exec(pathname);
  if (commentsMatch && method === 'GET') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const taskId = decodeSegment(commentsMatch[1]);
    await json(route, 200, state.comments.filter((comment) => comment.task_id === taskId));
    return;
  }

  if (commentsMatch && method === 'POST') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const taskId = decodeSegment(commentsMatch[1]);
    const body = postBody(route);
    const comment: TaskComment = {
      id: `comment-${state.comments.length + 1}`,
      task_id: taskId,
      author_user_id: 'viewer',
      body: typeof body.body === 'string' ? body.body : '',
      version: 1,
      deleted_at: null,
      deleted_by: null,
      created_at: '2026-09-01T10:00:00Z',
    };
    state.comments = [...state.comments, comment];
    await json(route, 201, { ...comment, cursor: state.cursor });
    return;
  }

  const deleteCommentMatch = /^\/api\/v1\/tasks\/([^/]+)\/comments\/([^/]+)$/.exec(pathname);
  if (deleteCommentMatch && method === 'DELETE') {
    if (!state.authenticated) {
      await unauthorized(route);
      return;
    }
    const id = decodeSegment(deleteCommentMatch[2]);
    state.comments = state.comments.map((comment) => comment.id === id
      ? { ...comment, deleted_at: '2026-09-01T10:00:00Z', deleted_by: 'viewer' }
      : comment);
    await json(route, 200, state.comments.find((comment) => comment.id === id));
    return;
  }

  const delaysMatch = /^\/api\/v1\/tasks\/([^/]+)\/delays$/.exec(pathname);
  if (delaysMatch && method === 'GET') {
    await json(route, 200, []);
    return;
  }

  if (delaysMatch && method === 'POST') {
    await json(route, 201, { cursor: state.cursor });
    return;
  }

  const conflictMatch = /^\/api\/v1\/tasks\/([^/]+)\/conflicts\/([^/]+)\/resolve$/.exec(pathname);
  if (conflictMatch && method === 'POST') {
    const taskId = decodeSegment(conflictMatch[1]);
    const conflictId = decodeSegment(conflictMatch[2]);
    state.conflicts = state.conflicts.filter((conflict) => conflict.task_id !== taskId || conflict.id !== conflictId);
    const task = state.tasks.find((item) => item.id === taskId);
    await json(route, 200, { ...(task ?? makeTask({ id: taskId })), cursor: state.cursor });
    return;
  }

  const transitionMatch = /^\/api\/v1\/tasks\/([^/]+)\/transition$/.exec(pathname);
  if (transitionMatch && method === 'POST') {
    const taskId = decodeSegment(transitionMatch[1]);
    const body = postBody(route);
    const task = state.tasks.find((item) => item.id === taskId);
    if (!task) {
      await json(route, 404, { code: 'NOT_FOUND', message: '任务不存在。' });
      return;
    }
    const updated = { ...task, status: typeof body.target_status === 'string' ? body.target_status : task.status } as TaskItem;
    state.tasks = state.tasks.map((item) => item.id === taskId ? updated : item);
    await json(route, 200, { ...updated, cursor: state.cursor });
    return;
  }

  const taskPatchMatch = /^\/api\/v1\/tasks\/([^/]+)$/.exec(pathname);
  if (taskPatchMatch && method === 'PATCH') {
    const taskId = decodeSegment(taskPatchMatch[1]);
    const task = state.tasks.find((item) => item.id === taskId);
    if (!task) {
      await json(route, 404, { code: 'NOT_FOUND', message: '任务不存在。' });
      return;
    }
    const body = postBody(route);
    const changes = body.changes && typeof body.changes === 'object' ? body.changes as Record<string, unknown> : {};
    const updated = { ...task, ...changes, updated_at: '2026-09-01T10:00:00Z', version: task.version + 1 } as TaskItem;
    state.tasks = state.tasks.map((item) => item.id === taskId ? updated : item);
    await json(route, 200, { ...updated, cursor: state.cursor });
    return;
  }

  if (pathname === '/api/v1/tasks' && method === 'POST') {
    const body = postBody(route);
    const task = makeTask({
      id: `task-created-${state.tasks.length + 1}`,
      title: typeof body.title === 'string' ? body.title : '新任务',
      description: typeof body.description === 'string' ? body.description : '',
      quadrant: body.quadrant === 'Q1' || body.quadrant === 'Q2' || body.quadrant === 'Q3' || body.quadrant === 'Q4' ? body.quadrant : 'Q2',
      labels: Array.isArray(body.labels) ? body.labels.filter((item): item is string => typeof item === 'string') : [],
    });
    state.tasks = [...state.tasks, task];
    await json(route, 201, { ...task, cursor: state.cursor });
    return;
  }

  await json(route, 404, { code: 'NOT_FOUND', message: '未配置的测试接口。' });
}

function postBody(route: Route): Record<string, unknown> {
  try {
    const body = route.request().postDataJSON();
    return body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function decodeSegment(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

async function unauthorized(route: Route): Promise<void> {
  await json(route, 401, { code: 'web_session_expired', message: '登录状态已过期。' });
}

async function json(route: Route, status: number, payload: unknown): Promise<void> {
  await route.fulfill({
    status,
    contentType: 'application/json; charset=utf-8',
    body: JSON.stringify(payload),
  });
}
