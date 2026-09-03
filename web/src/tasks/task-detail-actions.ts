import type { TaskComment } from '../api/types';
import type { EditableTaskChanges, TaskConflict } from './task-model';

export interface TaskDetailActions {
  onTransition: (status: string, payload?: { blockedReason?: string; resumeHandlerId?: string; waitingForUserId?: string; reviewRejectionReason?: string }) => Promise<unknown>;
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
