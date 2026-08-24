class TaskConflict {
  const TaskConflict({
    required this.id,
    required this.taskId,
    required this.target,
    required this.baseline,
    required this.current,
    required this.proposed,
    required this.state,
  });

  final String id;
  final String taskId;
  final String target;
  final Object? baseline;
  final Object? current;
  final Object? proposed;
  final String state;

  factory TaskConflict.fromJson(Map<String, dynamic> json) => TaskConflict(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    target: json['target'] as String,
    baseline: json['baseline'],
    current: json['current'],
    proposed: json['proposed'],
    state: json['state'] as String,
  );
}
