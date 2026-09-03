import 'dart:math';

import '../core/api_client.dart';
import '../models/workspace_change.dart';
import '../models/workspace_snapshot.dart';
import '../models/task.dart';
import '../models/task_approval_request.dart';
import '../models/home.dart';

abstract class WorkspaceSyncRepository {
  Future<WorkspaceSnapshot> snapshot();

  Future<WorkspaceChanges> changes({required int afterCursor});

  /// The bounded action-first projection is optional for older API versions.
  Future<HomeResponse?> home() async => null;

  Future<TaskItem> create({
    required String title,
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskMutationResult> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    String? reviewRejectionReason,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskApprovalRequest> createApprovalRequest({
    String? workspaceId,
    required String taskId,
    String? commentId,
    required String requestType,
    required Map<String, Object?> proposedChanges,
    required Map<String, int> baseFieldVersions,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<List<TaskApprovalRequest>> listApprovalRequests({
    String? workspaceId,
    String? box,
  }) {
    throw UnimplementedError();
  }

  Future<ApprovalActionResult> approveApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  Future<ApprovalActionResult> cancelApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) {
    throw UnimplementedError();
  }

  Future<TaskMutationResult?> deleteComment(
    String taskId,
    String commentId, {
    required int baseVersion,
    String? requestId,
  }) {
    throw UnimplementedError();
  }

  Stream<WorkspaceChanged> openWorkspaceHints();
}

class HttpWorkspaceSyncRepository implements WorkspaceSyncRepository {
  HttpWorkspaceSyncRepository(this._api, {this.hints = const Stream.empty()});

  final ApiClient _api;
  final Stream<WorkspaceChanged> hints;

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => hints;

  @override
  Future<TaskItem> create({
    required String title,
    required String quadrant,
    List<String> labels = const [],
    String? description,
    String? dueAt,
    String? parentTaskId,
    String? plannedStartAt,
    int? estimatedMinutes,
    required String requestId,
  }) async {
    final body = <String, Object?>{
      'request_id': requestId,
      'title': title,
      'quadrant': quadrant,
      'labels': labels,
    };
    if (description != null) {
      body['description'] = description;
    }
    if (dueAt != null) {
      body['due_at'] = dueAt;
    }
    if (parentTaskId != null) {
      body['parent_task_id'] = parentTaskId;
    }
    if (plannedStartAt != null) {
      body['planned_start_at'] = plannedStartAt;
    }
    if (estimatedMinutes != null) {
      body['estimated_minutes'] = estimatedMinutes;
    }
    final value = await _api.request(
      'POST',
      '/api/v1/tasks',
      body: body,
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    return TaskItem.fromJson(value as Map<String, dynamic>);
  }

  @override
  Future<TaskMutationResult?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async {
    final value = await _api.request(
      'PATCH',
      '/api/v1/tasks/$taskId',
      body: {
        'request_id': requestId,
        'changes': fields,
        'base_field_versions': fieldVersions,
      },
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    return _taskMutation(value);
  }

  @override
  Future<WorkspaceSnapshot> snapshot() async => WorkspaceSnapshot.fromJson(
    await _api.request(
      'GET',
      '/api/v1/workspaces/current/snapshot',
      authenticated: true,
    ) as Map<String, dynamic>,
  );

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      WorkspaceChanges.fromJson(
        await _api.request(
          'GET',
          '/api/v1/workspaces/current/changes?after_cursor=$afterCursor',
          authenticated: true,
        ) as Map<String, dynamic>,
      );

  @override
  Future<HomeResponse?> home() async {
    final value = await _api.request(
      'GET',
      '/api/v1/home',
      authenticated: true,
    );
    return HomeResponse.fromJson(value);
  }

  @override
  Future<TaskMutationResult> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    String? reviewRejectionReason,
    required String requestId,
  }) async {
    final value = await _api.request(
      'POST',
      '/api/v1/tasks/$taskId/transition',
      body: {
        'request_id': requestId,
        'target_status': targetStatus,
        'base_status_version': baseStatusVersion,
        'blocked_reason': blockedReason,
        'resume_handler_id': resumeHandlerId,
        'waiting_for_user_id': waitingForUserId,
        'review_rejection_reason': reviewRejectionReason,
      },
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    final result = _taskMutation(value);
    if (result == null) {
      throw const FormatException('服务器返回了无效任务或审批请求');
    }
    return result;
  }

  @override
  Future<Object?> addComment(
    String taskId, {
    required String body,
    required String requestId,
  }) => _api.request(
    'POST',
    '/api/v1/tasks/$taskId/comments',
    body: {'request_id': requestId, 'body': body},
    authenticated: true,
    headers: {'x-request-id': requestId},
  );

  @override
  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    required String requestId,
  }) => _api.request(
    'POST',
    '/api/v1/tasks/$taskId/delays',
    body: {
      'request_id': requestId,
      'new_due_at': newDueAt,
      'reason': reason,
      'note': note,
    },
    authenticated: true,
    headers: {'x-request-id': requestId},
  );

  @override
  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    required String requestId,
  }) async => TaskItem.fromJson(
    await _api.request(
      'POST',
      '/api/v1/tasks/$taskId/conflicts/$conflictId/resolve',
      body: {'request_id': requestId, 'resolution': resolution},
      authenticated: true,
      headers: {'x-request-id': requestId},
    ) as Map<String, dynamic>,
  );

