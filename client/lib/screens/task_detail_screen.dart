import 'package:flutter/material.dart';

import '../models/task.dart';
import '../sync/workspace_sync_controller.dart';

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.task, required this.sync});
  final TaskItem task;
  final WorkspaceSyncController sync;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(task.title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(task.description),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final status in const ['IN_PROGRESS', 'WAITING', 'DONE'])
              ElevatedButton(
                onPressed: () => sync.transition(task.id, status),
                child: Text(status),
              ),
          ],
        ),
      ],
    ),
  );
}
