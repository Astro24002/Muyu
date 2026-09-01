import type { PendingApproval, TaskComment, TaskItem, TaskStatus } from '../api/types';
import { isTaskQuadrant, parseTaskLabels, parseTaskLabelsInput, TASK_QUADRANTS, type EditableTaskChanges, type TaskConflict } from '../tasks/task-model';

export interface TaskDetailActions {
  onTransition: (status: string, payload?: { blockedReason?: string; resumeHandlerId?: string }) => Promise<unknown>;
  onComment: (body: string) => Promise<unknown>;
  onDelay: (date: string, reason: string, note?: string) => Promise<unknown>;
  onSave: (changes: EditableTaskChanges) => Promise<unknown>;
  onDeleteComment?: (commentId: string, baseVersion: number) => Promise<unknown>;
  onResolveConflict?: (conflictId: string, resolution: 'current' | 'proposed') => Promise<void>;
  onClose?: () => void;
  conflicts?: TaskConflict[];
  comments?: TaskComment[];
  currentUserId?: string;
  canWrite?: boolean;
  hasPendingApproval?: () => boolean;
}

export type TaskDetailHandle = {
  (): void;
  update: (task: TaskItem, conflicts: TaskConflict[], error?: string | null, comments?: TaskComment[]) => void;
};

const statuses: TaskStatus[] = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];
const delayReasons = ['NO_TIME', 'TOO_LARGE', 'NOT_WILLING', 'FORGOT', 'WAITING_PARTNER', 'INTERRUPTED', 'OTHER'];
const progressValues = [20, 40, 60, 80];

