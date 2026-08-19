import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/user.dart';

class TaskDelayInput {
  const TaskDelayInput({
    required this.newDueAt,
    required this.reason,
    this.note,
  });

  final DateTime newDueAt;
  final String reason;
  final String? note;
}

class TaskBlockInput {
  const TaskBlockInput({
    required this.blockedReason,
    required this.resumeHandlerId,
    this.waitingForUserId,
  });

  final String blockedReason;
  final String resumeHandlerId;
  final String? waitingForUserId;
}

typedef TaskDelaySubmit = Future<String?> Function(TaskDelayInput input);
typedef TaskBlockSubmit = Future<String?> Function(TaskBlockInput input);

Future<bool?> showTaskDelayDialog(
  BuildContext context, {
  required DateTime currentDueAt,
  required TaskDelaySubmit onSubmit,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _TaskDelayDialog(currentDueAt: currentDueAt, onSubmit: onSubmit),
);

Future<bool?> showTaskBlockDialog(
  BuildContext context, {
  required List<User> users,
  required List<String> assigneeIds,
  required String currentHandlerId,
  required TaskBlockSubmit onSubmit,
}) {
  final assignees = users
      .where((user) => assigneeIds.contains(user.id))
      .toList();
  return showDialog<bool>(
    context: context,
    builder: (_) => _TaskBlockDialog(
      users: users,
      assignees: assignees,
      currentHandlerId: currentHandlerId,
      onSubmit: onSubmit,
    ),
  );
}

class _TaskDelayDialog extends StatefulWidget {
  const _TaskDelayDialog({required this.currentDueAt, required this.onSubmit});

  final DateTime currentDueAt;
  final TaskDelaySubmit onSubmit;

  @override
  State<_TaskDelayDialog> createState() => _TaskDelayDialogState();
}

class _TaskDelayDialogState extends State<_TaskDelayDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  late DateTime _newDueAt;
  String _reason = 'NO_TIME';
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _newDueAt = widget.currentDueAt.toLocal().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _newDueAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _newDueAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _newDueAt.hour,
        _newDueAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_newDueAt),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _newDueAt = DateTime(
        _newDueAt.year,
        _newDueAt.month,
        _newDueAt.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newDueAt.toUtc().difference(widget.currentDueAt.toUtc()) <
        const Duration(minutes: 1)) {
      setState(() => _error = '新截止时间必须晚于当前截止时间至少 1 分钟');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(
        TaskDelayInput(
          newDueAt: _newDueAt,
          reason: _reason,
          note: _reason == 'OTHER' ? _note.text.trim() : null,
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('延期任务'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text('日期 ${_dateLabel(_newDueAt)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text('时间 ${_timeLabel(_newDueAt)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('task-delay-reason'),
                initialValue: _reason,
                decoration: const InputDecoration(labelText: '延期原因'),
                items: taskDelayReasonLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _reason = value;
                            _error = null;
                          });
                        }
                      },
              ),
              if (_reason == 'OTHER') ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('task-delay-note'),
                  controller: _note,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: '补充说明'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写补充说明' : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('task-delay-submit'),
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('确认延期'),
      ),
    ],
  );
}

class _TaskBlockDialog extends StatefulWidget {
  const _TaskBlockDialog({
    required this.users,
    required this.assignees,
    required this.currentHandlerId,
    required this.onSubmit,
  });

  final List<User> users;
  final List<User> assignees;
  final String currentHandlerId;
  final TaskBlockSubmit onSubmit;

  @override
  State<_TaskBlockDialog> createState() => _TaskBlockDialogState();
}

class _TaskBlockDialogState extends State<_TaskBlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late String _resumeHandlerId;
  String _waitingForUserId = '';
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resumeHandlerId =
        widget.assignees
            .where((user) => user.id == widget.currentHandlerId)
            .map((user) => user.id)
            .firstOrNull ??
        widget.assignees.firstOrNull?.id ??
        widget.currentHandlerId;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(
        TaskBlockInput(
          blockedReason: _reason.text.trim(),
          resumeHandlerId: _resumeHandlerId,
          waitingForUserId: _waitingForUserId.isEmpty
              ? null
              : _waitingForUserId,
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('阻塞任务'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('task-block-reason'),
                controller: _reason,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: '阻塞原因'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入阻塞原因' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _resumeHandlerId,
                decoration: const InputDecoration(labelText: '解除后负责人'),
                items: widget.assignees
                    .map(
                      (user) => DropdownMenuItem(
                        value: user.id,
                        child: Text(user.nickname),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _resumeHandlerId = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _waitingForUserId,
                decoration: const InputDecoration(labelText: '等待成员（可选）'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('不指定')),
                  ...widget.users.map(
                    (user) => DropdownMenuItem(
                      value: user.id,
                      child: Text(user.nickname),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _waitingForUserId = value);
                        }
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('task-block-submit'),
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('确认阻塞'),
      ),
    ],
  );
}

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
