export interface WebChallenge { challenge_id: string; qr_payload: string; origin: string; safety_code: string; expires_at: string }
export type WebChallengeLifecycle = 'PENDING' | 'APPROVED' | 'CONSUMED' | 'EXPIRED' | 'REVOKED';
export interface WebChallengeStatus { challenge_id: string; status: WebChallengeLifecycle; expires_at: string }
export interface WebSessionExchange { status: 'authenticated'; expires_at: string }
export type WebSessionStatus = 'ACTIVE' | 'EXPIRED' | 'REVOKED';
export interface WebSessionSummary {
  id: string;
  status: WebSessionStatus;
  origin: string | null;
  created_at: string;
  expires_at: string;
}
export interface WebSessionRevokeAllResult { revoked_count: number }
export type CanonicalTaskStatus = 'TODO' | 'IN_PROGRESS' | 'BLOCKED' | 'REVIEW' | 'DONE' | 'CANCELLED';
/** Legacy values remain readable at the API/test-fixture boundary only. */
export type TaskStatus = CanonicalTaskStatus | 'WAITING' | 'COMPLETED';
export type TaskQuadrant = 'Q1' | 'Q2' | 'Q3' | 'Q4';
export type TaskApprovalRequestType =
  | 'TASK_UPDATE'
  | 'QUADRANT_UPDATE'
  | 'STATUS_UPDATE'
  | 'TASK_DELETE'
  | 'TASK_RESTORE'
  | 'COMMENT_DELETE'
  | 'HANDLER_TRANSFER';
export type TaskApprovalRequestStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'CONFLICTED' | 'CANCELLED';
export type ApprovalRequestType = TaskApprovalRequestType;
export type ApprovalRequestStatus = TaskApprovalRequestStatus;

export interface TaskItem {
  id: string; workspace_id: string; parent_task_id: string | null; title: string; description: string;
  due_at: string | null; status: TaskStatus; current_handler_id: string; blocked_reason: string | null;
  blocked_since: string | null; resume_handler_id: string | null; waiting_for_user_id: string | null;
  reviewer_user_id?: string | null; review_submitted_at?: string | null; reviewed_at?: string | null; review_rejection_reason?: string | null;
  planned_start_at: string | null; estimated_minutes: number | null; completed_at: string | null;
  created_by: string; created_at: string; updated_at: string;
  delay_count: number; total_delay_minutes: number; version: number; status_version: number; field_versions: Record<string, number>;
  lifecycle_version: number; deleted_at: string | null;
  task_number?: string;
  quadrant: TaskQuadrant;
  labels: string[];
  progress?: number | null;
  [key: string]: unknown;
}

export interface TaskComment {
  id: string;
  workspace_id: string;
  task_id: string;
  author_user_id: string;
  body: string;
  version: number;
  deleted_at: string | null;
  deleted_by: string | null;
  created_at: string | null;
}

export interface ActivityEvent {
  kind: 'operation' | 'comment' | 'delay' | string;
  id: string;
  created_at: string;
  operation_type?: string;
  body?: string;
  author_user_id?: string;
  actor_user_id?: string;
  reason?: string;
  note?: string;
  new_due_at?: string;
  delay_duration_minutes?: number;
  request_id?: string;
  [key: string]: unknown;
}

export interface TaskApprovalRequest {
  id: string;
  workspace_id: string;
  task_id: string;
  comment_id: string | null;
  requester_id: string;
  approver_id: string;
  request_type: TaskApprovalRequestType;
  proposed_changes: Record<string, unknown>;
  base_field_versions: Record<string, number>;
  request_id: string;
  status: TaskApprovalRequestStatus;
  created_at: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  rejection_reason: string | null;
  resolved_cursor: number | null;
}

export interface PendingApproval {
  pending: true;
  approval_request: TaskApprovalRequest;
  cursor: number;
}

export interface ApprovalActionResult {
  approval_request: TaskApprovalRequest;
  task?: TaskItem;
  comment?: TaskComment;
  cursor?: number | null;
}

export interface WorkspaceSnapshot {
  workspace_id: string; workspace: { id: string; name: string | null; status: string };
  members: Array<{ user_id: string; display_name?: string; member_slot: number; membership_status?: string; status?: string }>; tasks: TaskItem[];
  conflicts: Array<Record<string, unknown>>; cursor: number;
  viewer_user_id?: string | null;
  comments?: TaskComment[];
  approval_requests?: TaskApprovalRequest[];
}

export interface WorkspaceChange {
  cursor: number;
  resource_type: 'task' | 'task_conflict' | 'approval_request' | 'comment' | string;
  resource_id: string;
  action: string;
  operation_id: string | null;
  resource: TaskItem | TaskApprovalRequest | TaskComment | Record<string, unknown> | null;
}
export interface WorkspaceChanges { workspace_id: string; cursor: number; changes: WorkspaceChange[] }
