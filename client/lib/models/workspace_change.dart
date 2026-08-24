import 'task.dart';

class WorkspaceChange {
  const WorkspaceChange({
    required this.cursor,
    required this.resourceType,
    required this.resourceId,
    required this.action,
    this.task,
  });

  final int cursor;
  final String resourceType;
  final String resourceId;
  final String action;
  final TaskItem? task;

  factory WorkspaceChange.taskUpdated({
    required int cursor,
    required TaskItem task,
  }) => WorkspaceChange(
    cursor: cursor,
    resourceType: 'task',
    resourceId: task.id,
    action: 'updated',
    task: task,
  );

  factory WorkspaceChange.fromJson(Map<String, dynamic> json) =>
      WorkspaceChange(
        cursor: json['cursor'] as int,
        resourceType: json['resource_type'] as String,
        resourceId: json['resource_id'] as String,
        action: json['action'] as String,
        task: json['resource_type'] == 'task' && json['resource'] != null
            ? TaskItem.fromJson(json['resource'] as Map<String, dynamic>)
            : null,
      );
}

class WorkspaceChanged {
  const WorkspaceChanged({required this.workspaceId, required this.cursor});

  final String workspaceId;
  final int cursor;
}

class WorkspaceChanges {
  const WorkspaceChanges({
    required this.workspaceId,
    required this.cursor,
    required this.changes,
  });

  final String workspaceId;
  final int cursor;
  final List<WorkspaceChange> changes;

  factory WorkspaceChanges.fromJson(Map<String, dynamic> json) =>
      WorkspaceChanges(
        workspaceId: json['workspace_id'] as String,
        cursor: json['cursor'] as int,
        changes: (json['changes'] as List<dynamic>? ?? const [])
            .map(
              (item) => WorkspaceChange.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}
