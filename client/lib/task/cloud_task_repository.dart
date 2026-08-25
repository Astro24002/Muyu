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

  String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<List<TaskMutationRecord>> inFlightMutations() => _journal.readAll();
}
