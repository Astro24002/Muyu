import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../task/task_controller.dart';
import '../task/task_repository.dart';
import 'task_action_dialogs.dart';
import 'task_form_screen.dart';
import 'task_list_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.initialTask,
    required this.controller,
    required this.repository,
    required this.sessionController,
  });

  final TaskItem initialTask;
  final TaskController controller;
  final TaskRepository repository;
  final SessionController sessionController;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late final TaskController _subtasks;
  late final TaskController _delays;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _subtasks = TaskController(widget.repository)
      ..load(parentTaskId: widget.initialTask.id);
    _delays = TaskController(widget.repository)
      ..loadDelays(widget.initialTask.id);
  }

  @override
  void dispose() {
    _subtasks.dispose();
    _delays.dispose();
    super.dispose();
  }

  TaskItem get _task => widget.controller.tasks.firstWhere(
    (task) => task.id == widget.initialTask.id,
    orElse: () => widget.initialTask,
  );

  String _userName(String id) =>
      widget.sessionController.users
          .where((user) => user.id == id)
          .map((user) => user.nickname)
          .firstOrNull ??
      (widget.sessionController.currentUser?.id == id
          ? widget.sessionController.currentUser!.nickname
          : '未知成员');

  List<User> get _users {
    if (widget.sessionController.users.isNotEmpty) {
      return widget.sessionController.users;
    }
    final current = widget.sessionController.currentUser;
    return current == null ? const [] : [current];
  }

  Future<void> _showDelay() async {
    final task = _task;
    final dueAt = task.dueAt;
    if (dueAt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先设置截止时间，再进行延期')));
      return;
    }
    setState(() => _dialogOpen = true);
    await showTaskDelayDialog(
      context,
      currentDueAt: dueAt,
      onSubmit: (input) async {
        final updated = await widget.controller.delay(
          task.id,
          newDueAt: input.newDueAt,
          reason: input.reason,
          note: input.note,
        );
        if (!updated) {
          return widget.controller.errorMessage ?? '延期失败';
        }
        await _delays.loadDelays(task.id);
        return null;
      },
    );
    if (mounted) setState(() => _dialogOpen = false);
  }

  Future<void> _showBlock() async {
    final task = _task;
    setState(() => _dialogOpen = true);
    await showTaskBlockDialog(
      context,
      users: _users,
      assigneeIds: task.assigneeIds,
      currentHandlerId: task.currentHandlerId,
      onSubmit: (input) async {
        final updated = await widget.controller.block(
          task.id,
          blockedReason: input.blockedReason,
          resumeHandlerId: input.resumeHandlerId,
          waitingForUserId: input.waitingForUserId,
        );
        if (!updated) {
          return widget.controller.errorMessage ?? '阻塞失败';
        }
        return null;
      },
    );
    if (mounted) setState(() => _dialogOpen = false);
  }

  Future<void> _unblock() async {
    await widget.controller.unblock(_task.id);
  }

  Future<void> _addSubtask() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          controller: _subtasks,
          sessionController: widget.sessionController,
          parentTaskId: _task.id,
        ),
      ),
    );
    if (created == true) await _subtasks.load(parentTaskId: _task.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, _subtasks, _delays]),
    builder: (context, _) {
      final task = _task;
      return Scaffold(
        appBar: AppBar(title: const Text('任务详情')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(taskStatusLabel(task.status)),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(task.description),
              ],
              const SizedBox(height: 24),
              _DetailRow(
                icon: Icons.person_outline,
                label: '当前负责人',
                value: _userName(task.currentHandlerId),
              ),
              _DetailRow(
                icon: Icons.group_outlined,
                label: '参与人',
                value: task.assigneeIds.map(_userName).join('、'),
              ),
              if (task.status == 'WAITING') ...[
                _DetailRow(
                  icon: Icons.pause_circle_outline,
                  label: '阻塞原因',
                  value: task.blockedReason ?? '未填写',
                ),
                if (task.blockedSince != null)
                  _DetailRow(
                    icon: Icons.access_time_outlined,
                    label: '阻塞开始',
                    value: _dateTimeLabel(task.blockedSince!),
                  ),
                if (task.waitingForUserId != null)
                  _DetailRow(
                    icon: Icons.hourglass_empty,
                    label: '等待成员',
                    value: _userName(task.waitingForUserId!),
                  ),
                if (task.resumeHandlerId != null)
                  _DetailRow(
                    icon: Icons.person_pin_outlined,
                    label: '恢复负责人',
                    value: _userName(task.resumeHandlerId!),
                  ),
              ],
              if (task.estimatedMinutes != null)
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  label: '预计耗时',
                  value: '${task.estimatedMinutes} 分钟',
                ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (task.status == 'TODO')
                    FilledButton.icon(
                      onPressed: () => widget.controller.start(task.id),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始'),
                    ),
                  if (task.status == 'TODO' ||
                      task.status == 'IN_PROGRESS' ||
                      task.status == 'WAITING')
                    FilledButton.tonalIcon(
                      onPressed: () => widget.controller.complete(task.id),
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                    ),
                  if (task.status == 'TODO' ||
                      task.status == 'IN_PROGRESS' ||
                      task.status == 'WAITING')
                    OutlinedButton.icon(
                      onPressed: () => widget.controller.cancel(task.id),
                      icon: const Icon(Icons.close),
                      label: const Text('取消'),
                    ),
                  if (task.status == 'TODO' || task.status == 'IN_PROGRESS')
                    OutlinedButton.icon(
                      onPressed: _showBlock,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('阻塞'),
                    ),
                  if ((task.status == 'TODO' || task.status == 'IN_PROGRESS') &&
                      task.dueAt != null)
                    OutlinedButton.icon(
                      onPressed: _showDelay,
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('延期'),
                    ),
                  if (task.status == 'WAITING')
                    FilledButton.icon(
                      onPressed: _unblock,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('解除阻塞'),
                    ),
                  if (task.status == 'DONE' || task.status == 'CANCELLED')
                    FilledButton.icon(
                      onPressed: () => widget.controller.reopen(task.id),
                      icon: const Icon(Icons.replay),
                      label: const Text('重开'),
                    ),
                  if (task.assigneeIds.length > 1)
                    PopupMenuButton<String>(
                      tooltip: '转交负责人',
                      icon: const Icon(Icons.swap_horiz),
                      onSelected: (userId) =>
                          widget.controller.transfer(task.id, userId),
                      itemBuilder: (_) => task.assigneeIds
                          .where((id) => id != task.currentHandlerId)
                          .map(
                            (id) => PopupMenuItem(
                              value: id,
                              child: Text(_userName(id)),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
              if (!_dialogOpen && widget.controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (task.delayCount > 0 || task.totalDelayMinutes > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '延期 ${task.delayCount} 次 · 累计 ${task.totalDelayMinutes} 分钟',
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),
              Text('延期记录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_delays.loading && _delays.delayRecords.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_delays.errorMessage != null &&
                  _delays.delayRecords.isEmpty)
                Text(
                  _delays.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (_delays.delayRecords.isEmpty)
                const Text('暂无延期记录')
              else
                ..._delays.delayRecords.map(
                  (record) => _DelayRecordTile(record: record),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '子任务',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '新建子任务',
                    onPressed: _addSubtask,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_subtasks.loading && _subtasks.tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_subtasks.tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('暂无子任务'),
                )
              else
                ..._subtasks.tasks.map(
                  (subtask) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(subtask.title),
                    subtitle: Text(taskStatusLabel(subtask.status)),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _DelayRecordTile extends StatelessWidget {
  const _DelayRecordTile({required this.record});

  final TaskDelayRecord record;

  @override
  Widget build(BuildContext context) {
    final reason = taskDelayReasonLabels[record.reason] ?? record.reason;
    final note = record.note == null || record.note!.isEmpty
        ? ''
        : ' · ${record.note}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history),
        title: Text(reason),
        subtitle: Text(
          '${_dateTimeLabel(record.originalDueAt)} -> '
          '${_dateTimeLabel(record.newDueAt)}\n'
          '${record.delayDurationMinutes} 分钟$note',
        ),
      ),
    );
  }
}

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
