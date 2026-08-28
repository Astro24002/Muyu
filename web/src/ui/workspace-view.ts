import type { TaskItem } from '../api/types';
import type { TaskConflict } from '../tasks/task-model';
import { deriveTaskSummary, filterMyTasks, groupTasksByStatus, TASK_STATUSES } from '../tasks/task-view-model';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';
import { ApprovalView } from './approval-view';
import { TaskDetailView, type TaskDetailHandle } from './task-detail-view';
import { WebSessionView, type WebSessionViewApi } from './web-session-view';

export class WorkspaceView {
  static mount(
    root: Element,
    sync: WorkspaceSyncController,
    onLogout: () => void,
    sessionApi?: WebSessionViewApi,
    onSessionAuthRequired: () => void = onLogout,
  ): () => void {
    let mode: 'list' | 'board' = 'list';
    let myOnly = false;
    let creating = false;
    let showSessions = false;
    let detailCleanup: (() => void) | undefined;
    let sessionCleanup: (() => void) | undefined;
    let approvalCleanup: (() => void) | undefined;
    let detailHandle: TaskDetailHandle | undefined;
    let activeTaskId: string | null = null;
    let draftTitle = '';
    let draftDescription = '';
    let showApprovals = false;

    const render = (state: WorkspaceSyncState) => {
      if (state.authRequired) {
        sessionCleanup?.();
        sessionCleanup = undefined;
        onLogout();
        return;
      }
      if (activeTaskId && detailHandle) {
        const task = state.snapshot?.tasks.find((item) => item.id === activeTaskId);
        if (task) detailHandle.update(task, state.conflicts, state.error, state.comments ?? state.snapshot?.comments ?? []);
        return;
      }

      sessionCleanup?.();
      sessionCleanup = undefined;
      approvalCleanup?.();
      approvalCleanup = undefined;
      const page = buildWorkspace(
        state,
        sync,
        onLogout,
        mode,
        myOnly,
        draftTitle,
        draftDescription,
        creating,
        showSessions,
        showApprovals,
        Boolean(sessionApi),
        (value) => { draftTitle = value; },
        (value) => { draftDescription = value; },
        () => { draftTitle = ''; draftDescription = ''; },
        (value) => { creating = value; render(sync.state); },
        (nextMode) => { mode = nextMode; render(sync.state); },
        (nextMy) => { myOnly = nextMy; render(sync.state); },
        () => { showSessions = !showSessions; render(sync.state); },
        () => { showApprovals = !showApprovals; render(sync.state); },
        (task) => {
          activeTaskId = task.id;
          detailHandle = TaskDetailView.mount(root, task, state.snapshot?.members ?? [], {
            conflicts: state.conflicts,
            comments: state.comments ?? state.snapshot?.comments ?? [],
            currentUserId: state.snapshot?.viewer_user_id ?? undefined,
            hasPendingApproval: () => sync.state.approvals?.some((request) => request.task_id === task.id && request.status === 'PENDING') ?? sync.state.snapshot?.approval_requests?.some((request) => request.task_id === task.id && request.status === 'PENDING') ?? false,
            onTransition: (status, payload) => sync.transitionTask(task.id, status, payload),
            onComment: (body) => sync.addComment(task.id, body),
            onDelay: (date, reason, note) => sync.addDelay(task.id, date, reason, note),
            onSave: (changes) => sync.patchTask(task.id, changes),
            onDeleteComment: (commentId, baseVersion) => sync.deleteTaskComment(task.id, commentId, baseVersion),
            onResolveConflict: (id, resolution) => sync.resolveConflict(task.id, id, resolution),
            onClose: () => {
              activeTaskId = null;
              detailCleanup = undefined;
              detailHandle = undefined;
              render(sync.state);
            },
          });
          detailCleanup = () => {
            detailHandle?.();
            detailHandle = undefined;
            activeTaskId = null;
          };
        },
      );
      root.replaceChildren(page);
      if (sessionApi && showSessions) {
        const slot = page.querySelector<HTMLElement>('[data-web-session-slot]');
        if (slot) sessionCleanup = WebSessionView.mount(slot, sessionApi, { onAuthRequired: onSessionAuthRequired });
      }
      if (showApprovals) {
        const slot = page.querySelector<HTMLElement>('[data-approval-slot]');
        const viewerId = state.snapshot?.viewer_user_id ?? '';
        if (slot) approvalCleanup = ApprovalView.mount(slot, sync, viewerId);
      }
    };

    const unsubscribe = sync.subscribe(render);
    render(sync.state);
    return () => {
      detailCleanup?.();
      sessionCleanup?.();
      approvalCleanup?.();
      activeTaskId = null;
      unsubscribe();
    };
  }
}

