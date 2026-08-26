import 'dart:math';

import '../core/api_client.dart';
import '../models/task.dart';
import 'task_mutation_journal.dart';

class CloudTaskFailure implements Exception {
  const CloudTaskFailure(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;
}

class CloudTaskRepository {
  CloudTaskRepository(this._api, {TaskMutationJournal? journal})
    : _journal = journal ?? MemoryTaskMutationJournal();

  final ApiClient _api;
  final TaskMutationJournal _journal;

  Future<TaskItem?> update(
    String taskId, {
    required Map<String, Object?> fields,
    required Map<String, int> fieldVersions,
    required String requestId,
  }) async {
    final body = <String, Object?>{
      'changes': fields,
      'base_field_versions': fieldVersions,
      'request_id': requestId,
    };
    final record = TaskMutationRecord(
      requestId: requestId,
      method: 'PATCH',
      path: '/api/v1/tasks/$taskId',
      body: body,
      createdAt: DateTime.now().toUtc(),
    );
    await _journal.put(record);
    try {
      final value = await _api.request(
        'PATCH',
        record.path,
        body: body,
        authenticated: true,
        headers: {'x-request-id': requestId},
      );
      await _journal.remove(requestId);
      if (value is! Map<String, dynamic> ||
          value['id'] == null ||
          !value.containsKey('title')) {
        return null;
      }
      return TaskItem.fromJson(value);
    } on ApiException catch (error) {
      // Keep the exact request for reconciliation; never mint a new ID here.
      throw CloudTaskFailure(
        error.message,
        code: error.code,
        statusCode: error.statusCode,
      );
    }
  }

  Future<TaskItem?> transition(String taskId, {required String targetStatus, required int baseStatusVersion, String? blockedReason, String? resumeHandlerId, String? waitingForUserId, required String requestId}) async {
    final value = await _api.request('POST', '/api/v1/tasks/$taskId/transition', body: {
      'request_id': requestId, 'target_status': targetStatus, 'base_status_version': baseStatusVersion,
      'blocked_reason': blockedReason, 'resume_handler_id': resumeHandlerId, 'waiting_for_user_id': waitingForUserId,
    }, authenticated: true, headers: {'x-request-id': requestId});
    return value is Map<String, dynamic> && value['id'] != null ? TaskItem.fromJson(value) : null;
  }

  Future<Object?> addComment(String taskId, {required String body, required String requestId}) => _api.request('POST', '/api/v1/tasks/$taskId/comments', body: {'request_id': requestId, 'body': body}, authenticated: true, headers: {'x-request-id': requestId});

  Future<Object?> addDelay(String taskId, {required String newDueAt, required String reason, String? note, required String requestId}) => _api.request('POST', '/api/v1/tasks/$taskId/delays', body: {'request_id': requestId, 'new_due_at': newDueAt, 'reason': reason, 'note': note}, authenticated: true, headers: {'x-request-id': requestId});

  String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<List<TaskMutationRecord>> inFlightMutations() => _journal.readAll();
}
