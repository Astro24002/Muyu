class WorkspaceClassification {
  static const maxNameLength = 5;

  const WorkspaceClassification({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.createdBy,
    this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String createdBy;
  final DateTime? createdAt;

  factory WorkspaceClassification.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final workspaceId = json['workspace_id'];
    final name = json['name'];
    final createdBy = json['created_by'];
    if (id is! String ||
        id.isEmpty ||
        workspaceId is! String ||
        workspaceId.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.trim().runes.length > maxNameLength ||
        createdBy is! String ||
        createdBy.isEmpty) {
      throw const FormatException('workspace classification is invalid');
    }
    return WorkspaceClassification(
      id: id,
      workspaceId: workspaceId,
      name: name.trim(),
      createdBy: createdBy,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'workspace_id': workspaceId,
    'name': name,
    'created_by': createdBy,
    'created_at': createdAt?.toUtc().toIso8601String(),
  };
}
