const taskStatuses = <String>[
  'TODO',
  'IN_PROGRESS',
  'BLOCKED',
  'REVIEW',
  'DONE',
  'CANCELLED',
];

const taskStatusLabels = <String, String>{
  'TODO': '待进行',
  'IN_PROGRESS': '进行中',
  'BLOCKED': '阻塞中',
  'REVIEW': '待验收',
  'DONE': '已完成',
  'CANCELLED': '已取消',
};

const taskStatusTransitions = <String, List<String>>{
  'TODO': ['IN_PROGRESS', 'BLOCKED', 'CANCELLED'],
  'IN_PROGRESS': ['BLOCKED', 'REVIEW', 'CANCELLED'],
  'BLOCKED': ['IN_PROGRESS', 'CANCELLED'],
  'REVIEW': ['DONE', 'IN_PROGRESS', 'CANCELLED'],
  'DONE': ['TODO', 'IN_PROGRESS', 'CANCELLED'],
  'CANCELLED': ['TODO', 'IN_PROGRESS'],
};

String normalizeTaskStatus(String status) => switch (status) {
  'WAITING' => 'BLOCKED',
  'COMPLETED' => 'DONE',
  _ => status,
};

bool isCanonicalTaskStatus(String status) =>
    taskStatusLabels.containsKey(status);

List<String> taskTransitionTargets({
  required String status,
  required String currentHandlerId,
  String? reviewerUserId,
  String? actorUserId,
}) {
  final currentStatus = normalizeTaskStatus(status);
  final targets = taskStatusTransitions[currentStatus];
  if (targets == null) return const [];
  return List.unmodifiable(
    targets.where((targetStatus) {
      if (currentStatus != 'REVIEW' ||
          (targetStatus != 'DONE' && targetStatus != 'IN_PROGRESS')) {
        return true;
      }
      return actorUserId != null &&
          actorUserId == reviewerUserId &&
          actorUserId != currentHandlerId;
    }),
  );
}

bool isTaskTransitionAllowed({
  required String status,
  required String targetStatus,
  required String currentHandlerId,
  String? reviewerUserId,
  String? actorUserId,
}) => taskTransitionTargets(
  status: status,
  currentHandlerId: currentHandlerId,
  reviewerUserId: reviewerUserId,
  actorUserId: actorUserId,
).contains(targetStatus);

String taskStatusLabel(String status) =>
    taskStatusLabels[normalizeTaskStatus(status)] ?? status;
