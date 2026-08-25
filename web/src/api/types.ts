export interface WebChallenge { challenge_id: string; qr_payload: string; origin: string; safety_code: string; expires_at: string }
export type WebChallengeLifecycle = 'PENDING' | 'APPROVED' | 'CONSUMED' | 'EXPIRED' | 'REVOKED';
export interface WebChallengeStatus { challenge_id: string; status: WebChallengeLifecycle; expires_at: string }
export interface WebSessionExchange { status: 'authenticated'; expires_at: string }
export interface TaskItem {
  id: string; workspace_id: string; parent_task_id: string | null; title: string; description: string;
  due_at: string | null; status: string; current_handler_id: string; blocked_reason: string | null;
  blocked_since: string | null; resume_handler_id: string | null; waiting_for_user_id: string | null;
  planned_start_at: string | null; estimated_minutes: number | null; completed_at: string | null;
  created_by: string; created_at: string; updated_at: string; assignee_ids: string[];
  delay_count: number; total_delay_minutes: number; version: number; field_versions: Record<string, number>;
  lifecycle_version: number; deleted_at: string | null; [key: string]: unknown;
}
export interface WorkspaceSnapshot {
  workspace_id: string; workspace: { id: string; name: string; status: string };
  members: Array<{ user_id: string; member_slot: number }>; tasks: TaskItem[];
  conflicts: Array<Record<string, unknown>>; cursor: number;
}
export interface WorkspaceChange { cursor: number; resource_type: string; resource_id: string; action: string; operation_id: string | null; resource: TaskItem | null }
export interface WorkspaceChanges { workspace_id: string; cursor: number; changes: WorkspaceChange[] }
