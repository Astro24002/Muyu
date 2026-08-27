import type { TaskItem, TaskStatus } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from '../tasks/task-model';

export interface TaskDetailActions {
  onTransition: (status: string, payload?: { blockedReason?: string; resumeHandlerId?: string }) => Promise<void>;
  onComment: (body: string) => Promise<void>;
  onDelay: (date: string, reason: string, note?: string) => Promise<void>;
  onSave: (changes: EditableTaskChanges) => Promise<void>;
  onResolveConflict?: (conflictId: string, resolution: 'current' | 'proposed') => Promise<void>;
  conflicts?: TaskConflict[];
}

const statuses: TaskStatus[] = ['TODO', 'IN_PROGRESS', 'WAITING', 'DONE', 'CANCELLED'];
const delayReasons = ['NO_TIME', 'TOO_LARGE', 'NOT_WILLING', 'FORGOT', 'WAITING_PARTNER', 'INTERRUPTED', 'OTHER'];

export class TaskDetailView {
  static mount(container: Element, task: TaskItem, _members: Array<{ user_id: string; member_slot: number }>, actions: TaskDetailActions): () => void {
    const dialog = document.createElement('section');
    dialog.className = 'task-detail';
    dialog.setAttribute('aria-label', '任务详情');
    const error = document.createElement('p'); error.className = 'sync-error'; error.setAttribute('role', 'alert');
    const title = input('标题', task.title);
    const description = document.createElement('textarea'); description.setAttribute('aria-label', '描述'); description.value = task.description;
    const save = actionButton('保存', 'save');
    const status = document.createElement('select'); status.setAttribute('aria-label', '状态');
    for (const value of statuses) { const option = document.createElement('option'); option.value = value; option.textContent = value; option.selected = value === task.status; status.append(option); }
    const transition = actionButton('更新状态', 'transition');
    const blockedReason = input('阻塞原因', task.blocked_reason ?? '');
    const comment = input('评论'); const commentButton = actionButton('添加评论', 'comment');
    const due = input('延期至 (ISO 时间)'); due.type = 'datetime-local'; const reason = document.createElement('select'); reason.setAttribute('aria-label', '延期原因');
    for (const value of delayReasons) { const option = document.createElement('option'); option.value = value; option.textContent = value; reason.append(option); }
    const note = input('延期说明'); const delayButton = actionButton('提交延期', 'delay');
    const close = actionButton('关闭', 'close');
    dialog.append(heading('任务详情'), field('标题', title), field('描述', description), save, field('状态', status), field('阻塞原因', blockedReason), transition, field('评论', comment), commentButton, field('新截止时间', due), field('原因', reason), field('说明', note), delayButton);
    const conflicts = actions.conflicts ?? [];
    if (conflicts.length) {
      const panel = document.createElement('section'); panel.className = 'conflict-panel'; panel.append(heading('待处理冲突'));
      for (const conflict of conflicts.filter((item) => item.task_id === task.id)) {
        const item = document.createElement('article'); item.className = 'conflict-item';
        item.append(textNode(`${conflict.field}: 当前值 ${String(conflict.current ?? '')} / 提议值 ${String(conflict.proposed ?? '')}`));
        const keep = actionButton('保留当前', 'resolve-current'); keep.addEventListener('click', () => void resolve(conflict.id, 'current'));
        const accept = actionButton('采用提议', 'resolve-proposed'); accept.addEventListener('click', () => void resolve(conflict.id, 'proposed'));
        item.append(keep, accept); panel.append(item);
      }
      dialog.append(panel);
    }
    dialog.append(error, close); container.append(dialog);
    let disposed = false; let busy = false;
    const setBusy = (value: boolean) => { busy = value; for (const button of dialog.querySelectorAll('button')) button.disabled = value; };
    const run = async (operation: () => Promise<void>) => { if (busy) return; setBusy(true); error.textContent = ''; try { await operation(); } catch (cause) { if (!disposed) error.textContent = cause instanceof Error ? cause.message : '操作失败，请重试。'; } finally { if (!disposed) setBusy(false); } };
    save.addEventListener('click', () => void run(() => actions.onSave({ title: title.value.trim(), description: description.value })));
    transition.addEventListener('click', () => void run(() => {
      const reason = blockedReason.value.trim();
      return reason ? actions.onTransition(status.value, { blockedReason: reason }) : actions.onTransition(status.value);
    }));
    commentButton.addEventListener('click', () => { const body = comment.value.trim(); if (!body) return; void run(async () => { await actions.onComment(body); comment.value = ''; }); });
    delayButton.addEventListener('click', () => { if (!due.value) return; void run(() => actions.onDelay(new Date(due.value).toISOString(), reason.value, note.value.trim() || undefined)); });
    const resolve = (id: string, choice: 'current' | 'proposed') => actions.onResolveConflict ? run(() => actions.onResolveConflict!(id, choice)) : Promise.resolve();
    const cleanup = () => { disposed = true; dialog.remove(); };
    close.addEventListener('click', cleanup);
    return cleanup;
  }
}

function input(label: string, value = ''): HTMLInputElement { const node = document.createElement('input'); node.type = 'text'; node.setAttribute('aria-label', label); node.placeholder = label; node.value = value; return node; }
function field(label: string, control: HTMLElement): HTMLElement { const wrapper = document.createElement('label'); wrapper.className = 'task-field'; wrapper.append(textNode(label), control); return wrapper; }
function heading(label: string): HTMLElement { const node = document.createElement('h2'); node.textContent = label; return node; }
function textNode(value: string): Text { return document.createTextNode(value); }
function actionButton(label: string, action: string): HTMLButtonElement { const node = document.createElement('button'); node.type = 'button'; node.textContent = label; node.dataset.action = action; return node; }
