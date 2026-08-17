import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../models/task.dart';
import '../task/task_controller.dart';
import '../task/task_repository.dart';
import 'account_screen.dart';
import 'task_detail_screen.dart';
import 'task_form_screen.dart';
import 'task_list_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.sessionController,
    required this.taskRepository,
  });

  final SessionController sessionController;
  final TaskRepository taskRepository;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final TaskController _tasks;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tasks = TaskController(widget.taskRepository)..load();
    widget.sessionController.loadUsers();
  }

  @override
  void dispose() {
    _tasks.dispose();
    super.dispose();
  }

  Future<void> _createTask({String? parentTaskId}) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          controller: _tasks,
          sessionController: widget.sessionController,
          parentTaskId: parentTaskId,
        ),
      ),
    );
    if (created == true && mounted) await _tasks.load();
  }

  void _openTask(TaskItem task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          initialTask: task,
          controller: _tasks,
          repository: widget.taskRepository,
          sessionController: widget.sessionController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_index == 0 ? '任务' : '账户'),
      actions: _index == 1
          ? [
              IconButton(
                tooltip: '退出登录',
                onPressed: widget.sessionController.logout,
                icon: const Icon(Icons.logout),
              ),
              const SizedBox(width: 8),
            ]
          : [
              IconButton(
                tooltip: '刷新任务',
                onPressed: _tasks.load,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
            ],
    ),
    body: IndexedStack(
      index: _index,
      children: [
        TaskListScreen(
          controller: _tasks,
          sessionController: widget.sessionController,
          onCreate: _createTask,
          onOpen: _openTask,
        ),
        AccountScreen(controller: widget.sessionController, embedded: true),
      ],
    ),
    floatingActionButton: _index == 0
        ? FloatingActionButton(
            tooltip: '新建任务',
            onPressed: _createTask,
            child: const Icon(Icons.add),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          selectedIcon: Icon(Icons.checklist),
          label: '任务',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '账户',
        ),
      ],
    ),
  );
}
