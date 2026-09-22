import 'classification.dart';
import '../life/life_repository.dart';
import 'task.dart';
import 'task_approval_request.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.workspaceId,
    required this.cursor,
    required this.tasks,
    this.viewerUserId,
    this.members = const [],
    this.conflicts = const [],
    this.comments = const [],
    this.approvalRequests = const [],
    this.classifications = const [],
    this.hasClassificationContract = false,
    this.ledgerEntries = const [],
    this.habits = const [],
    this.habitCheckins = const [],
    this.anniversaries = const [],
    this.hasLifeDomainContract = false,
    this.fetchedAt,
  });

  final String workspaceId;
  final int cursor;
  final List<TaskItem> tasks;
  final String? viewerUserId;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> conflicts;
  final List<TaskComment> comments;
  final List<TaskApprovalRequest> approvalRequests;
  final List<WorkspaceClassification> classifications;

  /// Whether the source explicitly provided the classifications resource.
  ///
  /// Older cached snapshots predate classifications altogether. They remain
  /// readable until the next authoritative refresh, while every current API
  /// snapshot must prove non-empty task classifications are approved.
  final bool hasClassificationContract;
  final List<LedgerItem> ledgerEntries;
  final List<HabitItem> habits;
  final List<HabitCheckinItem> habitCheckins;
  final List<AnniversaryItem> anniversaries;

  /// Whether this snapshot explicitly carried the life-domain resources.
  /// Older cached snapshots remain readable until an authoritative refresh.
  final bool hasLifeDomainContract;
  final DateTime? fetchedAt;

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshot = WorkspaceSnapshot(
      workspaceId: json['workspace_id'] as String,
      cursor: json['cursor'] as int,
      viewerUserId: json['viewer_user_id'] as String?,
      tasks: (json['tasks'] as List<dynamic>? ?? const [])
          .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      members: (json['members'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      conflicts: (json['conflicts'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      comments: (json['comments'] as List<dynamic>? ?? const [])
          .map((item) => TaskComment.fromJson(item as Map<String, dynamic>))
          .toList(),
      approvalRequests:
          (json['approval_requests'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    TaskApprovalRequest.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      classifications: (json['classifications'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                WorkspaceClassification.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      hasClassificationContract: json.containsKey('classifications'),
      ledgerEntries: (json['ledger_entries'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                LedgerItem.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      habits: (json['habits'] as List<dynamic>? ?? const [])
          .map(
            (item) => HabitItem.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      habitCheckins: (json['habit_checkins'] as List<dynamic>? ?? const [])
          .map(
            (item) => HabitCheckinItem.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      anniversaries: (json['anniversaries'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                AnniversaryItem.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      hasLifeDomainContract:
          json.containsKey('ledger_entries') ||
          json.containsKey('habits') ||
          json.containsKey('habit_checkins') ||
          json.containsKey('anniversaries'),
      fetchedAt: json['fetched_at'] == null
          ? null
          : DateTime.parse(json['fetched_at'] as String),
    );
    if (!snapshot.isValidForWorkspace()) {
      throw const FormatException('workspace snapshot contains foreign data');
    }
    return snapshot;
  }

  bool isValidForWorkspace() {
    if (workspaceId.isEmpty || cursor < 0) return false;
    if (tasks.any(
      (task) => task.workspaceId != null && task.workspaceId != workspaceId,
    )) {
      return false;
    }
    if (comments.any((comment) => comment.workspaceId != workspaceId)) {
      return false;
    }
    if (conflicts.any((conflict) {
      final conflictWorkspaceId = conflict['workspace_id'];
      if (conflict.containsKey('workspace_id') &&
          conflictWorkspaceId != workspaceId) {
        return true;
      }
      final currentSnapshot = conflict['current_snapshot'];
      if (currentSnapshot == null) return false;
      if (currentSnapshot is! Map) return true;
      if (currentSnapshot.containsKey('workspace_id') &&
          currentSnapshot['workspace_id'] != workspaceId) {
        return true;
      }
      final taskId = conflict['task_id'];
      return currentSnapshot.containsKey('id') &&
          currentSnapshot['id'] != taskId;
    })) {
      return false;
    }
    if (!approvalRequests.every(
          (request) => request.workspaceId == workspaceId,
        ) ||
        !classifications.every(
          (classification) => classification.workspaceId == workspaceId,
        )) {
      return false;
    }
    if (!ledgerEntries.every(
      (entry) => entry.workspaceId == null || entry.workspaceId == workspaceId,
    )) {
      return false;
    }
    if (!habits.every(
      (habit) => habit.workspaceId == null || habit.workspaceId == workspaceId,
    )) {
      return false;
    }
    if (!habitCheckins.every((checkin) => checkin.workspaceId == workspaceId)) {
      return false;
    }
    if (!anniversaries.every(
      (anniversary) =>
          anniversary.workspaceId == null ||
          anniversary.workspaceId == workspaceId,
    )) {
      return false;
    }
    if (!habits.every(
      (habit) =>
          habit.checkins.every((checkin) => checkin.workspaceId == workspaceId),
    )) {
      return false;
    }
    if (!hasClassificationContract) return true;

    final approvedNames = <String>{};
    for (final classification in classifications) {
      final normalized = classification.name.trim().toLowerCase();
      if (!approvedNames.add(normalized)) return false;
    }
    return tasks.every((task) {
      if (task.labels.isEmpty) return true;
      return task.labels.length == 1 &&
          approvedNames.contains(task.labels.single.trim().toLowerCase());
    });
  }

  Map<String, Object?> toJson() => {
    'workspace_id': workspaceId,
    'cursor': cursor,
    'viewer_user_id': viewerUserId,
    'tasks': tasks.map(_taskJson).toList(),
    'members': members,
    'conflicts': conflicts,
    'comments': comments.map((comment) => comment.toJson()).toList(),
    'approval_requests': approvalRequests
        .map((request) => request.toJson())
        .toList(),
    if (hasClassificationContract)
      'classifications': classifications
          .map((classification) => classification.toJson())
          .toList(),
    if (hasLifeDomainContract) ...{
      'ledger_entries': ledgerEntries.map(_ledgerJson).toList(),
      'habits': habits.map(_habitJson).toList(),
      'habit_checkins': habitCheckins.map(_checkinJson).toList(),
      'anniversaries': anniversaries.map(_anniversaryJson).toList(),
    },
    'fetched_at': fetchedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _taskJson(TaskItem task) => task.toJson();

  static Map<String, Object?> _ledgerJson(LedgerItem item) => {
    'id': item.id,
    'workspace_id': item.workspaceId,
    'type': item.type,
    'amount_minor': item.amountMinor,
    'amount': item.formattedAmount,
    'currency': item.currency,
    'title': item.title,
    'category': item.category,
    'payer_or_payee_id': item.payerId,
    'payer_or_payee_name': item.payerName,
    'date': item.date.toIso8601String().split('T').first,
    'note': item.note,
    'created_by': item.createdBy,
    'updated_by': item.updatedBy,
    'version': item.version,
    'deleted_at': item.deletedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _checkinJson(HabitCheckinItem item) => {
    'id': item.id,
    'habit_id': item.habitId,
    'workspace_id': item.workspaceId,
    'actor_id': item.actorId,
    'frequency_snapshot': item.frequencySnapshot,
    'period_key': item.periodKey,
    'day': item.day.toIso8601String().split('T').first,
    'occurred_at': item.occurredAt.toUtc().toIso8601String(),
    'revoked_at': item.revokedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _habitJson(HabitItem item) => {
    'id': item.id,
    'workspace_id': item.workspaceId,
    'owner_id': item.ownerId,
    'title': item.title,
    'note': item.note,
    'frequency': item.frequency,
    'start_date': item.startDate.toIso8601String().split('T').first,
    'status': item.status,
    'version': item.version,
    'current_period_key': item.periodKey,
    'checked_in': item.checkedIn,
    'current_checkin': item.currentCheckin == null
        ? null
        : _checkinJson(item.currentCheckin!),
    'checkins': item.checkins.map(_checkinJson).toList(),
    'deleted_at': item.deletedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _anniversaryJson(AnniversaryItem item) => {
    'id': item.id,
    'workspace_id': item.workspaceId,
    'title': item.title,
    'anchor_date': item.anchorDate.toIso8601String().split('T').first,
    'kind': item.kind,
    'prepare_days': item.prepareDays,
    'note': item.note,
    'next_occurrence': item.nextOccurrence.toIso8601String().split('T').first,
    'days_until': item.daysUntil,
    'is_today': item.isToday,
    'version': item.version,
    'deleted_at': item.deletedAt?.toUtc().toIso8601String(),
    'created_by': item.createdBy,
    'updated_by': item.updatedBy,
  };
}
