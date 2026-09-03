import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_approval_request.dart';
import '../tasks/task_status.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';

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
  final _label = TextEditingController();
  final _comment = TextEditingController();
  late String _selectedQuadrant;
  late List<String> _selectedLabels;
  String? _labelError;
  String? _handlerError;
  String? _selectedResumeHandlerId;
  int? _selectedProgress;
  bool _saving = false;
  bool _commenting = false;
  String? _pendingMessage;

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
    _selectedLabels = _normalizeLabels(widget.task.labels);
    _selectedQuadrant = widget.task.quadrant;
    _selectedResumeHandlerId =
        widget.task.resumeHandlerId ?? widget.task.currentHandlerId;
    _selectedProgress = widget.task.progress;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _dueAt.dispose();
    _plannedStartAt.dispose();
    _estimatedMinutes.dispose();
    _label.dispose();
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

  static const _quadrantLabels = <String, String>{
    'Q1': 'Q1 重要且紧急',
    'Q2': 'Q2 重要不紧急',
    'Q3': 'Q3 紧急不重要',
    'Q4': 'Q4 不重要不紧急',
  };
  static const _maxLabelTotalLength = 320;

  static List<String> _normalizeLabels(Iterable<String> labels) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in labels) {
      final label = value.trim();
      if (label.isEmpty || !seen.add(label.toLowerCase())) continue;
      result.add(label);
    }
    return result;
  }

  static bool _sameLabels(Iterable<String> left, Iterable<String> right) {
    final normalizedLeft = _normalizeLabels(left);
    final normalizedRight = _normalizeLabels(right);
    if (normalizedLeft.length != normalizedRight.length) return false;
    for (var index = 0; index < normalizedLeft.length; index++) {
      if (normalizedLeft[index].toLowerCase() !=
          normalizedRight[index].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  static Set<String> _activeHandlerIds(Iterable<Map<String, dynamic>> members) {
    final ids = <String>{};
    for (final member in members) {
      final status = member['membership_status'] ?? member['status'];
      if (status is String && status != 'ACTIVE') continue;
      final userId = member['user_id'];
      if (userId is String && userId.isNotEmpty) ids.add(userId);
    }
    return ids;
  }

  static Map<String, String> _handlerLabels(
    Iterable<Map<String, dynamic>> members,
  ) {
    final labels = <String, String>{};
    for (final member in members) {
      final userId = member['user_id'];
      if (userId is! String || userId.isEmpty) continue;
      final displayName = member['display_name'];
      labels[userId] = displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : userId;
    }
    return labels;
  }

  static List<String> _handlerOptionIds(
    Set<String> activeHandlerIds,
    String storedHandlerId,
  ) => [
    ...activeHandlerIds,
    if (!activeHandlerIds.contains(storedHandlerId)) storedHandlerId,
  ];

  void _addLabel() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final normalized = label.toLowerCase();
    if (label.runes.length > 32) {
      setState(() => _labelError = '标签不能超过 32 个字符');
      return;
    }
    if (_selectedLabels.length >= 10) {
      setState(() => _labelError = '最多添加 10 个标签');
      return;
    }
    final totalLength = _selectedLabels.fold<int>(
      0,
      (total, item) => total + item.runes.length,
    );
    if (totalLength + label.runes.length > _maxLabelTotalLength) {
      setState(() => _labelError = '标签总长度不能超过 320 个字符');
      return;
    }
    if (_selectedLabels.any((item) => item.toLowerCase() == normalized)) {
      setState(() {
        _label.clear();
        _labelError = null;
      });
      return;
    }
    setState(() {
      _selectedLabels.add(label);
      _label.clear();
      _labelError = null;
    });
  }

  void _removeLabel(String label) {
    setState(() {
      _selectedLabels.remove(label);
      _labelError = null;
    });
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
      if (_selectedQuadrant != current.quadrant) 'quadrant': _selectedQuadrant,
      if (!_sameLabels(_selectedLabels, current.labels))
        'labels': List.unmodifiable(_selectedLabels),
      if (current.status == 'IN_PROGRESS' &&
          _selectedProgress != current.progress)
        'progress': _selectedProgress,
    };
    if (fields.isEmpty) return;
    setState(() => _saving = true);
    try {
      final result = await widget.sync.update(current.id, fields: fields);
      if (result is PendingApproval && mounted) {
        setState(() => _pendingMessage = '等待负责人审批');
      }
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

  Future<void> _deleteComment(TaskComment comment) async {
    if (!widget.canWrite || comment.deletedAt != null) return;
    try {
      final result = await widget.sync.deleteComment(
        _current.id,
        comment.id,
        baseVersion: comment.version,
      );
      if (result is PendingApproval && mounted) {
        setState(() => _pendingMessage = '评论删除等待作者审批');
      }
    } catch (_) {
      // Keep the error in the sync banner.
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
    final task = _current;
    final members = widget.sync.state.snapshot?.members ?? const [];
    final activeHandlerIds = _activeHandlerIds(members);
    final selectedResumeHandlerId =
        _selectedResumeHandlerId ??
        task.resumeHandlerId ??
        task.currentHandlerId;
    final isBlockedRecovery =
        normalizeTaskStatus(task.status) == 'BLOCKED' &&
        status == 'IN_PROGRESS';
    if ((status == 'BLOCKED' || isBlockedRecovery) &&
        !activeHandlerIds.contains(selectedResumeHandlerId)) {
      setState(() => _handlerError = '恢复负责人已不可用，请选择有效成员');
      return;
    }
    setState(() => _handlerError = null);
    String? blockedReason;
    if (status == 'BLOCKED') {
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
      final result = await widget.sync.transition(
        task.id,
        status,
        blockedReason: blockedReason,
        resumeHandlerId: status == 'BLOCKED'
            ? selectedResumeHandlerId
            : isBlockedRecovery &&
                  selectedResumeHandlerId != task.resumeHandlerId
            ? selectedResumeHandlerId
            : null,
      );
      if (result is PendingApproval && mounted) {
        setState(() => _pendingMessage = '等待负责人审批');
      }
    } catch (_) {
      // Keep the error in the sync banner.
    }
  }

  Future<void> _changeHandler(String? handlerId) async {
    if (!widget.canWrite) return;
    if (handlerId == null || handlerId == _current.currentHandlerId) return;
    final members = widget.sync.state.snapshot?.members ?? const [];
    if (!_activeHandlerIds(members).contains(handlerId)) {
      setState(() => _handlerError = '负责人已不可用，请选择有效成员');
      return;
    }
    setState(() => _handlerError = null);
    try {
      final result = await widget.sync.update(
        _current.id,
        fields: {'current_handler_id': handlerId},
      );
      if (result is PendingApproval && mounted) {
        setState(() => _pendingMessage = '等待负责人审批');
      }
    } catch (_) {
      // Keep the error in the sync banner.
    }
  }

  void _changeResumeHandler(String? handlerId) {
    if (!widget.canWrite || handlerId == null) return;
    final members = widget.sync.state.snapshot?.members ?? const [];
    if (!_activeHandlerIds(members).contains(handlerId)) {
      setState(() => _handlerError = '恢复负责人已不可用，请选择有效成员');
      return;
    }
    setState(() {
      _selectedResumeHandlerId = handlerId;
      _handlerError = null;
    });
  }

  static String _dateText(DateTime? value) =>
      value?.toUtc().toIso8601String() ?? '';

  static String? _dateValue(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc().toIso8601String();
  }

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
      final viewerId = widget.sync.state.snapshot?.viewerUserId;
      final isOwner = viewerId == task.currentHandlerId;
      final pendingApproval = widget.sync.state.approvalRequests.any(
        (request) => request.taskId == task.id && request.status == 'PENDING',
      );
      final quadrant = _selectedQuadrant;
      final progress = _selectedProgress;
      final comments =
          widget.sync.state.comments
              .where((comment) => comment.taskId == task.id)
              .toList()
            ..sort(
              (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
            );
      final activeHandlerIds = _activeHandlerIds(members);
      final handlerLabels = _handlerLabels(members);
      final handlerIds = _handlerOptionIds(
        activeHandlerIds,
        task.currentHandlerId,
      );
      final selectedResumeHandlerId =
          _selectedResumeHandlerId ??
          task.resumeHandlerId ??
          task.currentHandlerId;
      final resumeHandlerIds = _handlerOptionIds(
        activeHandlerIds,
        selectedResumeHandlerId,
      );
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
          padding: const EdgeInsets.all(MuyuSpacing.lg),
          children: [
            if (widget.sync.state.errorMessage != null)
              Text(
                widget.sync.state.errorMessage!,
                key: const Key('task-error'),
              ),
            if (_handlerError != null)
              Text(_handlerError!, key: const Key('task-handler-error')),
            Text(
              task.taskNumber.isEmpty ? '任务' : '任务编号：${task.taskNumber}',
              key: const Key('task-number'),
            ),
            Text(
              isOwner ? '当前设备是任务负责人' : '协作成员，修改需负责人审批',
              key: const Key('task-permission-hint'),
            ),
            if (task.parentTaskId != null)
              Text('父任务：${task.parentTaskId}', key: const Key('task-parent')),
            if (_pendingMessage != null || pendingApproval)
              Card(
                key: const Key('task-pending-approval'),
                child: Text(_pendingMessage ?? '等待负责人审批'),
              ),
            TextField(
              key: const Key('task-detail-title'),
              controller: _title,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: MuyuSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('task-quadrant-select'),
              initialValue: quadrant,
              decoration: const InputDecoration(labelText: '四象限（必选）'),
              items: _quadrantLabels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: !widget.canWrite || task.deletedAt != null
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedQuadrant = value);
                      }
                    },
            ),
            const SizedBox(height: MuyuSpacing.sm),
            TextField(
              key: const Key('task-detail-label-input'),
              controller: _label,
              enabled:
                  widget.canWrite &&
                  task.deletedAt == null &&
                  _selectedLabels.length < 10,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addLabel(),
              decoration: InputDecoration(
                labelText: '标签（可选）',
                errorText: _labelError,
                suffixIcon: IconButton(
                  key: const Key('task-detail-label-add'),
                  tooltip: '添加标签',
                  onPressed:
                      widget.canWrite &&
                          task.deletedAt == null &&
                          _selectedLabels.length < 10
                      ? _addLabel
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
            if (_selectedLabels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: MuyuSpacing.xs),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: MuyuSpacing.xs,
                    runSpacing: MuyuSpacing.xs,
                    children: [
                      for (final label in _selectedLabels)
                        InputChip(
                          key: Key('task-label-chip-$label'),
                          label: Text(label),
                          deleteIcon: Icon(
                            Icons.close,
                            key: Key('task-label-remove-$label'),
                          ),
                          onDeleted: !widget.canWrite || task.deletedAt != null
                              ? null
                              : () => _removeLabel(label),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: MuyuSpacing.sm),
            TextField(
              key: const Key('task-detail-description'),
              controller: _description,
              maxLines: 3,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            const SizedBox(height: MuyuSpacing.sm),
            TextField(
              key: const Key('task-detail-due-at'),
              controller: _dueAt,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '截止时间（ISO 8601，可选）'),
            ),
            const SizedBox(height: MuyuSpacing.sm),
            TextField(
              key: const Key('task-detail-planned-start-at'),
              controller: _plannedStartAt,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '计划开始（ISO 8601，可选）'),
            ),
            const SizedBox(height: MuyuSpacing.sm),
            TextField(
              key: const Key('task-detail-estimated-minutes'),
              controller: _estimatedMinutes,
              keyboardType: TextInputType.number,
              enabled: widget.canWrite,
              decoration: const InputDecoration(labelText: '预计工时（分钟）'),
            ),
            const SizedBox(height: MuyuSpacing.lg),
            Text('状态：${taskStatusLabel(task.status)}'),
            if (normalizeTaskStatus(task.status) == 'IN_PROGRESS')
              DropdownButtonFormField<int>(
                key: const Key('task-progress-select'),
                initialValue: const [20, 40, 60, 80].contains(progress)
                    ? progress
                    : task.progress ?? 20,
                decoration: const InputDecoration(labelText: '当前进度'),
                items: const [20, 40, 60, 80]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value%'),
                      ),
                    )
                    .toList(),
                onChanged: !widget.canWrite || task.deletedAt != null
                    ? null
                    : (value) => setState(() => _selectedProgress = value),
              ),
            if (handlerIds.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('task-handler-select'),
                initialValue: handlerIds.contains(task.currentHandlerId)
                    ? task.currentHandlerId
                    : task.currentHandlerId,
                decoration: const InputDecoration(labelText: '负责人'),
                items: handlerIds
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        enabled: activeHandlerIds.contains(id),
                        child: Text(handlerLabels[id] ?? id),
                      ),
                    )
                    .toList(),
                onChanged: !widget.canWrite || task.deletedAt != null
                    ? null
                    : _changeHandler,
              ),
            if (normalizeTaskStatus(task.status) == 'BLOCKED')
              DropdownButtonFormField<String>(
                key: const Key('task-resume-handler-select'),
                initialValue: selectedResumeHandlerId,
                decoration: const InputDecoration(labelText: '恢复负责人'),
                items: resumeHandlerIds
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        enabled: activeHandlerIds.contains(id),
                        child: Text(handlerLabels[id] ?? id),
                      ),
                    )
                    .toList(),
                onChanged: !widget.canWrite || task.deletedAt != null
                    ? null
                    : _changeResumeHandler,
              ),
            const SizedBox(height: MuyuSpacing.sm),
            Wrap(
              spacing: MuyuSpacing.sm,
              runSpacing: MuyuSpacing.sm,
              children: [
                for (final status in taskStatuses)
                  OutlinedButton(
                    key: Key('task-status-${status.toLowerCase()}'),
                    onPressed: !widget.canWrite || task.deletedAt != null
                        ? null
                        : () => _transition(status),
                    child: Text(taskStatusLabel(status)),
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
            const SizedBox(height: MuyuSpacing.xl),
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
            if (comments.isNotEmpty) ...[
              const SizedBox(height: MuyuSpacing.md),
              const Text('评论记录'),
              for (final comment in comments)
                Card(
                  key: Key('task-comment-${comment.id}'),
                  child: ListTile(
                    title: Text(
                      comment.deletedAt == null ? comment.body : '评论已删除',
                    ),
                    subtitle: Text(
                      comment.deletedAt == null
                          ? '作者：${comment.authorUserId}'
                          : '已删除 · 作者：${comment.authorUserId}',
                    ),
                    trailing: comment.deletedAt != null
                        ? null
                        : IconButton(
                            key: Key('task-comment-delete-${comment.id}'),
                            tooltip: '删除评论',
                            onPressed: !widget.canWrite
                                ? null
                                : () => _deleteComment(comment),
                            icon: const Icon(Icons.delete_outline),
                          ),
                  ),
                ),
            ],
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: MuyuSpacing.xl),
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
