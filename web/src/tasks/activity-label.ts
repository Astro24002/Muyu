const labels: Record<string, string> = {
  CREATED: '创建任务',
  UPDATED: '更新任务',
  STATUS_CHANGED: '更新状态',
  HANDLER_CHANGED: '转移负责人',
  DELETED: '删除任务',
  RESTORED: '恢复任务',
  COMMENTED: '添加评论',
  DELAYED: '延期任务',
  CONFLICT_CREATED: '产生冲突',
  CONFLICT_RESOLVED: '解决冲突',
  // Keep compatibility with the original Web activity vocabulary.
  CREATE: '创建任务',
  UPDATE: '更新任务',
  PATCH: '更新任务',
  TRANSITION: '更新状态',
  DELETE: '删除任务',
  RESTORE: '恢复任务',
};

export function activityLabel(operationType: string): string {
  return labels[operationType] ?? operationType;
}
