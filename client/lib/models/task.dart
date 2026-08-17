class TaskItem {
  const TaskItem({
    required this.id,
    required this.parentTaskId,
    required this.title,
    required this.description,
    required this.status,
    required this.currentHandlerId,
    required this.plannedStartAt,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.completedAt,
    required this.createdBy,
    required this.version,
    required this.statusVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.assigneeIds,
  });

  final String id;
  final String? parentTaskId;
  final String title;
  final String description;
  final String status;
  final String currentHandlerId;
  final DateTime? plannedStartAt;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final DateTime? completedAt;
  final String createdBy;
  final int version;
  final int statusVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> assigneeIds;

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String,
    parentTaskId: json['parent_task_id'] as String?,
    title: json['title'] as String,
    description: json['description'] as String,
    status: json['status'] as String,
    currentHandlerId: json['current_handler_id'] as String,
    plannedStartAt: _date(json['planned_start_at']),
    dueAt: _date(json['due_at']),
    estimatedMinutes: json['estimated_minutes'] as int?,
    completedAt: _date(json['completed_at']),
    createdBy: json['created_by'] as String,
    version: json['version'] as int,
    statusVersion: json['status_version'] as int,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    assigneeIds: (json['assignee_ids'] as List<dynamic>).cast<String>(),
  );

  TaskItem copyWith({String? status, String? currentHandlerId}) => TaskItem(
    id: id,
    parentTaskId: parentTaskId,
    title: title,
    description: description,
    status: status ?? this.status,
    currentHandlerId: currentHandlerId ?? this.currentHandlerId,
    plannedStartAt: plannedStartAt,
    dueAt: dueAt,
    estimatedMinutes: estimatedMinutes,
    completedAt: completedAt,
    createdBy: createdBy,
    version: version,
    statusVersion: statusVersion,
    createdAt: createdAt,
    updatedAt: updatedAt,
    assigneeIds: assigneeIds,
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

class TaskActivity {
  const TaskActivity({
    required this.id,
    required this.action,
    required this.before,
    required this.after,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String action;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory TaskActivity.fromJson(Map<String, dynamic> json) => TaskActivity(
    id: json['id'] as String,
    action: json['action'] as String,
    before: (json['before_json'] as Map<Object?, Object?>?)
        ?.cast<String, dynamic>(),
    after: (json['after_json'] as Map<Object?, Object?>?)
        ?.cast<String, dynamic>(),
    payload: (json['payload_json'] as Map<Object?, Object?>)
        .cast<String, dynamic>(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
