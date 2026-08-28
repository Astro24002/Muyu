import 'package:flutter/material.dart';

import '../models/task.dart';
import '../sync/workspace_sync_controller.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.sync,
    this.canWrite = true,
  });

  final TaskItem task;
  final WorkspaceSyncController sync;
  final bool canWrite;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _dueAt;
  late final TextEditingController _plannedStartAt;
  late final TextEditingController _estimatedMinutes;
  final _comment = TextEditingController();
  late Set<String> _selectedAssignees;
  bool _saving = false;
  bool _commenting = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task.title);
    _description = TextEditingController(text: widget.task.description);
    _dueAt = TextEditingController(text: _dateText(widget.task.dueAt));
    _plannedStartAt = TextEditingController(
      text: _dateText(widget.task.plannedStartAt),
    );
    _estimatedMinutes = TextEditingController(
      text: widget.task.estimatedMinutes?.toString() ?? '',
    );
    _selectedAssignees = widget.task.assigneeIds.toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _dueAt.dispose();
    _plannedStartAt.dispose();
    _estimatedMinutes.dispose();
    _comment.dispose();
    super.dispose();
  }

  TaskItem get _current {
    for (final task
        in widget.sync.state.snapshot?.tasks ?? const <TaskItem>[]) {
      if (task.id == widget.task.id) return task;
    }
    return widget.task;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (!widget.canWrite || title.isEmpty || _saving) return;
    final estimateText = _estimatedMinutes.text.trim();
    final estimate = estimateText.isEmpty ? null : int.tryParse(estimateText);
    if (estimateText.isNotEmpty && (estimate == null || estimate < 0)) {
      setState(() {});
      return;
    }
    final current = _current;
    final fields = <String, Object?>{
      if (title != current.title) 'title': title,
      if (_description.text.trim() != current.description)
        'description': _description.text.trim(),
      if (_dateValue(_dueAt.text) != current.dueAt?.toIso8601String())
        'due_at': _dateValue(_dueAt.text),
      if (_dateValue(_plannedStartAt.text) !=
          current.plannedStartAt?.toIso8601String())
        'planned_start_at': _dateValue(_plannedStartAt.text),
      if (estimate != current.estimatedMinutes) 'estimated_minutes': estimate,
      if (!_sameIds(_selectedAssignees, current.assigneeIds))
        'assignee_ids': _selectedAssignees.toList(),
    };
    if (fields.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.sync.update(current.id, fields: fields);
    } catch (_) {
      // The controller exposes the authoritative error in its state.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addComment() async {
    final body = _comment.text.trim();
    if (!widget.canWrite || body.isEmpty || _commenting) return;
    setState(() => _commenting = true);
    try {
      await widget.sync.addComment(_current.id, body);
      if (mounted) _comment.clear();
    } catch (_) {
      // Keep the draft on failure.
    } finally {
      if (mounted) setState(() => _commenting = false);
    }
  }

  Future<void> _addDelay() async {
    if (!widget.canWrite) return;
    final note = TextEditingController();
    var selectedReason = 'OTHER';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录延期'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (context, setDialogState) =>
                  DropdownButtonFormField<String>(
                    key: const Key('delay-reason-input'),
                    initialValue: selectedReason,
                    decoration: const InputDecoration(labelText: '延期原因'),
                    items: taskDelayReasonLabels.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedReason = value);
                      }
                    },
                  ),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('delay-submit'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      note.dispose();
      return;
    }
    try {
      await widget.sync.addDelay(
        _current.id,
        newDueAt: (_current.dueAt ?? DateTime.now())
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        reason: selectedReason,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
    } catch (_) {
      // Keep the error in the sync banner.
    } finally {
      note.dispose();
    }
  }

  Future<void> _resolveConflict(String conflictId, String resolution) async {
    if (!widget.canWrite) return;
    try {
      await widget.sync.resolveConflict(
        _current.id,
        conflictId,
        resolution: resolution,
      );
    } catch (_) {
      // Keep the error in the sync banner.
    }
  }

  Future<void> _transition(String status) async {
    if (!widget.canWrite) return;
    String? blockedReason;
    if (status == 'WAITING') {
      blockedReason = await showDialog<String>(
        context: context,
        builder: (context) {
          var selected = 'WAITING_PARTNER';
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('选择等待原因'),
              content: DropdownButtonFormField<String>(
                initialValue: selected,
                items: taskDelayReasonLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selected = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('确认'),
                ),
              ],
            ),
          );
        },
      );
      if (blockedReason == null) return;
    }
    try {
      final task = _current;
      await widget.sync.transition(
        task.id,
        status,
        blockedReason: blockedReason,
        resumeHandlerId: status == 'WAITING' ? task.currentHandlerId : null,
      );
    } catch (_) {
      // Keep the error in the sync banner.
    }
  }

  Future<void> _changeHandler(String? handlerId) async {
    if (!widget.canWrite) return;
    if (handlerId == null || handlerId == _current.currentHandlerId) return;
    try {
      await widget.sync.update(
        _current.id,
        fields: {'current_handler_id': handlerId},
      );
    } catch (_) {
      // Keep the error in the sync banner.
    }
  }

  static String _dateText(DateTime? value) =>
      value?.toUtc().toIso8601String() ?? '';

  static String? _dateValue(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc().toIso8601String();
  }

  static bool _sameIds(Set<String> selected, List<String> current) =>
      selected.length == current.length && selected.containsAll(current);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.sync,
    builder: (context, _) {
      final task = _current;
      final conflicts = (widget.sync.state.snapshot?.conflicts ?? const [])
          .where(
            (item) =>
                item['task_id'] == task.id && item['status'] != 'RESOLVED',
          )
          .toList();
      final members = widget.sync.state.snapshot?.members ?? const [];
      final handlerIds = members
          .map((member) => member['user_id'] as String?)
          .whereType<String>()
          .where(task.assigneeIds.contains)
          .toSet()
          .toList();
      if (handlerIds.isEmpty) handlerIds.addAll(task.assigneeIds);
      final assigneeOptions = members
          .map((member) => member['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      for (final id in task.assigneeIds) {
        if (!assigneeOptions.contains(id)) assigneeOptions.add(id);
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(task.title),
          actions: [
            IconButton(
              key: const Key('task-save-button'),
              tooltip: '保存任务',
              onPressed: !widget.canWrite || _saving || task.deletedAt != null
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.sync.state.errorMessage != null)
              Text(
                widget.sync.state.errorMessage!,
                key: const Key('task-error'),
              ),
            TextField(
              key: const Key('task-detail-title'),
              controller: _title,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('task-detail-description'),
              controller: _description,
              maxLines: 3,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('task-detail-due-at'),
              controller: _dueAt,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '截止时间（ISO 8601，可选）'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('task-detail-planned-start-at'),
              controller: _plannedStartAt,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '计划开始（ISO 8601，可选）'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('task-detail-estimated-minutes'),
              controller: _estimatedMinutes,
              keyboardType: TextInputType.number,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '预计工时（分钟）'),
            ),
            if (assigneeOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('协作者（最多 2 人）'),
              Wrap(
                spacing: 8,
                children: [
                  for (final id in assigneeOptions)
                    FilterChip(
                      key: Key('task-assignee-$id'),
                      label: Text(id),
                      selected: _selectedAssignees.contains(id),
                      onSelected: !widget.canWrite || task.deletedAt != null
                          ? null
                          : (selected) {
                              if (!selected && _selectedAssignees.length <= 1) {
                                return;
                              }
                              if (selected && _selectedAssignees.length >= 2) {
                                return;
                              }
                              setState(() {
                                if (selected) {
                                  _selectedAssignees.add(id);
                                } else {
                                  _selectedAssignees.remove(id);
                                }
                              });
                            },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('状态：${task.status}'),
            if (handlerIds.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('task-handler-select'),
                initialValue: handlerIds.contains(task.currentHandlerId)
                    ? task.currentHandlerId
                    : handlerIds.first,
                decoration: const InputDecoration(labelText: '负责人'),
                items: handlerIds
                    .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                    .toList(),
                onChanged: !widget.canWrite || task.deletedAt != null
                    ? null
                    : _changeHandler,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in const [
                  'IN_PROGRESS',
                  'WAITING',
                  'DONE',
                  'CANCELLED',
                  'TODO',
                ])
                  OutlinedButton(
                    key: Key('task-status-${status.toLowerCase()}'),
                    onPressed: !widget.canWrite || task.deletedAt != null
                        ? null
                        : () => _transition(status),
                    child: Text(status),
                  ),
                OutlinedButton(
                  key: const Key('task-delay-button'),
                  onPressed: !widget.canWrite || task.deletedAt != null
                      ? null
                      : _addDelay,
                  child: const Text('记录延期'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('task-comment-input'),
              controller: _comment,
              enabled: widget.canWrite,
              decoration: InputDecoration(
                labelText: '添加评论',
                suffixIcon: IconButton(
                  key: const Key('task-comment-submit'),
                  tooltip: '发送评论',
                  onPressed: !widget.canWrite || _commenting
                      ? null
                      : _addComment,
                  icon: _commenting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ),
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('待解决冲突'),
              for (final conflict in conflicts)
                Card(
                  child: ListTile(
                    title: Text('冲突 ${conflict['id']}'),
                    trailing: Wrap(
                      children: [
                        TextButton(
                          key: Key('resolve-conflict-${conflict['id']}'),
                          onPressed: widget.canWrite
                              ? () => _resolveConflict(
                                  conflict['id'] as String,
                                  'current',
                                )
                              : null,
                          child: const Text('保留当前'),
                        ),
                        TextButton(
                          onPressed: widget.canWrite
                              ? () => _resolveConflict(
                                  conflict['id'] as String,
                                  'proposed',
                                )
                              : null,
                          child: const Text('采用对方'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
