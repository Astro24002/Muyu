class TaskItem {
  const TaskItem({
    required this.id,
    required this.parentTaskId,
    required this.title,
    required this.description,
    required this.status,
    required this.currentHandlerId,
    this.blockedReason,
    this.blockedSince,
    this.resumeHandlerId,
    this.waitingForUserId,
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
    this.delayCount = 0,
    this.totalDelayMinutes = 0,
  });

  final String id;
  final String? parentTaskId;
  final String title;
  final String description;
  final String status;
  final String currentHandlerId;
  final String? blockedReason;
  final DateTime? blockedSince;
  final String? resumeHandlerId;
  final String? waitingForUserId;
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
  final int delayCount;
  final int totalDelayMinutes;

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'] as String,
    parentTaskId: json['parent_task_id'] as String?,
    title: json['title'] as String,
    description: json['description'] as String,
    status: json['status'] as String,
    currentHandlerId: json['current_handler_id'] as String,
    blockedReason: json['blocked_reason'] as String?,
    blockedSince: _date(json['blocked_since']),
    resumeHandlerId: json['resume_handler_id'] as String?,
    waitingForUserId: json['waiting_for_user_id'] as String?,
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
    delayCount: json['delay_count'] as int? ?? 0,
    totalDelayMinutes: json['total_delay_minutes'] as int? ?? 0,
  );

  TaskItem copyWith({String? status, String? currentHandlerId}) => TaskItem(
    id: id,
    parentTaskId: parentTaskId,
    title: title,
    description: description,
    status: status ?? this.status,
    currentHandlerId: currentHandlerId ?? this.currentHandlerId,
    blockedReason: blockedReason,
    blockedSince: blockedSince,
    resumeHandlerId: resumeHandlerId,
    waitingForUserId: waitingForUserId,
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
    delayCount: delayCount,
    totalDelayMinutes: totalDelayMinutes,
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

const taskDelayReasonLabels = <String, String>{
  'NO_TIME': '没有时间',
  'TOO_LARGE': '任务过大',
  'NOT_WILLING': '暂时不想处理',
  'FORGOT': '忘记处理',
  'WAITING_PARTNER': '等待对方',
  'INTERRUPTED': '被其他事情打断',
  'OTHER': '其他',
};

class TaskDelayRecord {
  const TaskDelayRecord({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.originalDueAt,
    required this.newDueAt,
    required this.delayedAt,
    required this.delayDurationMinutes,
    required this.reason,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String userId;
  final DateTime originalDueAt;
  final DateTime newDueAt;
  final DateTime delayedAt;
  final int delayDurationMinutes;
  final String reason;
  final String? note;
  final DateTime createdAt;

  factory TaskDelayRecord.fromJson(Map<String, dynamic> json) =>
      TaskDelayRecord(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        userId: json['user_id'] as String,
        originalDueAt: DateTime.parse(json['original_due_at'] as String),
        newDueAt: DateTime.parse(json['new_due_at'] as String),
        delayedAt: DateTime.parse(json['delayed_at'] as String),
        delayDurationMinutes: json['delay_duration_minutes'] as int,
        reason: json['reason'] as String,
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
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