export class TaskDetailView {
  static mount(container: Element, task: TaskItem, members: Array<{ user_id: string; member_slot: number }>, actions: TaskDetailActions): TaskDetailHandle {
    let currentTask = task;
    let currentComments = actions.comments ?? [];
    let disposed = false;
    let busy = false;
    const activeActions = new Set<string>();
    let pendingMessage: string | null = null;
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
    for (const { user_id: id } of members) {
      const option = document.createElement('option');
      option.value = id;
      option.textContent = id;
      option.selected = id === (task.resume_handler_id ?? task.current_handler_id);
      resumeHandler.append(option);
    }
    const quadrant = document.createElement('select');
    quadrant.setAttribute('aria-label', '四象限');
    for (const value of TASK_QUADRANTS) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value || '未设置';
      option.selected = value === task.quadrant;
      quadrant.append(option);
    }
    const labelsInput = input('标签', parseTaskLabels(task.labels ?? []).join(', '));
    const labelsDisplay = document.createElement('div');
    labelsDisplay.className = 'task-labels';
    labelsDisplay.setAttribute('aria-label', '任务标签');
    const progress = document.createElement('select');
    progress.setAttribute('aria-label', '进度');
    for (const value of progressValues) {
      const option = document.createElement('option');
      option.value = String(value);
      option.textContent = `${value}%`;
      option.selected = value === task.progress;
      progress.append(option);
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
    const metadata = document.createElement('div');
    metadata.className = 'task-metadata';
    const pendingNotice = message('pending-approval', '');
    const progressField = field('进度', progress);
    const commentsPanel = document.createElement('section');
    commentsPanel.className = 'task-comments';
    commentsPanel.setAttribute('aria-label', '评论历史');
    dialog.append(
      heading('任务详情'),
      metadata,
      pendingNotice,
      field('标题', title),
      field('描述', description),
      save,
      field('四象限', quadrant),
      field('标签', labelsInput),
      labelsDisplay,
      field('状态', status),
      field('阻塞原因', blockedReason),
      field('恢复负责人', resumeHandler),
      transition,
      progressField,
      field('评论', comment),
      commentButton,
      commentsPanel,
      field('新截止时间', due),
      field('原因', reason),
      field('说明', note),
      delayButton,
      error,
      close,
    );

    let conflictPanel: HTMLElement | undefined;
    const isOwner = () => !actions.currentUserId || actions.currentUserId === currentTask.current_handler_id;
    const canWrite = () => actions.canWrite !== false;
    const renderLabels = () => {
      labelsDisplay.replaceChildren();
      for (const value of parseTaskLabelsInput(labelsInput.value)) labelsDisplay.append(message('task-label', value));
    };
    const renderMetadata = () => {
      metadata.replaceChildren(
        textNode(currentTask.task_number ? `任务编号：${currentTask.task_number}` : '任务编号：未分配'),
        textNode(`负责人：${currentTask.current_handler_id}`),
        textNode(isOwner() ? '当前用户是任务负责人' : '协作成员，修改将提交审批'),
      );
      save.textContent = isOwner() ? '保存' : '提交审批';
      transition.textContent = isOwner() ? '更新状态' : '提交审批';
      const pending = Boolean(pendingMessage) || Boolean(actions.hasPendingApproval?.());
      pendingNotice.hidden = !pending;
      pendingNotice.textContent = pending ? pendingMessage ?? '等待负责人审批' : '';
      progressField.hidden = currentTask.status !== 'IN_PROGRESS';
      if (!dirty.has('quadrant')) quadrant.value = isTaskQuadrant(currentTask.quadrant) ? currentTask.quadrant : '';
      if (!dirty.has('labels')) labelsInput.value = parseTaskLabels(currentTask.labels ?? []).join(', ');
      if (!dirty.has('progress')) progress.value = String(currentTask.progress ?? 20);
      const protectedControls = [save, quadrant, labelsInput, status, blockedReason, resumeHandler, transition];
      for (const control of protectedControls) control.disabled = !canWrite();
      // The server has no pending delay response, so only the owner may delay.
      commentButton.disabled = !canWrite();
      delayButton.disabled = !canWrite() || !isOwner();
      renderLabels();
    };

    const renderComments = () => {
      commentsPanel.replaceChildren();
      if (currentComments.length === 0) {
        commentsPanel.append(message('comments-empty', '暂无评论'));
        return;
      }
      const sorted = [...currentComments].sort((a, b) => (a.created_at ?? '').localeCompare(b.created_at ?? ''));
      for (const item of sorted) {
        const row = document.createElement('article');
        row.className = item.deleted_at ? 'comment-item comment-tombstone' : 'comment-item';
        row.dataset.commentId = item.id;
        if (item.deleted_at) {
          row.append(message('comment-body', '评论已删除'), message('comment-meta', `删除时间：${item.deleted_at}`));
        } else {
          row.append(message('comment-body', item.body), message('comment-meta', `作者：${item.author_user_id}`));
          const viewerId = actions.currentUserId ?? currentTask.current_handler_id;
          const canDelete = canWrite() && Boolean(actions.onDeleteComment)
            && (item.author_user_id === viewerId || currentTask.current_handler_id === viewerId);
          if (canDelete) {
            const remove = actionButton('删除评论', 'delete-comment');
            remove.dataset.commentId = item.id;
            remove.disabled = busy;
            remove.addEventListener('click', () => void run(async () => {
              const result = await actions.onDeleteComment!(item.id, item.version);
              if (isPendingApproval(result)) pendingMessage = '评论删除等待作者审批';
            }, 'delete-comment'));
            row.append(remove);
          }
        }
        commentsPanel.append(row);
      }
    };

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
      dialog.dataset.busy = value ? 'true' : 'false';
      renderComments();
    };
    const run = (operation: () => Promise<unknown>, action = 'operation'): Promise<void> => {
      if (activeActions.has(action)) return Promise.resolve();
      activeActions.add(action);
      setBusy(true);
      error.textContent = '';
      let result: Promise<unknown>;
      try {
        result = operation();
      } catch (cause) {
        result = Promise.reject(cause);
      }
      return result
        .catch((cause: unknown) => {
          if (!disposed) error.textContent = cause instanceof Error ? cause.message : '操作失败，请重试。';
        })
        .finally(() => {
          if (disposed) return;
          activeActions.delete(action);
          setBusy(activeActions.size > 0);
          renderMetadata();
          renderComments();
          if (pendingMessage) {
            error.textContent = pendingMessage;
            renderMetadata();
            pendingMessage = null;
          }
        })
        .then(() => undefined);
    };
    const resolve = (id: string, choice: 'current' | 'proposed') =>
      actions.onResolveConflict ? run(() => actions.onResolveConflict!(id, choice), 'conflict') : Promise.resolve();

    const updateIfClean = (fieldName: string, control: HTMLInputElement | HTMLTextAreaElement, value: string) => {
      if (!dirty.has(fieldName)) control.value = value;
    };
    title.addEventListener('input', () => dirty.add('title'));
    description.addEventListener('input', () => dirty.add('description'));
    blockedReason.addEventListener('input', () => dirty.add('blockedReason'));
    resumeHandler.addEventListener('change', () => dirty.add('resumeHandler'));
    status.addEventListener('change', () => dirty.add('status'));
    quadrant.addEventListener('change', () => dirty.add('quadrant'));
    labelsInput.addEventListener('input', () => { dirty.add('labels'); renderLabels(); });
    progress.addEventListener('change', () => dirty.add('progress'));

