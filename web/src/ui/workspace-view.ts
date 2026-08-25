import type { TaskItem } from '../api/types';
import type { TaskConflict } from '../tasks/task-model';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';

export class WorkspaceView {
  static mount(root: Element, sync: WorkspaceSyncController, onLogout: () => void): () => void {
    let logoutNotified = false;
    const render = (state: WorkspaceSyncState) => {
      if (state.authRequired && !logoutNotified) {
        logoutNotified = true;
        onLogout();
        return;
      }
      root.replaceChildren(buildWorkspace(state, sync, onLogout));
    };
    const unsubscribe = sync.subscribe(render);
    render(sync.state);
    return () => unsubscribe();
  }
}

function buildWorkspace(state: WorkspaceSyncState, sync: WorkspaceSyncController, onLogout: () => void): HTMLElement {
  const page = element('main', 'workspace-page');
  const header = element('header', 'workspace-header');
  const identity = element('div');
  identity.append(element('h1', undefined, 'Muyu'));
  identity.append(element('p', 'workspace-cursor', `游标: ${state.cursor}`));
  header.append(identity);

  const controls = element('div', 'workspace-controls');
  if (state.stale) controls.append(element('span', 'sync-warning', '数据可能已过期'));
  if (state.error) controls.append(element('span', 'sync-error', state.error));
  const refresh = button('刷新', () => void sync.refresh());
  refresh.disabled = state.loading;
  controls.append(refresh, button('退出登录', onLogout));
  header.append(controls);
  page.append(header);

  const newTask = element('form', 'new-task-form') as HTMLFormElement;
  const title = input('新任务标题', 'text');
  title.required = true;
  const description = input('任务描述', 'text');
  const create = button('创建任务');
  create.type = 'submit';
  create.disabled = state.loading;
  newTask.append(title, description, create);
  newTask.addEventListener('submit', (event) => {
    event.preventDefault();
    void sync.createTask(title.value.trim(), description.value).then(() => {
      title.value = '';
      description.value = '';
    });
  });
  page.append(newTask);

  const taskList = element('section', 'task-list');
  taskList.setAttribute('aria-label', '任务列表');
  for (const task of state.snapshot?.tasks ?? []) taskList.append(taskRow(task, sync, state.loading));
  if (!state.snapshot && !state.loading) taskList.append(element('p', undefined, '尚未加载工作区。'));
  page.append(taskList);

  if (state.conflicts.length > 0) page.append(conflictPanel(state.conflicts, sync, state.loading));
  return page;
}

function taskRow(task: TaskItem, sync: WorkspaceSyncController, loading: boolean): HTMLElement {
  const row = element('article', 'task-row');
  const metadata = element('p', 'task-meta', `${task.status} | 截止: ${task.due_at ?? '未设置'} | 版本: ${task.version}`);
  const title = input('任务标题', 'text', task.title);
  title.className = 'task-title-input';
  title.required = true;
  const description = document.createElement('textarea');
  description.value = task.description;
  description.placeholder = '任务描述';
  description.setAttribute('aria-label', `${task.title} 的任务描述`);
  const save = button('保存', () => {
    const changes: { title?: string; description?: string } = {};
    if (title.value !== task.title) changes.title = title.value;
    if (description.value !== task.description) changes.description = description.value;
    if (Object.keys(changes).length > 0) void sync.patchTask(task.id, changes);
  });
  save.disabled = loading;
  row.append(title, metadata, description, save);
  return row;
}

function conflictPanel(conflicts: TaskConflict[], sync: WorkspaceSyncController, loading: boolean): HTMLElement {
  const panel = element('section', 'conflict-panel');
  panel.append(element('h2', undefined, '待处理冲突'));
  for (const conflict of conflicts) {
    const item = element('article', 'conflict-item');
    item.append(element('p', undefined, `字段: ${conflict.field}`));
    item.append(element('p', undefined, `当前值: ${displayValue(conflict.current)}`));
    item.append(element('p', undefined, `提议值: ${displayValue(conflict.proposed)}`));
    const keep = button('保留当前', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'current'));
    const adopt = button('采用提议', () => void sync.resolveConflict(conflict.task_id, conflict.id, 'proposed'));
    keep.disabled = loading;
    adopt.disabled = loading;
    item.append(keep, adopt);
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

function input(placeholder: string, type: string, value = ''): HTMLInputElement {
  const node = document.createElement('input');
  node.type = type;
  node.placeholder = placeholder;
  node.setAttribute('aria-label', placeholder);
  node.value = value;
  return node;
}

function button(label: string, handler?: () => void): HTMLButtonElement {
  const node = document.createElement('button');
  node.type = 'button';
  node.textContent = label;
  if (handler) node.addEventListener('click', handler);
  return node;
}

function displayValue(value: unknown): string {
  if (value === null || value === undefined) return '未设置';
  return typeof value === 'string' ? value : JSON.stringify(value);
}
