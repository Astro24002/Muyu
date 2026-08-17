import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../task/task_controller.dart';

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    required this.controller,
    required this.sessionController,
    this.parentTaskId,
  });

  final TaskController controller;
  final SessionController sessionController;
  final String? parentTaskId;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _estimatedMinutes = TextEditingController();
  late final Set<String> _assigneeIds;
  late String _handlerId;
  DateTime? _plannedStart;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _handlerId = widget.sessionController.currentUser!.id;
    _assigneeIds = {_handlerId};
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimatedMinutes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool due) async {
    final initial = (due ? _dueDate : _plannedStart) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (due) {
        _dueDate = selected;
      } else {
        _plannedStart = selected;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final estimate = _estimatedMinutes.text.trim().isEmpty
        ? null
        : int.tryParse(_estimatedMinutes.text.trim());
    final result = await widget.controller.create(
      title: _title.text.trim(),
      description: _description.text.trim(),
      assigneeIds: _assigneeIds.toList(),
      currentHandlerId: _handlerId,
      parentTaskId: widget.parentTaskId,
      plannedStartAt: _plannedStart,
      dueAt: _dueDate,
      estimatedMinutes: estimate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.errorMessage ?? '任务保存失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.sessionController.users.isEmpty
        ? [widget.sessionController.currentUser!]
        : widget.sessionController.users;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parentTaskId == null ? '新建任务' : '新建子任务'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              TextFormField(
                key: const Key('task-title-field'),
                controller: _title,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '标题'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入任务标题' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 4,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: '描述'),
              ),
              const SizedBox(height: 20),
              Text('参与人', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ...users.map(
                (user) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(user.nickname),
                  value: _assigneeIds.contains(user.id),
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        _assigneeIds.add(user.id);
                      } else if (_assigneeIds.length > 1) {
                        _assigneeIds.remove(user.id);
                        if (_handlerId == user.id) {
                          _handlerId = _assigneeIds.first;
                        }
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _handlerId,
                decoration: const InputDecoration(labelText: '当前负责人'),
                items: users
                    .where((user) => _assigneeIds.contains(user.id))
                    .map(
                      (user) => DropdownMenuItem(
                        value: user.id,
                        child: Text(user.nickname),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _handlerId = value);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _estimatedMinutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '预计耗时（分钟）'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final parsed = int.tryParse(value.trim());
                  return parsed == null || parsed <= 0 ? '请输入正整数' : null;
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      _plannedStart == null
                          ? '计划开始'
                          : _dateLabel(_plannedStart!),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _dueDate == null ? '截止日期' : _dateLabel(_dueDate!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存任务'),
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
