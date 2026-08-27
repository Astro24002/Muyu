import type { TaskItem, TaskStatus } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';

export interface TaskDetailActions {
  onTransition: (status: string, payload?: { blockedReason?: string; resumeHandlerId?: string }) => Promise<void>;
  onComment: (body: string) => Promise<void>;
  onDelay: (date: string, reason: string, note?: string) => Promise<void>;
  onSave: (changes: EditableTaskChanges) => Promise<void>;
  onResolveConflict?: (conflictId: string, resolution: 'current' | 'proposed') => Promise<void>;
  onClose?: () => void;
  conflicts?: TaskConflict[];
}

export type TaskDetailHandle = {
  (): void;
  update: (task: TaskItem, conflicts: TaskConflict[], error?: string | null) => void;
};

const statuses: TaskStatus[] = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];
const delayReasons = ['NO_TIME', 'TOO_LARGE', 'NOT_WILLING', 'FORGOT', 'WAITING_PARTNER', 'INTERRUPTED', 'OTHER'];

export class TaskDetailView {
  static mount(container: Element, task: TaskItem, members: Array<{ user_id: string; member_slot: number }>, actions: TaskDetailActions): TaskDetailHandle {
    let currentTask = task;
    let disposed = false;
    let busy = false;
    const dirty = new Set<string>();
    const dialog = document.createElement('section');
    dialog.className = 'task-detail';
    dialog.setAttribute('aria-label', '任务详情');
    const error = document.createElement('p');
    error.className = 'sync-error';
    error.setAttribute('role', 'alert');
    const title = input('标题', task.title);
    const description = document.createElement('textarea');
    description.setAttribute('aria-label', '描述');
    description.value = task.description;
    const save = actionButton('保存', 'save');
    const status = document.createElement('select');
    status.setAttribute('aria-label', '状态');
    for (const value of statuses) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      option.selected = value === task.status;
      status.append(option);
    }
    const transition = actionButton('更新状态', 'transition');
    const blockedReason = input('阻塞原因', task.blocked_reason ?? '');
    const resumeHandler = document.createElement('select');
    resumeHandler.setAttribute('aria-label', '恢复负责人');
    const activeMembers = new Set(members.map((member) => member.user_id));
    const handlerIds = task.assignee_ids.filter((id) => activeMembers.size === 0 || activeMembers.has(id));
    for (const id of handlerIds) {
      const option = document.createElement('option');
      option.value = id;
      option.textContent = id;
      option.selected = id === (task.resume_handler_id ?? task.current_handler_id);
      resumeHandler.append(option);
    }
    const comment = input('评论');
    const commentButton = actionButton('添加评论', 'comment');
    const due = input('延期至 (ISO 时间)');
    due.type = 'datetime-local';
    const reason = document.createElement('select');
    reason.setAttribute('aria-label', '延期原因');
    for (const value of delayReasons) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      reason.append(option);
    }
    const note = input('延期说明');
    const delayButton = actionButton('提交延期', 'delay');
    const close = actionButton('关闭', 'close');
    dialog.append(
      heading('任务详情'),
      field('标题', title),
      field('描述', description),
      save,
      field('状态', status),
      field('阻塞原因', blockedReason),
      field('恢复负责人', resumeHandler),
      transition,
      field('评论', comment),
      commentButton,
      field('新截止时间', due),
      field('原因', reason),
      field('说明', note),
      delayButton,
      error,
      close,
    );

    let conflictPanel: HTMLElement | undefined;
    const renderConflicts = (conflicts: TaskConflict[]) => {
      conflictPanel?.remove();
      conflictPanel = undefined;
      const taskConflicts = conflicts.filter((item) => item.task_id === currentTask.id);
      if (taskConflicts.length === 0) return;
      conflictPanel = document.createElement('section');
      conflictPanel.className = 'conflict-panel';
      conflictPanel.append(heading('待处理冲突'));
      for (const conflict of taskConflicts) {
        const item = document.createElement('article');
        item.className = 'conflict-item';
        item.append(textNode(`${conflict.field}: 当前值 ${String(conflict.current ?? '')} / 提议值 ${String(conflict.proposed ?? '')}`));
        const keep = actionButton('保留当前', 'resolve-current');
        keep.addEventListener('click', () => void resolve(conflict.id, 'current'));
        const accept = actionButton('采用提议', 'resolve-proposed');
        accept.addEventListener('click', () => void resolve(conflict.id, 'proposed'));
        item.append(keep, accept);
        conflictPanel.append(item);
      }
      dialog.insertBefore(conflictPanel, error);
    };

    const setBusy = (value: boolean) => {
      busy = value;
      for (const button of dialog.querySelectorAll('button')) button.disabled = value;
    };
    const run = async (operation: () => Promise<void>) => {
      if (busy) return;
      setBusy(true);
      error.textContent = '';
      try {
        await operation();
      } catch (cause) {
        if (!disposed) error.textContent = cause instanceof Error ? cause.message : '操作失败，请重试。';
      } finally {
        if (!disposed) setBusy(false);
      }
    };
    const resolve = (id: string, choice: 'current' | 'proposed') =>
      actions.onResolveConflict ? run(() => actions.onResolveConflict!(id, choice)) : Promise.resolve();

    const updateIfClean = (fieldName: string, control: HTMLInputElement | HTMLTextAreaElement, value: string) => {
      if (!dirty.has(fieldName)) control.value = value;
    };
    title.addEventListener('input', () => dirty.add('title'));
    description.addEventListener('input', () => dirty.add('description'));
    blockedReason.addEventListener('input', () => dirty.add('blockedReason'));
    resumeHandler.addEventListener('change', () => dirty.add('resumeHandler'));
    status.addEventListener('change', () => dirty.add('status'));

    const handle = (() => {
      disposed = true;
      dialog.remove();
    }) as TaskDetailHandle;
    handle.update = (nextTask, conflicts, nextError) => {
      if (disposed) return;
      currentTask = nextTask;
      updateIfClean('title', title, nextTask.title);
      updateIfClean('description', description, nextTask.description);
      updateIfClean('blockedReason', blockedReason, nextTask.blocked_reason ?? '');
      if (!dirty.has('status')) status.value = nextTask.status;
      if (!dirty.has('resumeHandler')) resumeHandler.value = nextTask.resume_handler_id ?? nextTask.current_handler_id;
      error.textContent = nextError ?? '';
      renderConflicts(conflicts);
    };

    save.addEventListener('click', () => void run(() => actions.onSave({ title: title.value.trim(), description: description.value })));
    transition.addEventListener('click', () => void run(async () => {
      const blocked = blockedReason.value.trim();
      const handler = resumeHandler.value;
      if (status.value === 'WAITING' && (!blocked || !handler)) {
        error.textContent = '进入等待状态需要阻塞原因和恢复负责人。';
        return;
      }
      const payload = {
        ...(blocked ? { blockedReason: blocked } : {}),
        ...(handler && (status.value === 'WAITING' || currentTask.status === 'WAITING') ? { resumeHandlerId: handler } : {}),
      };
      if (Object.keys(payload).length === 0) {
        await actions.onTransition(status.value);
      } else {
        await actions.onTransition(status.value, payload);
      }
    }));
    commentButton.addEventListener('click', () => {
      const body = comment.value.trim();
      if (!body) return;
      void run(async () => {
        await actions.onComment(body);
        comment.value = '';
      });
    });
    delayButton.addEventListener('click', () => {
      if (!due.value) return;
      void run(() => actions.onDelay(new Date(due.value).toISOString(), reason.value, note.value.trim() || undefined));
    });
    close.addEventListener('click', () => {
      handle();
      actions.onClose?.();
    });

    container.append(dialog);
    renderConflicts(actions.conflicts ?? []);
    return handle;
  }
}

function input(label: string, value = ''): HTMLInputElement {
  const node = document.createElement('input');
  node.type = 'text';
  node.setAttribute('aria-label', label);
  node.placeholder = label;
  node.value = value;
  return node;
}

function field(label: string, control: HTMLElement): HTMLElement {
  const wrapper = document.createElement('label');
  wrapper.className = 'task-field';
  wrapper.append(textNode(label), control);
  return wrapper;
}

function heading(label: string): HTMLElement {
  const node = document.createElement('h2');
  node.textContent = label;
  return node;
}

function textNode(value: string): Text {
  return document.createTextNode(value);
}

function actionButton(label: string, action: string): HTMLButtonElement {
  const node = document.createElement('button');
  node.type = 'button';
  node.textContent = label;
  node.dataset.action = action;
  return node;
}
