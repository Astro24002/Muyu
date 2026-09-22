import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/task.dart';
import '../models/task_approval_request.dart';
import '../sync/workspace_sync_controller.dart';
import '../tasks/task_status.dart';
import '../theme/muyu_theme.dart';
import '../widgets/route_settle.dart';

class _UnavailableOriginalValue {
  const _UnavailableOriginalValue();
}

class TaskApprovalScreen extends StatefulWidget {
  const TaskApprovalScreen({
    super.key,
    required this.sync,
    required this.currentUserId,
    this.canWrite = true,
  });

  final WorkspaceSyncController sync;
  final String currentUserId;
  final bool canWrite;

  @override
  State<TaskApprovalScreen> createState() => _TaskApprovalScreenState();
}

class _TaskApprovalScreenState extends State<TaskApprovalScreen> {
  bool _loading = false;
  final Set<String> _submittingRequestIds = <String>{};

  @override
  void initState() {
    super.initState();
    // A request may have been created on the partner device after the
    // workspace snapshot was loaded. Refresh when the approval surface opens
    // so the two boxes are authoritative even without a realtime hint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.sync.listApprovalRequests();
    } catch (_) {
      // The controller keeps the authoritative error message.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.sync,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final state = widget.sync.state;
    final viewerId = widget.currentUserId.isNotEmpty
        ? widget.currentUserId
        : (state.snapshot?.viewerUserId ?? '');
    final incoming = state.approvalRequests
        .where((request) => request.isIncoming(viewerId) && _isPending(request))
        .toList();
    final outgoing = state.approvalRequests
        .where((request) => request.isOutgoing(viewerId) && _isPending(request))
        .toList();
    final history = state.approvalRequests
        .where((request) => !_isPending(request))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务审批'),
        actions: [
          IconButton(
            key: const Key('approval-refresh-button'),
            tooltip: '刷新审批',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.canWrite)
            const MaterialBanner(
              key: Key('approval-read-only-banner'),
              content: Text('当前设备尚未验证，仅可查看审批状态'),
              actions: [SizedBox.shrink()],
            ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(MuyuSpacing.md),
              child: Text(
                state.errorMessage!,
                key: const Key('approval-error'),
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '待我审批'),
                      Tab(text: '我发起的请求'),
                      Tab(text: '审批记录'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _requestList(
                          incoming,
                          emptyLabel: '暂无待我审批请求',
                          incoming: true,
                        ),
                        _requestList(
                          outgoing,
                          emptyLabel: '暂无我发起的请求',
                          incoming: false,
                        ),
                        _requestList(
                          history,
                          emptyLabel: '暂无审批记录',
                          incoming: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestList(
    List<TaskApprovalRequest> requests, {
    required String emptyLabel,
    required bool incoming,
  }) {
    if (requests.isEmpty) return Center(child: Text(emptyLabel));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        MuyuSpacing.md,
        MuyuSpacing.sm,
        MuyuSpacing.md,
        MuyuSpacing.md,
      ),
      itemCount: requests.length,
      itemBuilder: (context, index) =>
          _requestCard(context, requests[index], incoming: incoming),
    );
  }

  bool _isPending(TaskApprovalRequest request) =>
      request.status.toUpperCase() == 'PENDING';

  Widget _requestCard(
    BuildContext context,
    TaskApprovalRequest request, {
    required bool incoming,
  }) {
    final task = widget.sync.state.snapshot?.tasks
        .where((item) => item.id == request.taskId)
        .firstOrNull;
    final pending = request.status.toUpperCase() == 'PENDING';
    final submitting = _submittingRequestIds.contains(request.id);
    final theme = Theme.of(context);
    return Card(
      key: Key('approval-card-${request.id}'),
      margin: const EdgeInsets.only(bottom: MuyuSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MuyuSpacing.md,
          vertical: MuyuSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '审批事项',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  _statusLabel(request.status),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _statusColor(theme, request.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MuyuSpacing.xs),
            _initiatorRow(context, request),
            const SizedBox(height: MuyuSpacing.sm),
            _approvalField(
              context,
              label: '审批类别',
              value: Text(
                _approvalTypeLabel(request),
                style: theme.textTheme.bodyMedium,
              ),
              labelKey: const Key('approval-category-label'),
              valueKey: const Key('approval-category-value'),
            ),
            const SizedBox(height: MuyuSpacing.sm),
            _approvalField(
              context,
              label: '变更内容',
              value: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _changeRows(
                  context,
                  request,
                  task: task,
                  pending: pending,
                ),
              ),
              labelKey: const Key('approval-change-label'),
              valueKey: const Key('approval-change-value'),
            ),
            if (request.rejectionReason != null) ...[
              const SizedBox(height: MuyuSpacing.xs),
              _detailRow(context, '说明', _reasonLabel(request.rejectionReason!)),
            ],
            if (incoming && pending && widget.canWrite) ...[
              const SizedBox(height: MuyuSpacing.sm),
              Row(
                children: [
                  FilledButton(
                    key: Key('approval-approve-${request.id}'),
                    onPressed: submitting ? null : () => _approve(request),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: _actionLabel('批准', submitting),
                  ),
                  const SizedBox(width: MuyuSpacing.sm),
                  OutlinedButton(
                    key: Key('approval-reject-${request.id}'),
                    onPressed: submitting ? null : () => _reject(request),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: _actionLabel('拒绝', submitting),
                  ),
                ],
              ),
            ],
            if (!incoming && pending && widget.canWrite) ...[
              const SizedBox(height: MuyuSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: Key('approval-cancel-${request.id}'),
                  onPressed: submitting ? null : () => _confirmCancel(request),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: _actionLabel('撤回请求', submitting),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _approvalField(
    BuildContext context, {
    required String label,
    required Widget value,
    Key? labelKey,
    Key? valueKey,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, key: labelKey, style: labelStyle),
        ),
        Expanded(
          child: KeyedSubtree(key: valueKey, child: value),
        ),
      ],
    );
  }

  Widget _initiatorRow(BuildContext context, TaskApprovalRequest request) {
    final name = _memberDisplayName(request.requesterId) ?? '对方';
    return Row(
      children: [
        Expanded(
          child: Text(
            '$name · 发起',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: MuyuSpacing.sm),
        Flexible(
          child: Text(
            _dateLabel(request.createdAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  String _approvalTypeLabel(TaskApprovalRequest request) =>
      request.proposedChanges['agreement_update'] == true
      ? '修改完成标准'
      : request.proposedChanges['cancellation_request'] == true
      ? '取消任务'
      : _isReviewSubmission(request)
      ? '任务验收'
      : switch (request.requestType.toUpperCase()) {
          'TASK_INVITATION' => '任务邀请',
          'TASK_UPDATE' => '任务修改',
          'QUADRANT_UPDATE' => '四象限修改',
          'STATUS_UPDATE' => '状态修改',
          'TASK_DELETE' => '删除任务',
          'TASK_RESTORE' => '恢复任务',
          'COMMENT_DELETE' => '删除评论',
          'HANDLER_TRANSFER' => '负责人转移',
          'CLASSIFICATION_CREATE' => '新建分类',
          _ => '其他审批事项',
        };

  List<Widget> _changeRows(
    BuildContext context,
    TaskApprovalRequest request, {
    required TaskItem? task,
    required bool pending,
  }) {
    final entries = _orderedChanges(request.proposedChanges)
        .where(
          (entry) =>
              entry.key != 'review_submission' &&
              entry.key != 'agreement_update' &&
              entry.key != 'cancellation_request',
        )
        .toList();
    if (entries.isEmpty) {
      return [Text('无字段变更', style: Theme.of(context).textTheme.bodyMedium)];
    }
    return [
      for (var index = 0; index < entries.length; index++) ...[
        if (index > 0) const SizedBox(height: MuyuSpacing.xs),
        _changeRow(
          context,
          request,
          entries[index].key,
          entries[index].value,
          task: task,
          pending: pending,
        ),
      ],
    ];
  }

  Widget _changeRow(
    BuildContext context,
    TaskApprovalRequest request,
    String field,
    Object? proposedValue, {
    required TaskItem? task,
    required bool pending,
  }) {
    final oldValue = _originalValue(
      request,
      field,
      task: task,
      pending: pending,
    );
    final reviewSubmission =
        _isReviewSubmission(request) &&
        (field == 'target_status' || field == 'status');
    final oldLabel = reviewSubmission
        ? '进行中'
        : oldValue is _UnavailableOriginalValue
        ? '原内容未记录'
        : request.requestType.toUpperCase() == 'CLASSIFICATION_CREATE' &&
              field == 'name' &&
              oldValue == null
        ? '无'
        : _changeValue(field, oldValue);
    final newLabel = reviewSubmission
        ? '待验收'
        : _changeValue(field, proposedValue);
    return Text(
      '${_fieldLabel(field)}：$oldLabel → $newLabel',
      key: Key('approval-change-row-$field'),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) =>
      _approvalField(
        context,
        label: label,
        value: Text(value, style: Theme.of(context).textTheme.bodyMedium),
      );

  Object? _originalValue(
    TaskApprovalRequest request,
    String field, {
    required TaskItem? task,
    required bool pending,
  }) {
    if (request.requestType.toUpperCase() == 'CLASSIFICATION_CREATE' &&
        field == 'name') {
      return null;
    }
    // The current snapshot is a trustworthy base only while the request is
    // pending and every requested field still has its recorded base version.
    // Resolved requests do not carry old values in the API contract, so never
    // present their current task value as historical data.
    if (!pending || task == null) return const _UnavailableOriginalValue();
    final version = task.fieldVersions[field];
    final baseVersion = request.baseFieldVersions[field];
    if (baseVersion == null || version != baseVersion) {
      return const _UnavailableOriginalValue();
    }
    return switch (field) {
      'title' => task.title,
      'description' => task.description,
      'acceptance_criteria' => task.acceptanceCriteria,
      'due_at' => task.dueAt,
      'planned_start_at' => task.plannedStartAt,
      'estimated_minutes' => task.estimatedMinutes,
      'quadrant' => task.quadrant,
      'labels' => task.labels,
      'progress' => task.progress,
      'target_status' || 'status' => task.status,
      'current_handler_id' || 'handler_id' => task.currentHandlerId,
      'resume_handler_id' => task.resumeHandlerId,
      'waiting_for_user_id' => task.waitingForUserId,
      'blocked_reason' => task.blockedReason,
      'review_rejection_reason' => task.reviewRejectionReason,
      _ => const _UnavailableOriginalValue(),
    };
  }

  Color _statusColor(ThemeData theme, String status) =>
      switch (status.toUpperCase()) {
        'PENDING' => theme.colorScheme.primary,
        'APPROVED' => Colors.green.shade700,
        'REJECTED' || 'CONFLICTED' => theme.colorScheme.error,
        'CANCELLED' => theme.colorScheme.onSurfaceVariant,
        _ => theme.colorScheme.onSurfaceVariant,
      };

  String? _memberDisplayName(String userId) {
    for (final member
        in widget.sync.state.snapshot?.members ??
            const <Map<String, dynamic>>[]) {
      final memberId = member['user_id'];
      if (memberId is! String ||
          memberId.toLowerCase() != userId.toLowerCase()) {
        continue;
      }
      final displayName = member['display_name'];
      if (displayName is String && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
      return null;
    }
    return null;
  }

  static List<MapEntry<String, dynamic>> _orderedChanges(
    Map<String, dynamic> changes,
  ) {
    const order = [
      'title',
      'description',
      'acceptance_criteria',
      'due_at',
      'planned_start_at',
      'estimated_minutes',
      'quadrant',
      'labels',
      'progress',
      'target_status',
      'status',
      'current_handler_id',
      'handler_id',
      'resume_handler_id',
      'waiting_for_user_id',
      'blocked_reason',
      'review_rejection_reason',
      'cancel_reason',
      'name',
    ];
    final ordered = <MapEntry<String, dynamic>>[];
    for (final key in order) {
      if (changes.containsKey(key)) {
        ordered.add(MapEntry(key, changes[key]));
      }
    }
    for (final entry in changes.entries) {
      if (!order.contains(entry.key)) ordered.add(entry);
    }
    return ordered;
  }

  String _changeValue(String field, Object? value) {
    switch (field) {
      case 'quadrant':
        return _quadrantLabel(value);
      case 'target_status':
      case 'status':
        return value is String ? taskStatusLabel(value) : '未设置';
      case 'current_handler_id':
      case 'handler_id':
      case 'resume_handler_id':
      case 'waiting_for_user_id':
        if (value is String) {
          return _memberDisplayName(value) ?? '协作成员';
        }
        return '协作成员';
      case 'due_at':
      case 'planned_start_at':
        return _dateValueLabel(value);
      case 'estimated_minutes':
        return value is num ? '${value.toInt()} 分钟' : '未设置';
      case 'progress':
        return value is num ? '${value.toInt()}%' : '未设置';
      case 'labels':
        return _listValueLabel(value);
      default:
        return _safeValueLabel(value);
    }
  }

  bool _isReviewSubmission(TaskApprovalRequest request) {
    final changes = request.proposedChanges;
    return request.requestType.toUpperCase() == 'STATUS_UPDATE' &&
        changes['review_submission'] == true &&
        changes['target_status'] == 'DONE';
  }

  static String _fieldLabel(String field) => switch (field) {
    'title' => '任务标题',
    'description' => '任务描述',
    'acceptance_criteria' => '完成标准',
    'due_at' => '截止时间',
    'planned_start_at' => '计划开始',
    'estimated_minutes' => '预计时长',
    'quadrant' => '四象限',
    'labels' => '分类',
    'progress' => '完成进度',
    'target_status' || 'status' => '任务状态',
    'current_handler_id' => '负责人',
    'handler_id' => '负责人',
    'resume_handler_id' => '恢复后负责人',
    'waiting_for_user_id' => '等待成员',
    'blocked_reason' => '阻塞原因',
    'review_rejection_reason' => '退回原因',
    'cancel_reason' => '取消原因',
    'name' => '分类名称',
    _ => '变更项',
  };

  static String _quadrantLabel(Object? value) => switch (value) {
    'Q1' => 'Q1 重要且紧急',
    'Q2' => 'Q2 重要不紧急',
    'Q3' => 'Q3 紧急不重要',
    'Q4' => 'Q4 不重要不紧急',
    _ => '未设置',
  };

  static String _dateValueLabel(Object? value) {
    if (value == null) return '未设置';
    final parsed = value is DateTime
        ? value
        : value is String
        ? DateTime.tryParse(value)
        : null;
    return parsed == null ? '未设置' : _dateLabel(parsed);
  }

  static String _dateLabel(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year年$month月$day日 $hour:$minute';
  }

  static String _listValueLabel(Object? value) {
    if (value is! List) return _safeValueLabel(value);
    final values = value.map(_safeValueLabel).where((item) => item.isNotEmpty);
    final result = values.join('、');
    return result.isEmpty ? '未设置' : result;
  }

  static String _safeValueLabel(Object? value) {
    if (value == null) return '未设置';
    if (value is bool) return value ? '是' : '否';
    if (value is Map) return '已更新';
    final text = '$value'.trim();
    if (text.isEmpty) return '未设置';
    if (RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(text)) {
      return '协作成员';
    }
    if (RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$').hasMatch(text)) {
      return '已更新';
    }
    final parsed = DateTime.tryParse(text);
    return parsed == null ? text : _dateLabel(parsed);
  }

  Future<void> _approve(TaskApprovalRequest request) async {
    await _performAction(
      request,
      widget.sync.approveApproval,
      successMessage: '审批已通过',
    );
  }

  Future<void> _reject(TaskApprovalRequest request) async {
    String? reason;
    if (_isReviewSubmission(request) ||
        request.requestType.toUpperCase() == 'TASK_INVITATION') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          String? errorText;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                request.requestType.toUpperCase() == 'TASK_INVITATION'
                    ? '暂不同意任务邀请'
                    : '退回待验收任务',
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText:
                      request.requestType.toUpperCase() == 'TASK_INVITATION'
                      ? '回应与建议'
                      : '退回原因',
                  errorText: errorText,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setDialogState(() => errorText = '请填写退回原因');
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: const Text('确认退回'),
                ),
              ],
            ),
          );
        },
      );
      await waitForRouteDismissal();
      controller.dispose();
      if (!mounted || reason == null) return;
    }
    await _performAction(
      request,
      (approvalId) => widget.sync.rejectApproval(approvalId, reason: reason),
      successMessage: '审批已拒绝',
    );
  }

  Future<void> _cancel(TaskApprovalRequest request) async {
    await _performAction(
      request,
      widget.sync.cancelApproval,
      successMessage: '请求已取消',
    );
  }

  Future<void> _confirmCancel(TaskApprovalRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤回审批请求？'),
        content: const Text('撤回后对方将无法继续审批，需要重新提交请求。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await waitForRouteDismissal();
    if (mounted) await _cancel(request);
  }

  Future<void> _performAction(
    TaskApprovalRequest request,
    Future<ApprovalActionResult> Function(String approvalId) action, {
    required String successMessage,
  }) async {
    if (_submittingRequestIds.contains(request.id)) return;
    setState(() => _submittingRequestIds.add(request.id));
    try {
      await action(request.id);
      _showFeedback(successMessage);
    } catch (error) {
      _showFeedback(_actionErrorMessage(error));
      // The partner may have resolved the request while this page was open.
      // Reconcile the authoritative snapshot so a stale pending card cannot
      // leave the user with an action that can no longer succeed.
      try {
        await widget.sync.refresh();
      } catch (_) {
        // Keep the original action error visible when reconciliation fails.
      }
    } finally {
      if (mounted) {
        setState(() => _submittingRequestIds.remove(request.id));
      }
    }
  }

  Widget _actionLabel(String label, bool submitting) {
    if (!submitting) return Text(label);
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  void _showFeedback(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  String _actionErrorMessage(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return '操作失败，请刷新后重试';
  }

  static String _statusLabel(String status) => switch (status.toUpperCase()) {
    'PENDING' => '待审批',
    'APPROVED' => '已批准',
    'REJECTED' => '已拒绝',
    'CONFLICTED' => '已失效',
    'CANCELLED' => '已撤回',
    _ => '状态未知',
  };

  static String _reasonLabel(String reason) {
    final normalized = reason.trim();
    final label = switch (normalized) {
      'cancelled by requester' => '请求方已撤回请求',
      'task handler changed' => '任务负责人已变更',
      'task was deleted' => '任务已删除',
      'task was restored' => '任务已恢复',
      'comment or task lifecycle changed' => '评论或任务状态已变化',
      'comment version changed' => '评论内容已变化',
      'comment author changed' => '评论作者已变化',
      'classification already exists' => '分类已存在',
      _ => null,
    };
    if (label != null) return label;
    if (normalized.startsWith('task field ') &&
        normalized.endsWith(' changed')) {
      return '任务内容已变化';
    }
    if (normalized.isEmpty) return '审批状态已更新';
    return normalized;
  }
}
