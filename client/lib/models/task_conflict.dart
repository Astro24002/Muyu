class TaskConflict {
  const TaskConflict({
    required this.id,
    required this.taskId,
    required this.target,
    required this.baseline,
    required this.current,
    required this.proposed,
    required this.state,
    this.proposedPayload,
    this.baseVersion,
    this.currentVersion,
    this.baseStatusVersion,
    this.currentStatusVersion,
    this.fieldVersions = const {},
    this.statusVersion,
    this.lifecycleVersion,
    this.currentSnapshot,
  });

  final String id;
  final String taskId;
  final String target;
  final Object? baseline;
  final Object? current;
  final Object? proposed;
  final String state;
  final Map<String, dynamic>? proposedPayload;
  final int? baseVersion;
  final int? currentVersion;
  final int? baseStatusVersion;
  final int? currentStatusVersion;
  final Map<String, int> fieldVersions;
  final int? statusVersion;
  final int? lifecycleVersion;
  final Map<String, dynamic>? currentSnapshot;

  factory TaskConflict.fromJson(Map<String, dynamic> json) {
    final proposed = json['proposed'] ?? json['proposed_payload'];
    final proposedPayload = proposed is Map
        ? proposed.map((key, value) => MapEntry(key.toString(), value))
        : null;
    final currentSnapshot = json['current_snapshot'];
    final rawVersions = json['field_versions'];
    final fieldVersions = rawVersions is Map
        ? rawVersions.map(
            (key, value) => MapEntry(key.toString(), (value as num).toInt()),
          )
        : const <String, int>{};
    return TaskConflict(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      target: (json['target'] ?? json['field']) as String,
      baseline: json['baseline'] ?? json['base'],
      current: json['current'],
      proposed: proposed,
      state: (json['state'] ?? json['status']) as String,
      proposedPayload: proposedPayload,
      baseVersion: (json['base_version'] as num?)?.toInt(),
      currentVersion: (json['current_version'] as num?)?.toInt(),
      baseStatusVersion: (json['base_status_version'] as num?)?.toInt(),
      currentStatusVersion: (json['current_status_version'] as num?)?.toInt(),
      fieldVersions: fieldVersions,
      statusVersion: (json['status_version'] as num?)?.toInt(),
      lifecycleVersion: (json['lifecycle_version'] as num?)?.toInt(),
      currentSnapshot: currentSnapshot is Map
          ? currentSnapshot.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }
}