  @override
  Future<TaskApprovalRequest> createApprovalRequest({
    String? workspaceId,
    required String taskId,
    String? commentId,
    required String requestType,
    required Map<String, Object?> proposedChanges,
    required Map<String, int> baseFieldVersions,
    required String requestId,
  }) async {
    final body = <String, Object?>{
      'request_id': requestId,
      'task_id': taskId,
      'request_type': requestType,
      'proposed_changes': proposedChanges,
      'base_field_versions': baseFieldVersions,
    };
    if (commentId != null) body['comment_id'] = commentId;
    final value = await _api.request(
      'POST',
      _approvalPath(workspaceId),
      body: body,
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    if (value is! Map) {
      throw const FormatException(
        'server returned an invalid approval request',
      );
    }
    return TaskApprovalRequest.fromJson(value.cast<String, dynamic>());
  }

  @override
  Future<List<TaskApprovalRequest>> listApprovalRequests({
    String? workspaceId,
    String? box,
  }) async {
    final suffix = box == null ? '' : '?box=${Uri.encodeQueryComponent(box)}';
    final value = await _api.request(
      'GET',
      '${_approvalPath(workspaceId)}$suffix',
      authenticated: true,
    );
    if (value is! List) {
      throw const FormatException('server returned an invalid approval list');
    }
    return value
        .whereType<Map>()
        .map(
          (item) => TaskApprovalRequest.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
  }

  @override
  Future<ApprovalActionResult> approveApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) => _approvalAction(
    'approve',
    approvalId,
    workspaceId: workspaceId,
    requestId: requestId,
  );

  @override
  Future<ApprovalActionResult> rejectApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) => _approvalAction(
    'reject',
    approvalId,
    workspaceId: workspaceId,
    requestId: requestId,
    reason: reason,
  );

  @override
  Future<ApprovalActionResult> cancelApproval(
    String approvalId, {
    String? workspaceId,
    required String requestId,
  }) => _approvalAction(
    'cancel',
    approvalId,
    workspaceId: workspaceId,
    requestId: requestId,
  );

  @override
  Future<TaskMutationResult?> deleteComment(
    String taskId,
    String commentId, {
    required int baseVersion,
    String? requestId,
  }) async {
    final id = requestId ?? _newRequestId();
    final value = await _api.request(
      'DELETE',
      '/api/v1/tasks/$taskId/comments/$commentId',
      body: {'request_id': id, 'base_version': baseVersion},
      authenticated: true,
      headers: {'x-request-id': id},
    );
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    if (json['pending'] == true && json['approval_request'] != null) {
      return PendingApproval.fromJson(json);
    }
    if (json['id'] != null && json['task_id'] != null) {
      return TaskComment.fromJson(json);
    }
    return null;
  }

  Future<ApprovalActionResult> _approvalAction(
    String action,
    String approvalId, {
    String? workspaceId,
    required String requestId,
    String? reason,
  }) async {
    final body = <String, Object?>{'request_id': requestId};
    if (action == 'reject' && reason != null) body['reason'] = reason;
    final value = await _api.request(
      'POST',
      '${_approvalPath(workspaceId)}/$approvalId/$action',
      body: body,
      authenticated: true,
      headers: {'x-request-id': requestId},
    );
    if (value is! Map) {
      throw const FormatException('server returned an invalid approval result');
    }
    return ApprovalActionResult.fromJson(value.cast<String, dynamic>());
  }

  static TaskMutationResult? _taskMutation(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    if (json['pending'] == true && json['approval_request'] != null) {
      return PendingApproval.fromJson(json);
    }
    if (json['id'] != null && json['title'] != null) {
      return TaskItem.fromJson(json);
    }
    return null;
  }

  static String _approvalPath(String? workspaceId) =>
      '/api/v1/workspaces/${workspaceId ?? 'current'}/approval-requests';

  static String _newRequestId() {
    final random = Random();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
