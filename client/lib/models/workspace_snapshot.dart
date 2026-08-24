import 'task.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.workspaceId,
    required this.cursor,
    required this.tasks,
    this.members = const [],
    this.conflicts = const [],
    this.fetchedAt,
  });

  final String workspaceId;
  final int cursor;
  final List<TaskItem> tasks;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> conflicts;
  final DateTime? fetchedAt;

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceSnapshot(
        workspaceId: json['workspace_id'] as String,
        cursor: json['cursor'] as int,
        tasks: (json['tasks'] as List<dynamic>? ?? const [])
            .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        members: (json['members'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
        conflicts: (json['conflicts'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>(),
        fetchedAt: json['fetched_at'] == null
            ? null
            : DateTime.parse(json['fetched_at'] as String),
      );

  Map<String, Object?> toJson() => {
    'workspace_id': workspaceId,
    'cursor': cursor,
    'tasks': tasks.map(_taskJson).toList(),
    'members': members,
    'conflicts': conflicts,
    'fetched_at': fetchedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _taskJson(TaskItem task) => {
    'id': task.id,
    'parent_task_id': task.parentTaskId,
    'title': task.title,
    'description': task.description,
    'status': task.status,
    'current_handler_id': task.currentHandlerId,
    'blocked_reason': task.blockedReason,
    'blocked_since': task.blockedSince?.toUtc().toIso8601String(),
    'resume_handler_id': task.resumeHandlerId,
    'waiting_for_user_id': task.waitingForUserId,
    'planned_start_at': task.plannedStartAt?.toUtc().toIso8601String(),
    'due_at': task.dueAt?.toUtc().toIso8601String(),
    'estimated_minutes': task.estimatedMinutes,
    'completed_at': task.completedAt?.toUtc().toIso8601String(),
    'created_by': task.createdBy,
    'version': task.version,
    'status_version': task.statusVersion,
    'created_at': task.createdAt.toUtc().toIso8601String(),
    'updated_at': task.updatedAt.toUtc().toIso8601String(),
    'assignee_ids': task.assigneeIds,
    'delay_count': task.delayCount,
    'total_delay_minutes': task.totalDelayMinutes,
    'field_versions': task.fieldVersions,
    'lifecycle_version': task.lifecycleVersion,
    'deleted_at': task.deletedAt?.toUtc().toIso8601String(),
  };
}
