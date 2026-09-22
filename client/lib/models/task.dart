// ignore_for_file: prefer_initializing_formals

import 'moment_next_step.dart';

export 'moment_next_step.dart';

abstract interface class TaskMutationResult {}

class TaskItem implements TaskMutationResult {
  static const maxClassificationLength = 5;

  TaskItem({
    required this.id,
    this.workspaceId,
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
    this.reviewerUserId,
    this.reviewSubmittedAt,
    this.reviewedAt,
    this.reviewRejectionReason,
    this.nextStepText,
    this.acceptanceCriteria,
    this.nextStep,
    required this.plannedStartAt,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.completedAt,
    required this.createdBy,
    required this.version,
    required this.statusVersion,
    required this.createdAt,
    required this.updatedAt,
    this.delayCount = 0,
    this.totalDelayMinutes = 0,
    this.fieldVersions = const {},
    this.lifecycleVersion = 1,
    this.deletedAt,
  }) : status = _normalizeStatus(status),
       quadrant = _validateQuadrant(quadrant),
       labels = _normalizeLabels(labels),
       _progress = progress;

  final String id;
  final String? workspaceId;
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
    'DONE' => 100,
    'IN_PROGRESS' => _progress,
    _ => null,
  };
  final String? blockedReason;
  final DateTime? blockedSince;
  final String? resumeHandlerId;
  final String? waitingForUserId;
  final String? reviewerUserId;
  final DateTime? reviewSubmittedAt;
  final DateTime? reviewedAt;
  final String? reviewRejectionReason;
  final String? nextStepText;
  final String? acceptanceCriteria;
  final MomentNextStep? nextStep;
  final DateTime? plannedStartAt;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final DateTime? completedAt;
  final String createdBy;
  final int version;
  final int statusVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int delayCount;
  final int totalDelayMinutes;
  final Map<String, int> fieldVersions;
  final int lifecycleVersion;
  final DateTime? deletedAt;

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;
    final rawProgress = json['progress'];
    final normalizedStatus = _normalizeStatus(status);
    final progress = rawProgress is num
        ? rawProgress.toInt()
        : _derivedProgress(normalizedStatus);
    return TaskItem(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String?,
      parentTaskId: json['parent_task_id'] as String?,
      taskNumber: json['task_number'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String,
      status: normalizedStatus,
      quadrant: _parseQuadrant(json['quadrant']),
      labels: _parseLabels(json),
      progress: progress,
      currentHandlerId: json['current_handler_id'] as String,
      blockedReason: json['blocked_reason'] as String?,
      blockedSince: _date(json['blocked_since']),
      resumeHandlerId: json['resume_handler_id'] as String?,
      waitingForUserId: json['waiting_for_user_id'] as String?,
      reviewerUserId: json['reviewer_user_id'] as String?,
      reviewSubmittedAt: _date(json['review_submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      reviewRejectionReason: json['review_rejection_reason'] as String?,
      nextStepText: json['next_step_text'] as String?,
      acceptanceCriteria: json['acceptance_criteria'] as String?,
      nextStep: json['next_step'] == null
          ? null
          : MomentNextStep.fromJson(json['next_step']),
      plannedStartAt: _date(json['planned_start_at']),
      dueAt: _date(json['due_at']),
      estimatedMinutes: json['estimated_minutes'] as int?,
      completedAt: _date(json['completed_at']),
      createdBy: json['created_by'] as String,
      version: json['version'] as int,
      statusVersion: json['status_version'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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
    String? reviewerUserId,
    DateTime? reviewSubmittedAt,
    DateTime? reviewedAt,
    String? reviewRejectionReason,
    String? nextStepText,
    String? acceptanceCriteria,
    MomentNextStep? nextStep,
    Map<String, int>? fieldVersions,
    int? lifecycleVersion,
    DateTime? deletedAt,
  }) => TaskItem(
    id: id,
    workspaceId: workspaceId,
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
    reviewerUserId: reviewerUserId ?? this.reviewerUserId,
    reviewSubmittedAt: reviewSubmittedAt ?? this.reviewSubmittedAt,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewRejectionReason: reviewRejectionReason ?? this.reviewRejectionReason,
    nextStepText: nextStepText ?? this.nextStepText,
    acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
    nextStep: nextStep ?? this.nextStep,
    plannedStartAt: plannedStartAt,
    dueAt: dueAt,
    estimatedMinutes: estimatedMinutes,
    completedAt: completedAt,
    createdBy: createdBy,
    version: version,
    statusVersion: statusVersion,
    createdAt: createdAt,
    updatedAt: updatedAt,
    delayCount: delayCount,
    totalDelayMinutes: totalDelayMinutes,
    fieldVersions: fieldVersions ?? this.fieldVersions,
    lifecycleVersion: lifecycleVersion ?? this.lifecycleVersion,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (workspaceId != null) 'workspace_id': workspaceId,
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
    'reviewer_user_id': reviewerUserId,
    'review_submitted_at': reviewSubmittedAt?.toUtc().toIso8601String(),
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'review_rejection_reason': reviewRejectionReason,
    'next_step_text': nextStepText,
    'acceptance_criteria': acceptanceCriteria,
    if (nextStep != null) 'next_step': nextStep!.toJson(),
    'planned_start_at': plannedStartAt?.toUtc().toIso8601String(),
    'due_at': dueAt?.toUtc().toIso8601String(),
    'estimated_minutes': estimatedMinutes,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'created_by': createdBy,
    'version': version,
    'status_version': statusVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
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

  // Legacy status values are accepted only at the read boundary.
  static String _normalizeStatus(String value) => switch (value) {
    'WAITING' => 'BLOCKED',
    'COMPLETED' => 'DONE',
    _ => value,
  };

  static List<String> _parseLabels(Map<String, dynamic> json) {
    // Omitted labels are accepted for cached pre-classification snapshots.
    // The wire field remains an array for compatibility, but a task can have
    // at most one classification.
    if (!json.containsKey('labels')) return const [];
    final value = json['labels'];
    if (value is! List) {
      throw const FormatException('task labels must be an array of strings');
    }
    if (value.length > 1) {
      throw const FormatException('task must have at most one classification');
    }
    if (value.isEmpty) return const [];
    final label = value.single;
    if (label is! String || label.trim().isEmpty) {
      throw const FormatException(
        'task classification must be a non-empty string',
      );
    }
    final normalized = label.trim();
    if (normalized.runes.length > maxClassificationLength) {
      throw const FormatException(
        'task classification must be at most 5 characters',
      );
    }
    return <String>[normalized];
  }

  static List<String> _normalizeLabels(Iterable<String> values) {
    final labels = values.map((value) => value.trim()).toList(growable: false);
    if (labels.length > 1) {
      throw const FormatException('task must have at most one classification');
    }
    if (labels.isEmpty) return const [];
    if (labels.single.isEmpty) {
      throw const FormatException(
        'task classification must be a non-empty string',
      );
    }
    if (labels.single.runes.length > maxClassificationLength) {
      throw const FormatException(
        'task classification must be at most 5 characters',
      );
    }
    return List.unmodifiable(labels);
  }

  static int? _derivedProgress(String status) => switch (status) {
    'TODO' => 0,
    'DONE' => 100,
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
    this.kind = 'activity',
    this.eventType,
    this.operationType,
    this.actorUserId,
    this.authorUserId,
    this.requestId,
    this.body,
    this.reason,
    this.note,
    this.newDueAt,
    this.delayDurationMinutes,
  });

  final String id;
  final String kind;
  final String action;
  final String? eventType;
  final String? operationType;
  final String? actorUserId;
  final String? authorUserId;
  final String? requestId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic> payload;
  final String? body;
  final String? reason;
  final String? note;
  final DateTime? newDueAt;
  final int? delayDurationMinutes;
  final DateTime createdAt;

  factory TaskActivity.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = json['created_at'];
    if (id is! String || id.isEmpty || createdAt is! String) {
      throw const FormatException('task activity has invalid identity');
    }
    final kind = _string(json['kind']) ?? 'activity';
    final eventType = _string(json['event_type']);
    final operationType = _string(json['operation_type']);
    final action =
        _string(json['action']) ?? eventType ?? operationType ?? kind;
    final payload = _map(json['payload'] ?? json['payload_json']);
    final before =
        _mapOrNull(json['before'] ?? json['before_json']) ??
        _mapOrNull(payload['before']);
    final after =
        _mapOrNull(json['after'] ?? json['after_json']) ??
        _mapOrNull(payload['after']);
    return TaskActivity(
      id: id,
      kind: kind,
      action: action,
      eventType: eventType,
      operationType: operationType,
      actorUserId: _string(json['actor_user_id']),
      authorUserId: _string(json['author_user_id']),
      requestId: _string(json['request_id']),
      before: before,
      after: after,
      payload: payload,
      body: _string(json['body']),
      reason: _string(json['reason']),
      note: _string(json['note']),
      newDueAt: _date(json['new_due_at']),
      delayDurationMinutes: (json['delay_duration_minutes'] as num?)?.toInt(),
      createdAt: DateTime.parse(createdAt),
    );
  }

  /// Approval metadata is nested in activity payloads on the cloud API.
  Map<String, dynamic> get approvalRequest => _map(payload['approval_request']);

  Map<String, dynamic> get proposedChanges =>
      _map(approvalRequest['proposed_changes']);

  String? get transferNote => _firstString([
    payload['transfer_note'],
    proposedChanges['transfer_note'],
    _map(payload['after'])['transfer_note'],
  ]);

  String? get reviewContent => _firstString([
    payload['review_content'],
    proposedChanges['review_content'],
    _map(payload['after'])['review_content'],
  ]);

  String? get rejectionReason => _firstString([
    payload['rejection_reason'],
    payload['reason'],
    approvalRequest['rejection_reason'],
    proposedChanges['review_rejection_reason'],
    _map(payload['after'])['review_rejection_reason'],
  ]);

  String? get operatorId =>
      actorUserId ??
      authorUserId ??
      _string(approvalRequest['reviewed_by']) ??
      _string(approvalRequest['requester_id']);

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', item));
  }

  static Map<String, dynamic>? _mapOrNull(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', item));
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static String? _firstString(Iterable<Object?> values) {
    for (final value in values) {
      final text = _string(value)?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
