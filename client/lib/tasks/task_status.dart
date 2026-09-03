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

String normalizeTaskStatus(String status) => switch (status) {
  'WAITING' => 'BLOCKED',
  'COMPLETED' => 'DONE',
  _ => status,
};

bool isCanonicalTaskStatus(String status) =>
    taskStatusLabels.containsKey(status);

String taskStatusLabel(String status) =>
    taskStatusLabels[normalizeTaskStatus(status)] ?? status;
