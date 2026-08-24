class TaskMutationRecord {
  const TaskMutationRecord({
    required this.requestId,
    required this.method,
    required this.path,
    required this.body,
    required this.createdAt,
  });

  final String requestId;
  final String method;
  final String path;
  final Map<String, Object?> body;
  final DateTime createdAt;
}

abstract interface class TaskMutationJournal {
  Future<void> put(TaskMutationRecord record);

  Future<void> remove(String requestId);

  Future<List<TaskMutationRecord>> readAll();
}

class MemoryTaskMutationJournal implements TaskMutationJournal {
  final _values = <String, TaskMutationRecord>{};

  @override
  Future<void> put(TaskMutationRecord record) async =>
      _values[record.requestId] = record;

  @override
  Future<void> remove(String requestId) async => _values.remove(requestId);

  @override
  Future<List<TaskMutationRecord>> readAll() async => _values.values.toList();
}
