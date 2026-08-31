// ignore_for_file: prefer_initializing_formals

abstract interface class TaskMutationResult {}

class TaskItem implements TaskMutationResult {
  TaskItem({
    required this.id,
    required this.parentTaskId,
    this.taskNumber = '',
    required this.title,
    required this.description,
    required String status,
    required this.currentHandlerId,
    required String quadrant,
    List<String> labels = const [],
    // Keep a public `progress` parameter while storing the nullable wire value.
    // The getter supplies 0/100 for terminal statuses when the server omits it.
    int? progress,
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
    this.fieldVersions = const {},
    this.lifecycleVersion = 1,
    this.deletedAt,
  }) : status = _normalizeStatus(status),
       quadrant = _validateQuadrant(quadrant),
       labels = List.unmodifiable(labels),
       _progress = progress;

  final String id;
  final String? parentTaskId;
  final String taskNumber;
  final String title;
  final String description;
  final String status;
  final String currentHandlerId;
  final String quadrant;
  final List<String> labels;
  final int? _progress;

  int? get progress => switch (status) {
    'TODO' => 0,
    'DONE' || 'COMPLETED' => 100,
    'IN_PROGRESS' => _progress,
    _ => null,
  };
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
  final Map<String, int> fieldVersions;
  final int lifecycleVersion;
  final DateTime? deletedAt;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;
    final rawProgress = json['progress'];
    final progress = rawProgress is num
        ? rawProgress.toInt()
        : _derivedProgress(status);
    return TaskItem(
      id: json['id'] as String,
      parentTaskId: json['parent_task_id'] as String?,
      taskNumber: json['task_number'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String,
      status: status,
      quadrant: _parseQuadrant(json['quadrant']),
      labels: _parseLabels(json),
      progress: progress,
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
      fieldVersions:
          (json['field_versions'] as Map<Object?, Object?>?)?.map(
            (key, value) => MapEntry(key as String, value as int),
          ) ??
          const {},
      lifecycleVersion: json['lifecycle_version'] as int? ?? 1,
      deletedAt: _date(json['deleted_at']),
    );
  }

  TaskItem copyWith({
    String? taskNumber,
    String? title,
    String? description,
    String? status,
    String? quadrant,
    List<String>? labels,
    int? progress,
    String? currentHandlerId,
    Map<String, int>? fieldVersions,
    int? lifecycleVersion,
    DateTime? deletedAt,
  }) => TaskItem(
    id: id,
    parentTaskId: parentTaskId,
    taskNumber: taskNumber ?? this.taskNumber,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    quadrant: quadrant ?? this.quadrant,
    labels: labels ?? this.labels,
    progress: progress ?? this.progress,
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
    fieldVersions: fieldVersions ?? this.fieldVersions,
    lifecycleVersion: lifecycleVersion ?? this.lifecycleVersion,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'parent_task_id': parentTaskId,
    'task_number': taskNumber,
    'title': title,
    'description': description,
    'status': status,
    'quadrant': quadrant,
    'labels': labels,
    'progress': progress,
    'current_handler_id': currentHandlerId,
    'blocked_reason': blockedReason,
    'blocked_since': blockedSince?.toUtc().toIso8601String(),
    'resume_handler_id': resumeHandlerId,
    'waiting_for_user_id': waitingForUserId,
    'planned_start_at': plannedStartAt?.toUtc().toIso8601String(),
    'due_at': dueAt?.toUtc().toIso8601String(),
    'estimated_minutes': estimatedMinutes,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'created_by': createdBy,
    'version': version,
    'status_version': statusVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'assignee_ids': assigneeIds,
    'delay_count': delayCount,
    'total_delay_minutes': totalDelayMinutes,
    'field_versions': fieldVersions,
    'lifecycle_version': lifecycleVersion,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  static const _validQuadrants = {'Q1', 'Q2', 'Q3', 'Q4'};

  static String _parseQuadrant(Object? value) {
    if (value is! String || !_validQuadrants.contains(value)) {
      throw const FormatException(
        'task quadrant must be one of Q1, Q2, Q3, Q4',
      );
    }
    return value;
  }

  static String _validateQuadrant(String value) => _parseQuadrant(value);

  // The persisted API historically exposed COMPLETED; the public client
  // contract uses DONE for the same terminal state.
  static String _normalizeStatus(String value) =>
      value == 'COMPLETED' ? 'DONE' : value;

  static List<String> _parseLabels(Map<String, dynamic> json) {
    // Omitted labels are accepted for cached pre-label snapshots. Values from
    // a mixed-type array are ignored, but a non-array is malformed protocol
    // data and must not replace the last valid snapshot.
    if (!json.containsKey('labels')) return const [];
    final value = json['labels'];
    if (value is! List) {
      throw const FormatException('task labels must be an array of strings');
    }
    return value.whereType<String>().toList(growable: false);
  }

  static int? _derivedProgress(String status) => switch (status) {
    'TODO' => 0,
    'DONE' || 'COMPLETED' => 100,
    _ => null,
  };
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