    const handle = (() => {
      disposed = true;
      dialog.remove();
    }) as TaskDetailHandle;
    handle.update = (nextTask, conflicts, nextError, comments) => {
      if (disposed) return;
      currentTask = nextTask;
      if (comments) currentComments = comments;
      updateIfClean('title', title, nextTask.title);
      updateIfClean('description', description, nextTask.description);
      updateIfClean('blockedReason', blockedReason, nextTask.blocked_reason ?? '');
      if (!dirty.has('status')) status.value = nextTask.status;
      if (!dirty.has('resumeHandler')) resumeHandler.value = nextTask.resume_handler_id ?? nextTask.current_handler_id;
      if (!dirty.has('labels')) labelsInput.value = parseTaskLabels(nextTask.labels ?? []).join(', ');
      error.textContent = nextError ?? '';
      renderMetadata();
      renderComments();
      renderConflicts(conflicts);
    };

    save.addEventListener('click', () => void run(() => {
      if (!isTaskQuadrant(currentTask.quadrant)) {
        error.textContent = '任务必须设置有效四象限。';
        return Promise.resolve();
      }
      const changes: EditableTaskChanges = { title: title.value.trim(), description: description.value };
      const nextQuadrant = quadrant.value;
      if (!isTaskQuadrant(nextQuadrant)) {
        error.textContent = '请选择有效四象限。';
        return Promise.resolve();
      }
      if (nextQuadrant !== currentTask.quadrant) changes.quadrant = nextQuadrant;
      const nextLabels = parseTaskLabelsInput(labelsInput.value);
      const currentLabels = parseTaskLabels(currentTask.labels ?? []);
      if (nextLabels.length !== currentLabels.length || nextLabels.some((value, index) => value !== currentLabels[index])) changes.labels = nextLabels;
      if (currentTask.status === 'IN_PROGRESS') {
        const nextProgress = Number(progress.value);
        if (nextProgress !== (currentTask.progress ?? 20)) changes.progress = nextProgress;
      }
      const result = actions.onSave(changes);
      void result.then((value) => { if (isPendingApproval(value)) pendingMessage = '等待负责人审批'; }, () => undefined);
      return result;
    }, 'save'));
    transition.addEventListener('click', () => void run(() => {
      const blocked = blockedReason.value.trim();
      const handler = resumeHandler.value;
      if (status.value === 'WAITING' && (!blocked || !handler)) {
        error.textContent = '进入等待状态需要阻塞原因和恢复负责人。';
        return Promise.resolve();
      }
      const payload = {
        ...(blocked ? { blockedReason: blocked } : {}),
        ...(handler && (status.value === 'WAITING' || currentTask.status === 'WAITING') ? { resumeHandlerId: handler } : {}),
      };
      const result = Object.keys(payload).length === 0
        ? actions.onTransition(status.value)
        : actions.onTransition(status.value, payload);
      return result.then((value) => { if (isPendingApproval(value)) pendingMessage = '等待负责人审批'; });
    }, 'transition'));
    commentButton.addEventListener('click', () => {
      const body = comment.value.trim();
      if (!body) return;
      void run(async () => {
        await actions.onComment(body);
        comment.value = '';
      }, 'comment');
    });
    delayButton.addEventListener('click', () => {
      if (!due.value) return;
      void run(async () => { await actions.onDelay(new Date(due.value).toISOString(), reason.value, note.value.trim() || undefined); }, 'delay');
    });
    close.addEventListener('click', () => {
      handle();
      actions.onClose?.();
    });

    container.append(dialog);
    renderMetadata();
    renderComments();
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

function message(className: string, value: string): HTMLElement {
  const node = document.createElement('p');
  node.className = className;
  node.textContent = value;
  return node;
}

function actionButton(label: string, action: string): HTMLButtonElement {
  const node = document.createElement('button');
  node.type = 'button';
  node.textContent = label;
  node.dataset.action = action;
  return node;
}

function isPendingApproval(value: unknown): value is PendingApproval {
  return Boolean(value && typeof value === 'object' && 'pending' in value && 'approval_request' in value);
}
