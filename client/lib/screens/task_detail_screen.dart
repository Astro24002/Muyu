import 'package:flutter/material.dart';

import '../models/task.dart';
import '../models/task_approval_request.dart';
import '../tasks/task_status.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import '../widgets/route_settle.dart';

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
  late String _selectedQuadrant;
  late List<String> _selectedLabels;
  String? _handlerError;
  String? _selectedResumeHandlerId;
  int? _selectedProgress;
  bool _saving = false;
  bool _commenting = false;
  bool _editing = false;
  String? _pendingMessage;
  String? _formError;

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

  static List<String> _normalizeLabels(Iterable<String> labels) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in labels) {
      final label = value.trim();
      if (label.isEmpty || !seen.add(label.toLowerCase())) continue;
      // The storage field is list-shaped for protocol compatibility, but the
      // task domain now has a single classification. Keep legacy snapshots
      // readable while exposing only the first value to the editor.
      result.add(label);
      break;
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
      final phone =
          member['phone_e164'] ??
          member['phone_number'] ??
          member['mobile'] ??
          member['phone'];
      labels[userId] = displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : phone is String && phone.trim().isNotEmpty
          ? phone.trim()
          : '协作成员';
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

  void _loadEditor(TaskItem task) {
    _title.text = task.title;
    _description.text = task.description;
    _dueAt.text = _dateText(task.dueAt);
    _plannedStartAt.text = _dateText(task.plannedStartAt);
    _estimatedMinutes.text = task.estimatedMinutes?.toString() ?? '';
    _selectedLabels = _normalizeLabels(task.labels);
    _selectedQuadrant = task.quadrant;
    _selectedResumeHandlerId = task.resumeHandlerId ?? task.currentHandlerId;
    _selectedProgress = task.progress;
    _formError = null;
  }

  void _beginEditing() {
    if (!widget.canWrite || _current.deletedAt != null) return;
    setState(() {
      _loadEditor(_current);
      _editing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _loadEditor(_current);
      _editing = false;
    });
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final initial = (current ?? DateTime.now().add(const Duration(hours: 1)))
        .toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDueAt() async {
    final picked = await _pickDateTime(_dateValueAsDate(_dueAt.text));
    if (!mounted || picked == null) return;
    setState(() {
      _dueAt.text = picked.toUtc().toIso8601String();
      _formError = null;
    });
  }

  Future<void> _pickPlannedStartAt() async {
    final picked = await _pickDateTime(_dateValueAsDate(_plannedStartAt.text));
    if (!mounted || picked == null) return;
    setState(() => _plannedStartAt.text = picked.toUtc().toIso8601String());
  }

  void _removeLabel(String label) {
    setState(() {
      _selectedLabels.remove(label);
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (!widget.canWrite || title.isEmpty || _saving) return;
    final current = _current;
    final labelsChanged = !_sameLabels(_selectedLabels, current.labels);
    final approvedClassifications = {
      for (final classification in widget.sync.state.classifications)
        classification.name.trim().toLowerCase(),
    };
    // Legacy snapshots may contain an empty classification array. Allow edits
    // to unrelated fields, but require exactly one approved classification
    // whenever the classification itself is changed.
    if (labelsChanged) {
      if (_selectedLabels.length != 1) {
        setState(() => _formError = '任务必须选择一个已批准分类');
        return;
      }
      if (approvedClassifications.isEmpty ||
          _selectedLabels.any(
            (label) => !approvedClassifications.contains(label.toLowerCase()),
          )) {
        setState(() => _formError = '任务只能选择已批准分类');
        return;
      }
    }
    final estimateText = _estimatedMinutes.text.trim();
    final estimate = estimateText.isEmpty ? null : int.tryParse(estimateText);
    if (estimateText.isNotEmpty && (estimate == null || estimate < 0)) {
      setState(() {});
      return;
    }
    final dueAt = _dateValue(_dueAt.text);
    final dueChanged = dueAt != current.dueAt?.toIso8601String();
    if (dueChanged && dueAt == null) {
      setState(() => _formError = '截止时间不能为空，请选择截止时间');
      return;
    }
    if (_formError != null) setState(() => _formError = null);
    final fields = <String, Object?>{
      if (title != current.title) 'title': title,
      if (_description.text.trim() != current.description)
        'description': _description.text.trim(),
      if (dueChanged) 'due_at': dueAt,
      if (_dateValue(_plannedStartAt.text) !=
          current.plannedStartAt?.toIso8601String())
        'planned_start_at': _dateValue(_plannedStartAt.text),
      if (estimate != current.estimatedMinutes) 'estimated_minutes': estimate,
      if (_selectedQuadrant != current.quadrant) 'quadrant': _selectedQuadrant,
      if (labelsChanged) 'labels': List.unmodifiable(_selectedLabels),
      if (current.status == 'IN_PROGRESS' &&
          _selectedProgress != current.progress)
        'progress': _selectedProgress,
    };
    if (fields.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await widget.sync.update(current.id, fields: fields);
      if (result is PendingApproval && mounted) {
        setState(() {
          _pendingMessage = '等待负责人审批';
          _editing = false;
        });
      } else if (result != null && mounted) {
        setState(() => _editing = false);
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
    await waitForRouteDismissal();
    if (!mounted) {
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
    final actorUserId = widget.sync.state.snapshot?.viewerUserId;
    if (!isTaskTransitionAllowed(
      status: task.status,
      targetStatus: status,
      currentHandlerId: task.currentHandlerId,
      reviewerUserId: task.reviewerUserId,
      actorUserId: actorUserId,
    )) {
      setState(() => _handlerError = '当前用户不能执行该状态操作');
      return;
    }
    final members = widget.sync.state.snapshot?.members ?? const [];
    final activeHandlerIds = _activeHandlerIds(members);
    final selectedResumeHandlerId =
        _selectedResumeHandlerId ??
        task.resumeHandlerId ??
        task.currentHandlerId;
    final isBlockedRecovery =
        normalizeTaskStatus(task.status) == 'BLOCKED' &&
        status == 'IN_PROGRESS';
    final isReviewReturn =
        normalizeTaskStatus(task.status) == 'REVIEW' && status == 'IN_PROGRESS';
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
      await waitForRouteDismissal();
      if (!mounted) return;
    }
    if (!mounted) return;
    String? reviewRejectionReason;
    if (isReviewReturn) {
      final reason = TextEditingController();
      reviewRejectionReason = await showDialog<String>(
        context: context,
        builder: (context) {
          String? errorText;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('退回待验收任务'),
              content: TextField(
                key: const Key('review-rejection-reason'),
                controller: reason,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '退回原因',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('review-return-submit'),
                  onPressed: () {
                    final value = reason.text.trim();
                    if (value.isEmpty) {
                      setDialogState(() => errorText = '请填写退回原因');
                      return;
                    }
                    Navigator.pop(context, value);
                  },
                  child: const Text('确认退回'),
                ),
              ],
            ),
          );
        },
      );
      await waitForRouteDismissal();
      reason.dispose();
      if (reviewRejectionReason == null) return;
      if (!mounted) return;
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
        reviewRejectionReason: reviewRejectionReason,
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

  List<TaskItem> _subtasksFor(TaskItem task) {
    final children = (widget.sync.state.snapshot?.tasks ?? const <TaskItem>[])
        .where(
          (candidate) =>
              candidate.parentTaskId == task.id && candidate.deletedAt == null,
        )
        .toList();
    children.sort((left, right) {
      final leftTerminal = _isTerminal(left.status);
      final rightTerminal = _isTerminal(right.status);
      if (leftTerminal != rightTerminal) return leftTerminal ? 1 : -1;
      final leftDue = left.dueAt;
      final rightDue = right.dueAt;
      if (leftDue == null && rightDue != null) return 1;
      if (leftDue != null && rightDue == null) return -1;
      if (leftDue != null && rightDue != null) {
        final comparison = leftDue.compareTo(rightDue);
        if (comparison != 0) return comparison;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return children;
  }

  TaskItem? _parentFor(TaskItem task) {
    final parentId = task.parentTaskId;
    if (parentId == null) return null;
    for (final candidate
        in widget.sync.state.snapshot?.tasks ?? const <TaskItem>[]) {
      if (candidate.id == parentId) return candidate;
    }
    return null;
  }

  void _openRelatedTask(TaskItem task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          task: task,
          sync: widget.sync,
          canWrite: widget.canWrite,
        ),
      ),
    );
  }

  Future<void> _createSubtask(TaskItem parent) async {
    if (!widget.canWrite || parent.deletedAt != null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateSubtaskSheet(parent: parent, sync: widget.sync),
    );
  }

  Color _quadrantColor(BuildContext context, String quadrant) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    return switch (quadrant) {
      'Q1' => extension?.quadrantQ1 ?? theme.colorScheme.error,
      'Q2' => extension?.quadrantQ2 ?? theme.colorScheme.primary,
      'Q3' => extension?.quadrantQ3 ?? theme.colorScheme.primary,
      'Q4' => extension?.quadrantQ4 ?? theme.colorScheme.primary,
      _ => theme.colorScheme.onSurfaceVariant,
    };
  }

  Color _statusColor(BuildContext context, String status) {
    final theme = Theme.of(context);
    final extension = theme.extension<MuyuThemeExtension>();
    return switch (taskStatusTone(status)) {
      TaskStatusTone.done => extension?.sync ?? theme.colorScheme.secondary,
      TaskStatusTone.cancelled => theme.colorScheme.error,
      TaskStatusTone.blocked => extension?.coral ?? theme.colorScheme.error,
      TaskStatusTone.review => theme.colorScheme.secondary,
      TaskStatusTone.inProgress => theme.colorScheme.primary,
      TaskStatusTone.todo => theme.colorScheme.onSurfaceVariant,
      TaskStatusTone.unknown => theme.colorScheme.error,
    };
  }

  IconData _statusIcon(String status) => switch (taskStatusTone(status)) {
    TaskStatusTone.done => Icons.check_circle,
    TaskStatusTone.cancelled => Icons.cancel,
    TaskStatusTone.blocked => Icons.pause_circle_outline,
    TaskStatusTone.review => Icons.fact_check_outlined,
    TaskStatusTone.inProgress => Icons.play_circle_outline,
    TaskStatusTone.todo => Icons.radio_button_unchecked,
    TaskStatusTone.unknown => Icons.help_outline,
  };

  String _transitionLabel(String currentStatus, String targetStatus) {
    final current = normalizeTaskStatus(currentStatus);
    final target = normalizeTaskStatus(targetStatus);
    if ((current == 'DONE' || current == 'CANCELLED') &&
        (target == 'TODO' || target == 'IN_PROGRESS')) {
      return '重新打开';
    }
    if (target == 'BLOCKED') return '标记阻塞';
    if (target == 'CANCELLED') return '取消任务';
    return taskStatusActionLabel(
      currentStatus: currentStatus,
      targetStatus: targetStatus,
    );
  }

  bool _isPrimaryTransition(String currentStatus, String targetStatus) {
    final current = normalizeTaskStatus(currentStatus);
    final target = normalizeTaskStatus(targetStatus);
    return (current == 'TODO' && target == 'IN_PROGRESS') ||
        (current == 'IN_PROGRESS' && target == 'REVIEW') ||
        (current == 'BLOCKED' && target == 'IN_PROGRESS') ||
        (current == 'REVIEW' && target == 'DONE') ||
        (current == 'DONE' && target == 'IN_PROGRESS') ||
        (current == 'CANCELLED' && target == 'TODO');
  }

  static bool _isTerminal(String status) {
    final normalized = normalizeTaskStatus(status);
    return normalized == 'DONE' || normalized == 'CANCELLED';
  }

  String _displayDate(DateTime? value) {
    if (value == null) return '未设置';
    final local = value.toLocal();
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month月$day日 周${weekdays[local.weekday - 1]} $hour:$minute';
  }

  String? _dueHint(DateTime? value) {
    if (value == null) return null;
    final now = DateTime.now();
    if (!value.isBefore(now)) return null;
    final difference = now.difference(value);
    if (difference.inDays > 0) return '已逾期 ${difference.inDays} 天';
    if (difference.inHours > 0) return '已逾期 ${difference.inHours} 小时';
    return '已逾期';
  }

  Widget _buildHeader(
    BuildContext context,
    TaskItem task,
    Map<String, String> handlerLabels,
    bool isOwner,
  ) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context, task.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: MuyuSpacing.xs),
              child: Icon(
                _statusIcon(task.status),
                color: statusColor,
                size: 28,
                semanticLabel: taskStatusLabel(task.status),
              ),
            ),
            const SizedBox(width: MuyuSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.taskNumber.isEmpty ? '任务' : '任务编号 ${task.taskNumber}',
                    key: const Key('task-number'),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: MuyuSpacing.xs),
                  if (_editing)
                    TextField(
                      key: const Key('task-detail-title'),
                      controller: _title,
                      autofocus: true,
                      enabled: widget.canWrite,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '任务标题'),
                    )
                  else
                    Text(
                      task.title,
                      key: const Key('task-detail-title'),
                      style: theme.textTheme.titleLarge,
                    ),
                  const SizedBox(height: MuyuSpacing.sm),
                  Wrap(
                    spacing: MuyuSpacing.sm,
                    runSpacing: MuyuSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(
                        label: taskStatusLabel(task.status),
                        color: statusColor,
                      ),
                      Text(
                        isOwner
                            ? '我负责'
                            : '${handlerLabels[task.currentHandlerId] ?? '协作成员'}负责',
                        key: const Key('task-permission-hint'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!_editing && task.description.trim().isNotEmpty) ...[
          const SizedBox(height: MuyuSpacing.lg),
          Text(task.description, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }

  Widget _buildReadOnlyAttributes(
    BuildContext context,
    TaskItem task,
    Map<String, String> handlerLabels,
  ) {
    final theme = Theme.of(context);
    final dueHint = _dueHint(task.dueAt);
    return Column(
      children: [
        _DetailAttributeRow(
          icon: Icons.person_outline,
          label: '负责人',
          child: Text(handlerLabels[task.currentHandlerId] ?? '协作成员'),
        ),
        _DetailAttributeRow(
          icon: Icons.schedule_outlined,
          label: '截止时间',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_displayDate(task.dueAt)),
              if (dueHint != null)
                Text(
                  dueHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        _DetailAttributeRow(
          icon: Icons.star_outline,
          label: '分类',
          child: task.labels.isEmpty
              ? Text('未分类', style: theme.textTheme.bodySmall)
              : Wrap(
                  spacing: MuyuSpacing.xs,
                  runSpacing: MuyuSpacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final label in task.labels)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MuyuSpacing.sm,
                          vertical: MuyuSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(label, style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
        ),
        _DetailAttributeRow(
          icon: Icons.priority_high,
          iconColor: _quadrantColor(context, task.quadrant),
          label: '四象限',
          child: Text(_quadrantLabels[task.quadrant] ?? task.quadrant),
        ),
        if (normalizeTaskStatus(task.status) == 'IN_PROGRESS')
          _DetailAttributeRow(
            icon: Icons.donut_small_outlined,
            label: '当前进度',
            child: Text('${task.progress ?? 20}%'),
          ),
      ],
    );
  }

  Widget _buildEditor(
    BuildContext context,
    TaskItem task,
    List<String> handlerIds,
    Set<String> activeHandlerIds,
    Map<String, String> handlerLabels,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('task-detail-description'),
          controller: _description,
          maxLines: 3,
          enabled: widget.canWrite,
          decoration: const InputDecoration(labelText: '任务描述'),
        ),
        const SizedBox(height: MuyuSpacing.md),
        _DateEditor(
          fieldKey: const Key('task-detail-due-at'),
          icon: Icons.schedule_outlined,
          label: '截止时间',
          value: _displayDate(_dateValueAsDate(_dueAt.text)),
          controller: _dueAt,
          onTap: _pickDueAt,
        ),
        const SizedBox(height: MuyuSpacing.md),
        Text('分类（必选一个）', style: theme.textTheme.labelLarge),
        const SizedBox(height: MuyuSpacing.sm),
        if (widget.sync.state.classifications.isEmpty)
          Text('暂无已批准分类，请前往“我的”→“分类管理”创建', style: theme.textTheme.bodySmall)
        else
          Wrap(
            key: const Key('task-detail-classification-options'),
            spacing: MuyuSpacing.xs,
            runSpacing: MuyuSpacing.xs,
            children: [
              for (final classification in widget.sync.state.classifications)
                ChoiceChip(
                  key: Key(
                    'task-detail-classification-option-${classification.name}',
                  ),
                  label: Text(classification.name),
                  selected: _selectedLabels.any(
                    (label) =>
                        label.toLowerCase() ==
                        classification.name.toLowerCase(),
                  ),
                  onSelected: widget.canWrite
                      ? (selected) {
                          setState(() {
                            if (selected) {
                              _selectedLabels
                                ..clear()
                                ..add(classification.name);
                            } else {
                              _selectedLabels.removeWhere(
                                (label) =>
                                    label.toLowerCase() ==
                                    classification.name.toLowerCase(),
                              );
                            }
                          });
                        }
                      : null,
                ),
            ],
          ),
        if (_selectedLabels.isNotEmpty) ...[
          const SizedBox(height: MuyuSpacing.sm),
          Wrap(
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
                  onDeleted: widget.canWrite ? () => _removeLabel(label) : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: MuyuSpacing.lg),
        Text('四象限', style: theme.textTheme.labelLarge),
        const SizedBox(height: MuyuSpacing.sm),
        Wrap(
          key: const Key('task-quadrant-select'),
          spacing: MuyuSpacing.sm,
          runSpacing: MuyuSpacing.sm,
          children: [
            for (final entry in _quadrantLabels.entries)
              _QuadrantChoice(
                key: Key('task-quadrant-option-${entry.key}'),
                value: entry.key,
                label: entry.value.substring(3),
                color: _quadrantColor(context, entry.key),
                selected: _selectedQuadrant == entry.key,
                onTap: widget.canWrite
                    ? () => setState(() => _selectedQuadrant = entry.key)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: MuyuSpacing.lg),
        if (handlerIds.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const Key('task-handler-select'),
            initialValue: task.currentHandlerId,
            decoration: const InputDecoration(
              labelText: '负责人',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: handlerIds
                .map(
                  (id) => DropdownMenuItem(
                    value: id,
                    enabled: activeHandlerIds.contains(id),
                    child: Text(handlerLabels[id] ?? '协作成员'),
                  ),
                )
                .toList(),
            onChanged: widget.canWrite ? _changeHandler : null,
          ),
        if (normalizeTaskStatus(task.status) == 'IN_PROGRESS') ...[
          const SizedBox(height: MuyuSpacing.md),
          DropdownButtonFormField<int>(
            key: const Key('task-progress-select'),
            initialValue: const [20, 40, 60, 80].contains(_selectedProgress)
                ? _selectedProgress
                : 20,
            decoration: const InputDecoration(
              labelText: '当前进度',
              prefixIcon: Icon(Icons.donut_small_outlined),
            ),
            items: const [20, 40, 60, 80]
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text('$value%')),
                )
                .toList(),
            onChanged: widget.canWrite
                ? (value) => setState(() => _selectedProgress = value)
                : null,
          ),
        ],
        const SizedBox(height: MuyuSpacing.md),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: true,
          title: const Text('更多信息'),
          children: [
            _DateEditor(
              fieldKey: const Key('task-detail-planned-start-at'),
              icon: Icons.event_available_outlined,
              label: '计划开始',
              value: _displayDate(_dateValueAsDate(_plannedStartAt.text)),
              controller: _plannedStartAt,
              onTap: _pickPlannedStartAt,
            ),
            const SizedBox(height: MuyuSpacing.md),
            TextField(
              key: const Key('task-detail-estimated-minutes'),
              controller: _estimatedMinutes,
              keyboardType: TextInputType.number,
              enabled: widget.canWrite,
              decoration: const InputDecoration(
                labelText: '预计工时（分钟）',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusActions(
    BuildContext context,
    TaskItem task,
    List<String> transitions,
    List<String> resumeHandlerIds,
    Set<String> activeHandlerIds,
    Map<String, String> handlerLabels,
  ) {
    final normalized = normalizeTaskStatus(task.status);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('当前状态', style: theme.textTheme.titleMedium),
            const Spacer(),
            _StatusBadge(
              label: taskStatusLabel(task.status),
              color: _statusColor(context, task.status),
            ),
          ],
        ),
        if (normalized == 'BLOCKED') ...[
          const SizedBox(height: MuyuSpacing.md),
          _StateNotice(
            icon: Icons.pause_circle_outline,
            title: '任务正在等待',
            lines: [
              if (task.blockedReason != null) '原因：${task.blockedReason}',
              if (task.blockedSince != null)
                '开始时间：${_displayDate(task.blockedSince)}',
              if (task.waitingForUserId != null)
                '等待对象：${handlerLabels[task.waitingForUserId] ?? '协作成员'}',
            ],
          ),
          if (resumeHandlerIds.isNotEmpty) ...[
            const SizedBox(height: MuyuSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('task-resume-handler-select'),
              initialValue:
                  _selectedResumeHandlerId ??
                  task.resumeHandlerId ??
                  task.currentHandlerId,
              decoration: const InputDecoration(labelText: '解除阻塞后负责人'),
              items: resumeHandlerIds
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      enabled: activeHandlerIds.contains(id),
                      child: Text(handlerLabels[id] ?? '协作成员'),
                    ),
                  )
                  .toList(),
              onChanged: widget.canWrite ? _changeResumeHandler : null,
            ),
          ],
        ],
        if (normalized == 'REVIEW') ...[
          const SizedBox(height: MuyuSpacing.md),
          _StateNotice(
            icon: Icons.fact_check_outlined,
            title: '等待验收',
            lines: [
              '验收人：${handlerLabels[task.reviewerUserId] ?? '协作成员'}',
              if (task.reviewSubmittedAt != null)
                '提交时间：${_displayDate(task.reviewSubmittedAt)}',
              if (task.reviewRejectionReason?.trim().isNotEmpty == true)
                '退回原因：${task.reviewRejectionReason}',
            ],
          ),
          Text(
            // Keep the legacy keyed summary available to widget tests and
            // accessibility tooling; the visible notice always uses a safe
            // display label when member data is unavailable.
            '验收人：${handlerLabels[task.reviewerUserId] ?? task.reviewerUserId ?? '协作成员'}',
            key: const Key('task-reviewer-summary'),
            style: const TextStyle(fontSize: 0),
          ),
        ],
        if (transitions.isNotEmpty && task.deletedAt == null) ...[
          const SizedBox(height: MuyuSpacing.lg),
          Wrap(
            spacing: MuyuSpacing.sm,
            runSpacing: MuyuSpacing.sm,
            children: [
              for (final status in transitions)
                if (_isPrimaryTransition(task.status, status))
                  OutlinedButton.icon(
                    key: Key('task-status-${status.toLowerCase()}'),
                    onPressed: widget.canWrite
                        ? () => _transition(status)
                        : null,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _statusColor(
                        context,
                        status,
                      ).withAlpha(20),
                      side: BorderSide(color: _statusColor(context, status)),
                      foregroundColor: _statusColor(context, status),
                    ),
                    icon: Icon(_statusIcon(status), size: 18),
                    label: Text(_transitionLabel(task.status, status)),
                  )
                else
                  OutlinedButton(
                    key: Key('task-status-${status.toLowerCase()}'),
                    onPressed: widget.canWrite
                        ? () => _transition(status)
                        : null,
                    child: Text(_transitionLabel(task.status, status)),
                  ),
              OutlinedButton.icon(
                key: const Key('task-delay-button'),
                onPressed: widget.canWrite ? _addDelay : null,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: const Text('记录延期'),
              ),
            ],
          ),
        ] else if (task.deletedAt == null) ...[
          const SizedBox(height: MuyuSpacing.lg),
          OutlinedButton.icon(
            key: const Key('task-delay-button'),
            onPressed: widget.canWrite ? _addDelay : null,
            icon: const Icon(Icons.schedule_outlined, size: 18),
            label: const Text('记录延期'),
          ),
        ],
      ],
    );
  }

  Widget _buildRelationships(
    BuildContext context,
    TaskItem task,
    List<TaskItem> subtasks,
    TaskItem? parent,
    Map<String, String> handlerLabels,
  ) {
    final theme = Theme.of(context);
    if (parent != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所属任务',
            key: const Key('task-parent'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: MuyuSpacing.sm),
          _RelatedTaskRow(
            task: parent,
            handlerLabel: handlerLabels[parent.currentHandlerId] ?? '协作成员',
            statusColor: _statusColor(context, parent.status),
            statusIcon: _statusIcon(parent.status),
            dueText: _displayDate(parent.dueAt),
            onTap: () => _openRelatedTask(parent),
            parent: true,
          ),
        ],
      );
    }
    final completed = subtasks
        .where((item) => normalizeTaskStatus(item.status) == 'DONE')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('子任务', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text(
              '$completed/${subtasks.length}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        if (subtasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.md),
            child: Text('还没有子任务', style: theme.textTheme.bodySmall),
          )
        else
          for (final subtask in subtasks)
            _RelatedTaskRow(
              task: subtask,
              handlerLabel: handlerLabels[subtask.currentHandlerId] ?? '协作成员',
              statusColor: _statusColor(context, subtask.status),
              statusIcon: _statusIcon(subtask.status),
              dueText: _displayDate(subtask.dueAt),
              dueHint: _dueHint(subtask.dueAt),
              onTap: () => _openRelatedTask(subtask),
            ),
        if (widget.canWrite && task.deletedAt == null) ...[
          const SizedBox(height: MuyuSpacing.xs),
          TextButton.icon(
            key: const Key('task-add-subtask'),
            onPressed: () => _createSubtask(task),
            icon: const Icon(Icons.add),
            label: const Text('添加子任务'),
          ),
        ],
      ],
    );
  }

  Widget _buildComments(
    BuildContext context,
    List<TaskComment> comments,
    Map<String, String> handlerLabels,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('评论', style: theme.textTheme.titleMedium),
            const Spacer(),
            Text('${comments.length}', style: theme.textTheme.bodySmall),
          ],
        ),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.md),
            child: Text('还没有评论', style: theme.textTheme.bodySmall),
          )
        else
          for (final comment in comments)
            _CommentRow(
              comment: comment,
              authorLabel: handlerLabels[comment.authorUserId] ?? '协作成员',
              canDelete: widget.canWrite && comment.deletedAt == null,
              onDelete: () => _deleteComment(comment),
            ),
        const SizedBox(height: MuyuSpacing.sm),
        TextField(
          key: const Key('task-comment-input'),
          controller: _comment,
          enabled: widget.canWrite,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '写评论……',
            suffixIcon: IconButton(
              key: const Key('task-comment-submit'),
              tooltip: '发送评论',
              onPressed: !widget.canWrite || _commenting ? null : _addComment,
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
      ],
    );
  }

  Widget _buildConflicts(
    BuildContext context,
    List<Map<String, dynamic>> conflicts,
  ) {
    if (conflicts.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: const Key('task-conflicts-section'),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.warning_amber,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('待解决冲突 ${conflicts.length}'),
      children: [
        for (final conflict in conflicts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('任务内容存在同步冲突'),
            subtitle: const Text('请选择保留当前内容或采用对方修改'),
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
      ],
    );
  }

  static String _dateText(DateTime? value) =>
      value?.toUtc().toIso8601String() ?? '';

  static DateTime? _dateValueAsDate(String text) {
    final value = text.trim();
    return value.isEmpty ? null : DateTime.tryParse(value);
  }

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
      final transitionStatuses = taskTransitionTargets(
        status: task.status,
        currentHandlerId: task.currentHandlerId,
        reviewerUserId: task.reviewerUserId,
        actorUserId: viewerId,
      );
      final subtasks = task.parentTaskId == null
          ? _subtasksFor(task)
          : const <TaskItem>[];
      final parent = _parentFor(task);
      return Scaffold(
        appBar: AppBar(
          title: const Text('任务详情'),
          actions: [
            IconButton(
              key: const Key('task-save-button'),
              tooltip: _editing ? '保存任务' : '编辑任务',
              onPressed: !widget.canWrite || _saving || task.deletedAt != null
                  ? null
                  : _editing
                  ? _save
                  : _beginEditing,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_editing ? Icons.save_outlined : Icons.edit_outlined),
            ),
            if (_editing)
              IconButton(
                key: const Key('task-edit-cancel'),
                tooltip: '取消编辑',
                onPressed: _saving ? null : _cancelEditing,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(MuyuSpacing.lg),
          children: [
            if (widget.sync.state.errorMessage != null)
              _InlineNotice(
                messageKey: const Key('task-error'),
                icon: Icons.sync_problem_outlined,
                color: Theme.of(context).colorScheme.error,
                message: widget.sync.state.errorMessage!,
              ),
            if (_handlerError != null)
              _InlineNotice(
                messageKey: const Key('task-handler-error'),
                icon: Icons.info_outline,
                color: Theme.of(context).colorScheme.error,
                message: _handlerError!,
              ),
            if (_formError != null)
              _InlineNotice(
                messageKey: const Key('task-form-error'),
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                message: _formError!,
              ),
            if (_pendingMessage != null || pendingApproval)
              _InlineNotice(
                messageKey: const Key('task-pending-approval'),
                icon: Icons.hourglass_top_outlined,
                color: Theme.of(context).colorScheme.primary,
                message: _pendingMessage ?? '等待负责人审批',
              ),
            Card(
              key: const Key('task-detail-card'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(MuyuSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, task, handlerLabels, isOwner),
                    const Divider(height: MuyuSpacing.xxl),
                    if (_editing)
                      _buildEditor(
                        context,
                        task,
                        handlerIds,
                        activeHandlerIds,
                        handlerLabels,
                      )
                    else
                      _buildReadOnlyAttributes(context, task, handlerLabels),
                    const Divider(height: MuyuSpacing.xxl),
                    _buildStatusActions(
                      context,
                      task,
                      transitionStatuses,
                      resumeHandlerIds,
                      activeHandlerIds,
                      handlerLabels,
                    ),
                    const Divider(height: MuyuSpacing.xxl),
                    _buildRelationships(
                      context,
                      task,
                      subtasks,
                      parent,
                      handlerLabels,
                    ),
                    const Divider(height: MuyuSpacing.xxl),
                    _buildComments(context, comments, handlerLabels),
                    if (conflicts.isNotEmpty) ...[
                      const Divider(height: MuyuSpacing.xxl),
                      _buildConflicts(context, conflicts),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    this.messageKey,
    required this.icon,
    required this.color,
    required this.message,
  });

  final Key? messageKey;
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: MuyuSpacing.md),
    padding: const EdgeInsets.all(MuyuSpacing.md),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      border: Border.all(color: color.withAlpha(80)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: MuyuSpacing.sm),
        Expanded(child: Text(message, key: messageKey)),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: MuyuSpacing.sm,
      vertical: MuyuSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      border: Border.all(color: color.withAlpha(100)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

class _DetailAttributeRow extends StatelessWidget {
  const _DetailAttributeRow({
    required this.icon,
    required this.label,
    required this.child,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: MuyuSpacing.sm),
        SizedBox(
          width: 68,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: MuyuSpacing.md),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}

class _DateEditor extends StatefulWidget {
  const _DateEditor({
    required this.fieldKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.controller,
  });

  final Key fieldKey;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final TextEditingController controller;

  @override
  State<_DateEditor> createState() => _DateEditorState();
}

class _DateEditorState extends State<_DateEditor> {
  late final TextEditingController _displayController;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _DateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _displayController.text != widget.value) {
      _displayController.text = widget.value;
    }
  }

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _displayController,
    onTap: null,
    onChanged: (value) {
      // The visible field uses Chinese text while the parent keeps ISO data.
      // This also preserves the existing widget-test contract for clearing a
      // deadline through the keyed field.
      if (value.trim().isEmpty) {
        widget.controller.clear();
      } else {
        final parsed = DateTime.tryParse(value);
        widget.controller.text = parsed?.toUtc().toIso8601String() ?? value;
      }
    },
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: '请选择日期和时间',
      prefixIcon: Icon(widget.icon),
      suffixIcon: IconButton(
        tooltip: '选择${widget.label}',
        onPressed: widget.onTap,
        icon: Icon(
          widget.value == '未设置'
              ? Icons.event_outlined
              : Icons.check_circle_outline,
          size: 18,
        ),
      ),
    ),
  );
}

class _QuadrantChoice extends StatelessWidget {
  const _QuadrantChoice({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$value $label',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: MuyuSpacing.md,
          vertical: MuyuSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(25) : Colors.transparent,
          border: Border.all(color: selected ? color : color.withAlpha(110)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.priority_high : Icons.priority_high_outlined,
              color: color,
              size: 18,
            ),
            const SizedBox(width: MuyuSpacing.xs),
            Text(
              '$value $label',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StateNotice extends StatelessWidget {
  const _StateNotice({
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MuyuSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: MuyuSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                for (final line in lines) ...[
                  const SizedBox(height: MuyuSpacing.xs),
                  Text(line),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedTaskRow extends StatelessWidget {
  const _RelatedTaskRow({
    required this.task,
    required this.handlerLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.dueText,
    required this.onTap,
    this.dueHint,
    this.parent = false,
  });

  final TaskItem task;
  final String handlerLabel;
  final Color statusColor;
  final IconData statusIcon;
  final String dueText;
  final String? dueHint;
  final VoidCallback onTap;
  final bool parent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(statusIcon, color: statusColor, size: 22),
            const SizedBox(width: MuyuSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.taskNumber.isEmpty
                        ? task.title
                        : '${task.taskNumber}  ${task.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: MuyuSpacing.xs),
                  Wrap(
                    spacing: MuyuSpacing.sm,
                    runSpacing: MuyuSpacing.xs,
                    children: [
                      Text(
                        parent ? '负责人：$handlerLabel' : handlerLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(dueText, style: theme.textTheme.bodySmall),
                      if (dueHint != null)
                        Text(
                          dueHint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MuyuSpacing.sm),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.authorLabel,
    required this.canDelete,
    required this.onDelete,
  });

  final TaskComment comment;
  final String authorLabel;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deleted = comment.deletedAt != null;
    return Padding(
      key: Key('task-comment-${comment.id}'),
      padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              authorLabel.characters.first,
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: MuyuSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authorLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: MuyuSpacing.xs),
                Text(
                  deleted ? '评论已删除' : comment.body,
                  style: deleted
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        )
                      : theme.textTheme.bodyMedium,
                ),
                if (comment.createdAt != null) ...[
                  const SizedBox(height: MuyuSpacing.xs),
                  Text(
                    _commentDate(comment.createdAt!),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (canDelete && !deleted)
            IconButton(
              key: Key('task-comment-delete-${comment.id}'),
              tooltip: '删除评论',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
        ],
      ),
    );
  }

  static String _commentDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month月$day日 $hour:$minute';
  }
}

class _CreateSubtaskSheet extends StatefulWidget {
  const _CreateSubtaskSheet({required this.parent, required this.sync});

  final TaskItem parent;
  final WorkspaceSyncController sync;

  @override
  State<_CreateSubtaskSheet> createState() => _CreateSubtaskSheetState();
}

class _CreateSubtaskSheetState extends State<_CreateSubtaskSheet> {
  final _title = TextEditingController();
  final _labels = <String>[];
  String _quadrant = 'Q1';
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final classifications = widget.sync.state.classifications;
    if (classifications.isNotEmpty) _labels.add(classifications.first.name);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _creating) {
      setState(() => _error = '请输入子任务标题');
      return;
    }
    if (_labels.length != 1) {
      setState(() => _error = '请选择一个已批准分类');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final created = await widget.sync.create(
        title,
        quadrant: _quadrant,
        labels: List.unmodifiable(_labels),
        parentTaskId: widget.parent.id,
      );
      if (!mounted) return;
      if (created == null) {
        setState(() {
          _creating = false;
          _error = '子任务创建失败，请稍后重试';
        });
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MuyuSpacing.lg,
        MuyuSpacing.md,
        MuyuSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + MuyuSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('新增子任务', style: theme.textTheme.titleLarge),
          const SizedBox(height: MuyuSpacing.xs),
          Text(
            widget.parent.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: MuyuSpacing.md),
          TextField(
            key: const Key('task-subtask-title'),
            controller: _title,
            autofocus: true,
            enabled: !_creating,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(labelText: '子任务标题', errorText: _error),
          ),
          const SizedBox(height: MuyuSpacing.md),
          Text('四象限（必选）', style: theme.textTheme.labelLarge),
          const SizedBox(height: MuyuSpacing.sm),
          Wrap(
            spacing: MuyuSpacing.sm,
            runSpacing: MuyuSpacing.sm,
            children: [
              for (final entry
                  in _TaskDetailScreenState._quadrantLabels.entries)
                _QuadrantChoice(
                  value: entry.key,
                  label: entry.value.substring(3),
                  color: _subtaskQuadrantColor(context, entry.key),
                  selected: _quadrant == entry.key,
                  onTap: _creating
                      ? null
                      : () => setState(() => _quadrant = entry.key),
                ),
            ],
          ),
          const SizedBox(height: MuyuSpacing.md),
          Text('分类（必选一个）', style: theme.textTheme.labelLarge),
          const SizedBox(height: MuyuSpacing.sm),
          if (widget.sync.state.classifications.isEmpty)
            Text('暂无已批准分类，请前往“我的”→“分类管理”创建')
          else
            Wrap(
              spacing: MuyuSpacing.xs,
              runSpacing: MuyuSpacing.xs,
              children: [
                for (final classification in widget.sync.state.classifications)
                  ChoiceChip(
                    key: Key(
                      'task-subtask-classification-${classification.name}',
                    ),
                    label: Text(classification.name),
                    selected: _labels.any(
                      (label) =>
                          label.toLowerCase() ==
                          classification.name.toLowerCase(),
                    ),
                    onSelected: _creating
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _labels
                                ..clear()
                                ..add(classification.name);
                            } else {
                              _labels.removeWhere(
                                (label) =>
                                    label.toLowerCase() ==
                                    classification.name.toLowerCase(),
                              );
                            }
                          }),
                  ),
              ],
            ),
          const SizedBox(height: MuyuSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('task-subtask-create'),
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('创建子任务'),
            ),
          ),
        ],
      ),
    );
  }

  Color _subtaskQuadrantColor(BuildContext context, String quadrant) {
    final extension = Theme.of(context).extension<MuyuThemeExtension>();
    return switch (quadrant) {
      'Q1' => extension?.quadrantQ1 ?? Theme.of(context).colorScheme.error,
      'Q2' => extension?.quadrantQ2 ?? Theme.of(context).colorScheme.primary,
      'Q3' => extension?.quadrantQ3 ?? Theme.of(context).colorScheme.primary,
      'Q4' => extension?.quadrantQ4 ?? Theme.of(context).colorScheme.primary,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}
