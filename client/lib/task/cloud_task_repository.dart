import 'dart:math';

import '../core/api_client.dart';
import '../models/task.dart';
import 'task_mutation_journal.dart';

class CloudTaskFailure implements Exception {
  const CloudTaskFailure(
    this.message, {
    this.code,
    this.statusCode,
    this.details,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final Object? details;
}

class CloudTaskRepository {
  CloudTaskRepository(this._api, {TaskMutationJournal? journal})
    : _journal = journal ?? MemoryTaskMutationJournal();

  final ApiClient _api;
  final TaskMutationJournal _journal;

  Future<TaskItem> create({
    required String title,
    String? description,
    String? dueAt,
    String? parentTaskId,
    List<String>? assigneeIds,
    String? plannedStartAt,
    int? estimatedMinutes,
    String? requestId,
  }) async {
    final id = requestId ?? newRequestId();
    final body = <String, Object?>{'request_id': id, 'title': title};
    if (description != null) body['description'] = description;
    if (dueAt != null) body['due_at'] = dueAt;
    if (parentTaskId != null) body['parent_task_id'] = parentTaskId;
    if (assigneeIds != null) body['assignee_ids'] = assigneeIds;
    if (plannedStartAt != null) body['planned_start_at'] = plannedStartAt;
    if (estimatedMinutes != null) body['estimated_minutes'] = estimatedMinutes;
    return _taskRequest('POST', '/api/v1/tasks', body, id);
  }

  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    String? requestId,
  }) async {
    final id = requestId ?? newRequestId();
    final body = <String, Object?>{
      'changes': fields,
      'base_field_versions': fieldVersions,
      'request_id': id,
    };
    final value = await _write('PATCH', '/api/v1/tasks/$taskId', body);
    return value is Map<String, dynamic> &&
            value['id'] != null &&
            value.containsKey('title')
        ? TaskItem.fromJson(value)
        : null;
  }

  Future<TaskItem> transition(
    String taskId, {
    required String targetStatus,
    required int baseStatusVersion,
    String? blockedReason,
    String? resumeHandlerId,
    String? waitingForUserId,
    String? requestId,
  }) async {
    final id = requestId ?? newRequestId();
    return _taskRequest('POST', '/api/v1/tasks/$taskId/transition', {
      'request_id': id,
      'target_status': targetStatus,
      'base_status_version': baseStatusVersion,
      'blocked_reason': blockedReason,
      'resume_handler_id': resumeHandlerId,
      'waiting_for_user_id': waitingForUserId,
    }, id);
  }

  Future<Object?> addComment(
    String taskId, {
    required String body,
    String? requestId,
  }) => _write('POST', '/api/v1/tasks/$taskId/comments', {
    'request_id': requestId ?? newRequestId(),
    'body': body,
  });

  Future<Object?> addDelay(
    String taskId, {
    required String newDueAt,
    required String reason,
    String? note,
    String? requestId,
  }) => _write('POST', '/api/v1/tasks/$taskId/delays', {
    'request_id': requestId ?? newRequestId(),
    'new_due_at': newDueAt,
    'reason': reason,
    'note': note,
  });

  Future<TaskItem> resolveConflict(
    String taskId,
    String conflictId, {
    required String resolution,
    String? requestId,
  }) async {
    final id = requestId ?? newRequestId();
    return _taskRequest(
      'POST',
      '/api/v1/tasks/$taskId/conflicts/$conflictId/resolve',
      {'request_id': id, 'resolution': resolution},
      id,
    );
  }

  Future<Object?> _write(
    String method,
    String path,
    Map<String, Object?> body,
  ) async {
    final id = body['request_id']! as String;
    try {
      return await _api.request(
        method,
        path,
        body: body,
        authenticated: true,
        headers: {'x-request-id': id},
      );
    } on ApiException catch (error) {
      throw CloudTaskFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
        details: error.details,
      );
    }
  }

  Future<TaskItem> _taskRequest(
    String method,
    String path,
    Map<String, Object?> body,
    String requestId,
  ) async {
    final value = await _write(method, path, body);
    if (value is! Map<String, dynamic> || value['id'] == null) {
      throw const CloudTaskFailure('服务器返回了无效任务');
    }
    return TaskItem.fromJson(value);
  }

  String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<TaskMutationRecord>> inFlightMutations() => _journal.readAll();
}
