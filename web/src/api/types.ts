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
  | 'TASK_INVITATION'
  | 'TASK_UPDATE'
  | 'QUADRANT_UPDATE'
  | 'STATUS_UPDATE'
  | 'TASK_DELETE'
  | 'TASK_RESTORE'
  | 'COMMENT_DELETE'
  | 'HANDLER_TRANSFER'
  | 'CLASSIFICATION_CREATE';
export type TaskApprovalRequestStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'CONFLICTED' | 'CANCELLED';
export type ApprovalRequestType = TaskApprovalRequestType;
export type ApprovalRequestStatus = TaskApprovalRequestStatus;

export interface TaskItem {
  id: string; workspace_id: string; parent_task_id: string | null; title: string; description: string;
  next_step_text?: string | null;
  acceptance_criteria?: string | null;
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

export interface HomeTaskSection {
  items: TaskItem[];
  has_more: boolean;
}

export interface HomeApprovalItem {
  approval_request: TaskApprovalRequest;
  task: TaskItem | null;
}

export interface HomeApprovalSection {
  items: HomeApprovalItem[];
  has_more: boolean;
}

export interface HomeWeek {
  timezone: string;
  start: string;
  end: string;
}

export interface HomeEntryCounts {
  needs_me: number;
  waiting_on_other: number;
  due_this_week: number;
  due_soon?: number;
}

export interface HomeEntries {
  needs_me: HomeApprovalSection;
  waiting_on_other: HomeApprovalSection;
  due_this_week: HomeTaskSection;
  due_soon?: HomeTaskSection;
}

export interface HomeMoment {
  /** Canonical section names. */
  blocked?: HomeTaskSection;
  mine?: HomeTaskSection;
  other?: HomeTaskSection;
  /** Deprecated names retained while older consumers migrate. */
  blocked_tasks?: HomeTaskSection;
  my_tasks?: HomeTaskSection;
  other_tasks?: HomeTaskSection;
  all_tasks_has_more?: boolean;
}

export interface HomeResponse {
  /** Canonical viewer-aware projection fields. */
  viewer_user_id?: string | null;
  as_of?: string | null;
  week?: HomeWeek | null;
  entry_counts?: HomeEntryCounts | null;
  moment?: HomeMoment | null;
  entries?: HomeEntries | null;
  /** Deprecated compatibility projection fields. */
  current_tasks?: HomeTaskSection;
  blocked_tasks?: HomeTaskSection;
  review_tasks?: HomeTaskSection;
  pending_approval_count?: number;
  needs_action_count?: number;
  waiting_on_other_count?: number;
  week_due_count?: number;
  due_soon_count?: number;
}

export interface TaskComment {
  id: string;
  workspace_id: string;
  task_id: string | null;
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
  task_id: string | null;
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
  classification?: WorkspaceClassification;
  cursor?: number | null;
}

export interface WorkspaceClassification {
  id: string;
  workspace_id: string;
  name: string;
  created_by: string;
  created_at: string | null;
}

export interface WorkspaceSnapshot {
  workspace_id: string; workspace: { id: string; name: string | null; status: string };
  members: Array<{ user_id: string; display_name?: string; member_slot: number; membership_status?: string; status?: string }>; tasks: TaskItem[];
  conflicts: Array<Record<string, unknown>>; cursor: number;
  viewer_user_id?: string | null;
  comments?: TaskComment[];
  approval_requests?: TaskApprovalRequest[];
  classifications?: WorkspaceClassification[];
  ledger_entries?: LedgerEntry[];
  habits?: Habit[];
  habit_checkins?: HabitCheckin[];
  anniversaries?: Anniversary[];
}

export interface WorkspaceChange {
  cursor: number;
  resource_type: 'task' | 'task_conflict' | 'approval_request' | 'comment' | 'classification' | 'ledger_entry' | 'habit' | 'habit_checkin' | 'anniversary' | string;
  resource_id: string;
  action: string;
  operation_id: string | null;
  resource: TaskItem | TaskApprovalRequest | TaskComment | WorkspaceClassification | LedgerEntry | Habit | HabitCheckin | Anniversary | Record<string, unknown> | null;
}
export interface WorkspaceChanges { workspace_id: string; cursor: number; changes: WorkspaceChange[] }

export type LedgerEntryType = 'EXPENSE' | 'INCOME';

export interface LedgerEntry {
  id: string;
  workspace_id: string;
  type: LedgerEntryType;
  amount_minor: number;
  amount: string;
  currency: 'CNY' | string;
  title: string;
  category: string;
  payer_or_payee_id: string;
  payer_or_payee_name?: string;
  date: string;
  note: string | null;
  created_by: string;
  updated_by: string;
  version: number;
  deleted_at: string | null;
}

export interface LedgerSummary {
  month: string;
  currency: string;
  expense_minor: number;
  income_minor: number;
  balance_minor: number;
  categories: Array<{ category: string; amount_minor: number; ratio: number }>;
  payer_totals: Array<{ user_id: string; display_name: string; amount_minor: number }>;
}

export type HabitFrequency = 'DAILY' | 'WEEKLY' | 'MONTHLY';
export type HabitStatus = 'ACTIVE' | 'PAUSED' | 'DELETED';

export interface HabitCheckin {
  id: string;
  habit_id: string;
  workspace_id: string;
  actor_id: string;
  frequency_snapshot: HabitFrequency;
  period_key: string;
  day: string;
  occurred_at: string;
  revoked_at: string | null;
}

export interface Habit {
  id: string;
  workspace_id: string;
  owner_id: string;
  title: string;
  note: string | null;
  frequency: HabitFrequency;
  start_date: string;
  status: HabitStatus;
  version: number;
  current_period_key: string;
  checked_in: boolean;
  current_checkin: HabitCheckin | null;
  checkins: HabitCheckin[];
  recent_days?: string[];
  recent_checkin_days?: string[];
  deleted_at: string | null;
}

export type AnniversaryKind = 'ANNIVERSARY' | 'BIRTHDAY' | 'IMPORTANT_DAY';

export interface Anniversary {
  id: string;
  workspace_id: string;
  title: string;
  anchor_date: string;
  kind: AnniversaryKind;
  prepare_days: number;
  note: string | null;
  next_occurrence: string;
  days_until: number;
  is_today: boolean;
  version: number;
  deleted_at?: string | null;
}

export interface PreparationTaskResult {
  task: TaskItem;
  cursor: number | null;
  source_key: string;
}
