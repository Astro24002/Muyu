import type { TaskItem } from '../api/types';
import type { EditableTaskChanges } from '../tasks/task-model';

export interface TaskDetailActions { onTransition: (status: string, payload?: { blockedReason?: string; resumeHandlerId?: string }) => Promise<void>; onComment: (body: string) => Promise<void>; onDelay: (date: string, reason: string, note?: string) => Promise<void>; onSave: (changes: EditableTaskChanges) => Promise<void> }

export class TaskDetailView {
  static mount(container: Element, task: TaskItem, _members: Array<{ user_id: string; member_slot: number }>, actions: TaskDetailActions): () => void {
    const dialog = document.createElement('section'); dialog.className = 'task-detail'; const title = document.createElement('input'); title.value = task.title; const description = document.createElement('textarea'); description.value = task.description; const save = document.createElement('button'); save.textContent = '保存'; save.onclick = () => void actions.onSave({ title: title.value, description: description.value }); const done = document.createElement('button'); done.textContent = '完成'; done.onclick = () => void actions.onTransition('DONE'); const close = document.createElement('button'); close.textContent = '关闭'; close.onclick = () => cleanup(); dialog.append(title, description, save, done, close); container.append(dialog); const cleanup = () => dialog.remove(); return cleanup;
  }
}
