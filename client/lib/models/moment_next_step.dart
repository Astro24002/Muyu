/// Viewer-specific action context returned by the task detail endpoint.
///
/// This is intentionally separate from the persisted task fields. Older
/// snapshot responses do not include `next_step`, so callers should treat a
/// missing value as an invitation to derive a best-effort local projection.
class MomentNextStep {
  const MomentNextStep({
    required this.kind,
    required this.label,
    required this.canAct,
    required this.actions,
    this.requestId,
  });

  final String kind;
  final String label;
  final String? requestId;
  final bool canAct;
  final List<String> actions;

  factory MomentNextStep.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('task next_step must be an object');
    }
    final kind = value['kind'];
    final label = value['label'];
    final canAct = value['can_act'];
    final rawActions = value['actions'];
    if (kind is! String ||
        kind.isEmpty ||
        label is! String ||
        label.isEmpty ||
        canAct is! bool ||
        rawActions is! List) {
      throw const FormatException('task next_step has invalid fields');
    }
    final actions = <String>[];
    for (final action in rawActions) {
      if (action is! String || action.isEmpty) {
        throw const FormatException('task next_step actions must be strings');
      }
      actions.add(action);
    }
    final requestId = value['request_id'];
    if (requestId != null && requestId is! String) {
      throw const FormatException('task next_step request_id must be a string');
    }
    return MomentNextStep(
      kind: kind,
      label: label,
      requestId: requestId as String?,
      canAct: canAct,
      actions: List.unmodifiable(actions),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'label': label,
    if (requestId != null) 'request_id': requestId,
    'can_act': canAct,
    'actions': actions,
  };
}

/// Alias used by task-detail code that treats the projection as task-local.
typedef TaskNextStep = MomentNextStep;
