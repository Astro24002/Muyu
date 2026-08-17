import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../models/task.dart';
import '../task/task_controller.dart';

class TaskListScreen extends StatelessWidget {
  const TaskListScreen({
    super.key,
    required this.controller,
    required this.sessionController,
    required this.onCreate,
    required this.onOpen,
  });

  final TaskController controller;
  final SessionController sessionController;
  final Future<void> Function({String? parentTaskId}) onCreate;
  final ValueChanged<TaskItem> onOpen;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.loading && controller.tasks.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.errorMessage != null && controller.tasks.isEmpty) {
        return _TaskError(
          message: controller.errorMessage!,
          onRetry: controller.load,
        );
      }
      if (controller.tasks.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.task_alt,
                  size: 48,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 16),
                Text('暂无任务', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('新建任务'),
                ),
              ],
            ),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: controller.tasks.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final task = controller.tasks[index];
            final handler = sessionController.users
                .where((user) => user.id == task.currentHandlerId)
                .firstOrNull;
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                onTap: () => onOpen(task),
                leading: Icon(_statusIcon(task.status)),
                title: Text(task.title),
                subtitle: Text(
                  '${_statusLabel(task.status)} · ${handler?.nickname ?? '未识别负责人'}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        ),
      );
    },
  );
}

class _TaskError extends StatelessWidget {
  const _TaskError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );
}

String taskStatusLabel(String status) => _statusLabel(status);

String _statusLabel(String status) => switch (status) {
  'TODO' => '待开始',
  'IN_PROGRESS' => '进行中',
  'WAITING' => '等待中',
  'DONE' => '已完成',
  'CANCELLED' => '已取消',
  _ => status,
};

IconData _statusIcon(String status) => switch (status) {
  'IN_PROGRESS' => Icons.play_circle_outline,
  'DONE' => Icons.check_circle_outline,
  'CANCELLED' => Icons.cancel_outlined,
  _ => Icons.radio_button_unchecked,
};
