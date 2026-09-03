import 'task.dart';

class TaskApprovalRequest {
  const TaskApprovalRequest({
    required this.id,
    required this.workspaceId,
    required this.taskId,
    this.commentId,
    required this.requesterId,
    required this.approverId,
    required this.requestType,
    required this.proposedChanges,
    required this.baseFieldVersions,
    required this.requestId,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    this.resolvedCursor,
  });

  final String id;
  final String workspaceId;
  final String taskId;
  final String? commentId;
  final String requesterId;
  final String approverId;
  final String requestType;
  final Map<String, dynamic> proposedChanges;
  final Map<String, int> baseFieldVersions;
  final String requestId;
  final String status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;
  final int? resolvedCursor;

  factory TaskApprovalRequest.fromJson(Map<String, dynamic> json) {
    final proposed = _stringDynamicMap(json['proposed_changes']);
    final versions = <String, int>{};
    final rawVersions = json['base_field_versions'];
    if (rawVersions is Map) {
      for (final entry in rawVersions.entries) {
        final value = entry.value;
        if (value is num) versions['${entry.key}'] = value.toInt();
      }
    }
    return TaskApprovalRequest(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      taskId: json['task_id'] as String,
      commentId: json['comment_id'] as String?,
      requesterId: json['requester_id'] as String,
      approverId: json['approver_id'] as String,
      requestType: json['request_type'] as String,
      proposedChanges: proposed,
      baseFieldVersions: versions,
      requestId: json['request_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: _date(json['reviewed_at']),
      reviewedBy: json['reviewed_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      resolvedCursor: (json['resolved_cursor'] as num?)?.toInt(),
    );
  }

  bool isIncoming(String userId) => approverId == userId;

  bool isOutgoing(String userId) => requesterId == userId;

  Map<String, Object?> toJson() => {
    'id': id,
    'workspace_id': workspaceId,
    'task_id': taskId,
    'comment_id': commentId,
    'requester_id': requesterId,
    'approver_id': approverId,
    'request_type': requestType,
    'proposed_changes': proposedChanges,
    'base_field_versions': baseFieldVersions,
    'request_id': requestId,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'reviewed_at': reviewedAt?.toUtc().toIso8601String(),
    'reviewed_by': reviewedBy,
    'rejection_reason': rejectionReason,
    'resolved_cursor': resolvedCursor,
  };

  TaskApprovalRequest copyWith({
    String? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? rejectionReason,
    int? resolvedCursor,
  }) => TaskApprovalRequest(
    id: id,
    workspaceId: workspaceId,
    taskId: taskId,
    commentId: commentId,
    requesterId: requesterId,
    approverId: approverId,
    requestType: requestType,
    proposedChanges: proposedChanges,
    baseFieldVersions: baseFieldVersions,
    requestId: requestId,
    status: status ?? this.status,
    createdAt: createdAt,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    resolvedCursor: resolvedCursor ?? this.resolvedCursor,
  );

  static Map<String, dynamic> _stringDynamicMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', item));
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

class PendingApproval implements TaskMutationResult {
  const PendingApproval({
    required this.approvalRequest,
    this.pending = true,
    this.cursor,
  });

  final TaskApprovalRequest approvalRequest;
  final bool pending;
  final int? cursor;

  TaskApprovalRequest get request => approvalRequest;

  String get status => approvalRequest.status;

  factory PendingApproval.fromJson(Map<String, dynamic> json) {
    final rawRequest = json['approval_request'];
    if (rawRequest is! Map) {
      throw const FormatException('missing approval_request');
    }
    return PendingApproval(
      approvalRequest: TaskApprovalRequest.fromJson(
        rawRequest.cast<String, dynamic>(),
      ),
      pending: json['pending'] as bool? ?? true,
      cursor: (json['cursor'] as num?)?.toInt(),
    );
  }
}

class ApprovalActionResult {
  const ApprovalActionResult({
    required this.approvalRequest,
    this.task,
    this.comment,
    this.cursor,
  });

  final TaskApprovalRequest approvalRequest;
  final TaskItem? task;
  final TaskComment? comment;
  final int? cursor;

  TaskApprovalRequest get request => approvalRequest;

  TaskItem? get updatedTask => task;

  TaskComment? get updatedComment => comment;

  factory ApprovalActionResult.fromJson(Map<String, dynamic> json) {
    final rawRequest = json['approval_request'] ?? json['request'];
    if (rawRequest is! Map) {
      throw const FormatException('missing approval_request');
    }
    final rawTask = json['task'];
    final rawComment = json['comment'];
    return ApprovalActionResult(
      approvalRequest: TaskApprovalRequest.fromJson(
        rawRequest.cast<String, dynamic>(),
      ),
      task: rawTask is Map
          ? TaskItem.fromJson(rawTask.cast<String, dynamic>())
          : null,
      comment: rawComment is Map
          ? TaskComment.fromJson(rawComment.cast<String, dynamic>())
          : null,
      cursor: (json['cursor'] as num?)?.toInt(),
    );
  }
}

class TaskComment implements TaskMutationResult {
  const TaskComment({
    required this.id,
    this.workspaceId,
    required this.taskId,
    required this.authorUserId,
    required this.body,
    required this.version,
    this.deletedAt,
    this.deletedBy,
    this.createdAt,
  });

  final String id;
  final String? workspaceId;
  final String taskId;
  final String authorUserId;
  final String body;
  final int version;
  final DateTime? deletedAt;
  final String? deletedBy;
  final DateTime? createdAt;

  factory TaskComment.fromJson(Map<String, dynamic> json) => TaskComment(
    id: json['id'] as String,
    workspaceId: json['workspace_id'] as String?,
    taskId: json['task_id'] as String,
    authorUserId: json['author_user_id'] as String,
    body: json['body'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
    deletedAt: _date(json['deleted_at']),
    deletedBy: json['deleted_by'] as String?,
    createdAt: _date(json['created_at']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'workspace_id': workspaceId,
    'task_id': taskId,
    'author_user_id': authorUserId,
    'body': body,
    'version': version,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'deleted_by': deletedBy,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

typedef TaskCommentItem = TaskComment;
typedef TaskApprovalResult = ApprovalActionResult;
typedef TaskPendingApproval = PendingApproval;
