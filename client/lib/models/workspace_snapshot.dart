import 'task.dart';
import 'task_approval_request.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.workspaceId,
    required this.cursor,
    required this.tasks,
    this.viewerUserId,
    this.members = const [],
    this.conflicts = const [],
    this.comments = const [],
    this.approvalRequests = const [],
    this.fetchedAt,
  });

  final String workspaceId;
  final int cursor;
  final List<TaskItem> tasks;
  final String? viewerUserId;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> conflicts;
  final List<TaskComment> comments;
  final List<TaskApprovalRequest> approvalRequests;
  final DateTime? fetchedAt;

  factory WorkspaceSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => WorkspaceSnapshot(
    workspaceId: json['workspace_id'] as String,
    cursor: json['cursor'] as int,
    viewerUserId: json['viewer_user_id'] as String?,
    tasks: (json['tasks'] as List<dynamic>? ?? const [])
        .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
        .toList(),
    members: (json['members'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>(),
    conflicts: (json['conflicts'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>(),
    comments: (json['comments'] as List<dynamic>? ?? const [])
        .map((item) => TaskComment.fromJson(item as Map<String, dynamic>))
        .toList(),
    approvalRequests: (json['approval_requests'] as List<dynamic>? ?? const [])
        .map(
          (item) => TaskApprovalRequest.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    fetchedAt: json['fetched_at'] == null
        ? null
        : DateTime.parse(json['fetched_at'] as String),
  );

  Map<String, Object?> toJson() => {
    'workspace_id': workspaceId,
    'cursor': cursor,
    'viewer_user_id': viewerUserId,
    'tasks': tasks.map(_taskJson).toList(),
    'members': members,
    'conflicts': conflicts,
    'comments': comments.map((comment) => comment.toJson()).toList(),
    'approval_requests': approvalRequests
        .map((request) => request.toJson())
        .toList(),
    'fetched_at': fetchedAt?.toUtc().toIso8601String(),
  };

  static Map<String, Object?> _taskJson(TaskItem task) => task.toJson();
}
