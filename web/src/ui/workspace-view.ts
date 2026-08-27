import type { TaskItem } from '../api/types';
import type { TaskConflict } from '../tasks/task-model';
import { deriveTaskSummary, filterMyTasks, groupTasksByStatus, TASK_STATUSES } from '../tasks/task-view-model';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';
import { TaskDetailView } from './task-detail-view';

export class WorkspaceView {
  static mount(root: Element, sync: WorkspaceSyncController, onLogout: () => void): () => void {
    let mode: 'list' | 'board' = 'list'; let myOnly = false; let detailCleanup: (() => void) | undefined;
    const render = (state: WorkspaceSyncState) => {
      if (state.authRequired) { onLogout(); return; }
      detailCleanup?.(); detailCleanup = undefined;
      root.replaceChildren(buildWorkspace(state, sync, onLogout, mode, myOnly, (nextMode) => { mode = nextMode; render(sync.state); }, (nextMy) => { myOnly = nextMy; render(sync.state); }, (task) => { detailCleanup = TaskDetailView.mount(root, task, state.snapshot?.members ?? [], { conflicts: state.conflicts, onTransition: (status, payload) => sync.transitionTask(task.id, status, payload), onComment: (body) => sync.addComment(task.id, body), onDelay: (date, reason, note) => sync.addDelay(task.id, date, reason, note), onSave: (changes) => sync.patchTask(task.id, changes), onResolveConflict: (id, resolution) => sync.resolveConflict(task.id, id, resolution) }); }));
    };
    const unsubscribe = sync.subscribe(render); render(sync.state);
    return () => { detailCleanup?.(); unsubscribe(); };
  }
}

function buildWorkspace(state: WorkspaceSyncState, sync: WorkspaceSyncController, onLogout: () => void, mode: 'list' | 'board', myOnly: boolean, setMode: (mode: 'list' | 'board') => void, setMyOnly: (value: boolean) => void, openTask: (task: TaskItem) => void): HTMLElement {
  const page = element('main', 'workspace-page');
  const header = element('header', 'workspace-header'); header.append(element('div', undefined, 'Muyu'));
  const controls = element('div', 'workspace-controls'); controls.append(button('刷新', () => void sync.refresh()), button('退出登录', onLogout)); header.append(controls); page.append(header);
  const tasks = (state.snapshot?.tasks ?? []).filter((task) => !task.deleted_at); const userId = state.snapshot?.members[0]?.user_id ?? ''; const visible = myOnly ? filterMyTasks(tasks, userId) : tasks;
  const summary = deriveTaskSummary(myOnly ? visible : tasks); page.append(element('section', 'task-summary', `我的任务 ${summary.mine} | 阻塞 ${summary.blocked} | 24小时内 ${summary.dueSoon} | 已过期 ${summary.overdue} | 待处理冲突 ${state.conflicts.length}`));
  const nav = element('div', 'view-controls'); nav.append(button('列表', () => setMode('list')), button('看板', () => setMode('board'))); const mine = document.createElement('input'); mine.type = 'checkbox'; mine.checked = myOnly; mine.id = 'my-only'; mine.addEventListener('change', () => setMyOnly(mine.checked)); nav.append(mine, element('label', undefined, '只看我的任务')); page.append(nav);
  const form = document.createElement('form'); form.className = 'new-task-form'; const title = input('新任务标题'); const description = input('任务描述'); const create = button('创建任务'); create.type = 'submit'; const formError = element('p', 'sync-error'); form.append(title, description, create, formError); let creating = false;
  form.addEventListener('submit', (event) => { event.preventDefault(); if (creating || !title.value.trim()) { if (!title.value.trim()) formError.textContent = '请输入任务标题。'; return; } creating = true; create.disabled = true; formError.textContent = ''; void sync.createTask(title.value.trim(), description.value).then(() => { title.value = ''; description.value = ''; }).catch((error: unknown) => { formError.textContent = error instanceof Error ? error.message : '无法创建任务，请检查网络后重试。'; }).finally(() => { creating = false; create.disabled = false; }); }); page.append(form);
  if (mode === 'board') { const boardNode = element('section', 'task-board'); const groups = groupTasksByStatus(visible); for (const status of TASK_STATUSES) { const column = element('div', 'task-column'); column.append(element('h2', undefined, status)); for (const task of groups[status]) column.append(taskCard(task, sync, state.loading, openTask)); boardNode.append(column); } page.append(boardNode); } else { const listNode = element('section', 'task-list'); [...visible].sort((a, b) => b.updated_at.localeCompare(a.updated_at)).forEach((task) => listNode.append(taskCard(task, sync, state.loading, openTask))); page.append(listNode); }
  if (state.error) page.append(element('p', 'sync-error', state.error)); if (state.conflicts.length) page.append(conflictPanel(state.conflicts, sync, state.loading)); return page;
}

function taskCard(task: TaskItem, sync: WorkspaceSyncController, loading: boolean, openTask: (task: TaskItem) => void): HTMLElement { const row = element('article', 'task-row'); row.addEventListener('click', () => openTask(task)); row.append(element('h3', undefined, task.title), element('p', 'task-meta', `${task.status} | 截止: ${task.due_at ?? '未设置'} | 延期: ${task.delay_count} | 版本: ${task.status_version}`)); if (task.status === 'WAITING') row.append(element('p', 'blocked-reason', `阻塞: ${task.blocked_reason ?? '未说明'}`)); if (task.due_at && Date.parse(task.due_at) < Date.now() && task.status !== 'DONE' && task.status !== 'CANCELLED') row.append(element('p', 'overdue-warning', '已过期')); const done = button('完成', (event) => { event.stopPropagation(); void sync.transitionTask(task.id, 'DONE'); }); done.disabled = loading || task.status === 'DONE'; row.append(done); return row; }
function conflictPanel(conflicts: TaskConflict[], sync: WorkspaceSyncController, loading: boolean): HTMLElement { const panel = element('section', 'conflict-panel'); panel.append(element('h2', undefined, '待处理冲突')); for (const conflict of conflicts) { const item = element('article', 'conflict-item'); item.append(element('p', undefined, `字段: ${conflict.field}`), button('保留当前', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'current')), button('采用提议', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'proposed'))); for (const node of item.querySelectorAll('button')) node.disabled = loading; panel.append(item); } return panel; }
function element(tag: string, className?: string, text?: string): HTMLElement { const node = document.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; }
function input(placeholder: string, value = ''): HTMLInputElement { const node = document.createElement('input'); node.type = 'text'; node.placeholder = placeholder; node.setAttribute('aria-label', placeholder); node.value = value; return node; }
function button(label: string, handler?: (event: Event) => void): HTMLButtonElement { const node = document.createElement('button'); node.type = 'button'; node.textContent = label; if (handler) node.addEventListener('click', handler); return node; }