function buildWorkspace(
  state: WorkspaceSyncState,
  sync: WorkspaceSyncController,
  onLogout: () => void,
  mode: 'list' | 'board',
  myOnly: boolean,
  draftTitle: string,
  draftDescription: string,
  creating: boolean,
  showSessions: boolean,
  showApprovals: boolean,
  hasSessionApi: boolean,
  setDraftTitle: (value: string) => void,
  setDraftDescription: (value: string) => void,
  clearDraft: () => void,
  setCreating: (value: boolean) => void,
  setMode: (mode: 'list' | 'board') => void,
  setMyOnly: (value: boolean) => void,
  toggleSessions: () => void,
  toggleApprovals: () => void,
  openTask: (task: TaskItem) => void,
): HTMLElement {
  const page = element('main', 'workspace-page');
  const header = element('header', 'workspace-header');
  header.append(element('div', undefined, 'Muyu'));
  const controls = element('div', 'workspace-controls');
  controls.append(button('刷新', () => void sync.refresh()));
  controls.append(button('任务审批', toggleApprovals));
  if (hasSessionApi) controls.append(button(showSessions ? '关闭网页登录会话' : '网页登录会话', toggleSessions));
  controls.append(button('退出登录', onLogout));
  header.append(controls);
  page.append(header);
  const tasks = (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at);
  const userId = state.snapshot?.viewer_user_id ?? '';
  const visible = myOnly ? filterMyTasks(tasks, userId) : tasks;
  const summary = deriveTaskSummary(myOnly ? visible : tasks);
  page.append(element('section', 'task-summary', `我的任务 ${summary.mine} | 阻塞 ${summary.blocked} | 24小时内 ${summary.dueSoon} | 已过期 ${summary.overdue} | 待处理冲突 ${state.conflicts.length}`));
  const nav = element('div', 'view-controls');
  nav.append(button('列表', () => setMode('list')), button('看板', () => setMode('board')));
  const mine = document.createElement('input');
  mine.type = 'checkbox';
  mine.checked = myOnly;
  mine.id = 'my-only';
  mine.addEventListener('change', () => setMyOnly(mine.checked));
  nav.append(mine, element('label', undefined, '只看我的任务'));
  page.append(nav);
  const form = document.createElement('form');
  form.className = 'new-task-form';
  const title = input('新任务标题', draftTitle);
  const description = input('任务描述', draftDescription);
  title.addEventListener('input', () => setDraftTitle(title.value));
  description.addEventListener('input', () => setDraftDescription(description.value));
  const create = button('创建任务');
  create.type = 'submit';
  create.disabled = creating;
  const formError = element('p', 'sync-error');
  form.append(title, description, create, formError);
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    if (creating || !title.value.trim()) {
      if (!title.value.trim()) formError.textContent = '请输入任务标题。';
      return;
    }
    setCreating(true);
    formError.textContent = '';
    void sync.createTask(title.value.trim(), description.value).then(() => {
      if (!sync.state.error) clearDraft();
    }).catch((error: unknown) => {
      formError.textContent = error instanceof Error ? error.message : '无法创建任务，请检查网络后重试。';
    }).finally(() => setCreating(false));
  });
  page.append(form);
  if (hasSessionApi) {
    const slot = element('section', 'web-session-slot');
    slot.dataset.webSessionSlot = 'true';
    slot.hidden = !showSessions;
    if (showSessions) page.append(slot);
  }
  if (showApprovals) {
    const slot = element('section', 'approval-slot');
    slot.dataset.approvalSlot = 'true';
    page.append(slot);
  }
  if (mode === 'board') {
    const boardNode = element('section', 'task-board');
    const groups = groupTasksByStatus(visible);
    for (const status of TASK_STATUSES) {
      const column = element('div', 'task-column');
      column.append(element('h2', undefined, status));
      for (const task of groups[status]) column.append(taskCard(task, sync, state.loading, openTask));
      boardNode.append(column);
    }
    page.append(boardNode);
  } else {
    const listNode = element('section', 'task-list');
    [...visible].sort((a, b) => b.updated_at.localeCompare(a.updated_at)).forEach((task) => listNode.append(taskCard(task, sync, state.loading, openTask)));
    page.append(listNode);
  }
  if (state.error) page.append(element('p', 'sync-error', state.error));
  if (state.conflicts.length) page.append(conflictPanel(state.conflicts, sync, state.loading));
  return page;
}

function taskCard(task: TaskItem, sync: WorkspaceSyncController, loading: boolean, openTask: (task: TaskItem) => void): HTMLElement {
  const row = element('article', 'task-row');
  row.addEventListener('click', () => openTask(task));
  const progressLabel = task.status === 'IN_PROGRESS' && task.progress !== null && task.progress !== undefined
    ? ` | 进度: ${task.progress}%`
    : '';
  const quadrantLabel = task.quadrant ? ` | ${task.quadrant}` : '';
  row.append(element('h3', undefined, `${task.task_number ?? task.id} ${task.title}`), element('p', 'task-meta', `${task.status}${quadrantLabel}${progressLabel} | 截止: ${task.due_at ?? '未设置'} | 延期: ${task.delay_count} | 版本: ${task.status_version}`));
  if (task.status === 'WAITING') row.append(element('p', 'blocked-reason', `阻塞: ${task.blocked_reason ?? '未说明'}`));
  if (task.due_at && Date.parse(task.due_at) < Date.now() && task.status !== 'DONE' && task.status !== 'CANCELLED') row.append(element('p', 'overdue-warning', '已过期'));
  const done = button('完成', (event) => { event.stopPropagation(); void sync.transitionTask(task.id, 'DONE'); });
  done.disabled = loading || task.status === 'DONE';
  row.append(done);
  return row;
}

function conflictPanel(conflicts: TaskConflict[], sync: WorkspaceSyncController, loading: boolean): HTMLElement {
  const panel = element('section', 'conflict-panel');
  panel.append(element('h2', undefined, '待处理冲突'));
  for (const conflict of conflicts) {
    const item = element('article', 'conflict-item');
    item.append(element('p', undefined, `字段: ${conflict.field}`), button('保留当前', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'current')), button('采用提议', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'proposed')));
    for (const node of item.querySelectorAll('button')) node.disabled = loading;
    panel.append(item);
  }
  return panel;
}

function element(tag: string, className?: string, text?: string): HTMLElement {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function input(placeholder: string, value = ''): HTMLInputElement {
  const node = document.createElement('input');
  node.type = 'text';
  node.placeholder = placeholder;
  node.setAttribute('aria-label', placeholder);
  node.value = value;
  return node;
}

function button(label: string, handler?: (event: Event) => void): HTMLButtonElement {
  const node = document.createElement('button');
  node.type = 'button';
  node.textContent = label;
  if (handler) node.addEventListener('click', handler);
  return node;
}
