import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/task_approval_request.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';

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
        .where((request) => request.isIncoming(viewerId))
        .toList();
    final outgoing = state.approvalRequests
        .where((request) => request.isOutgoing(viewerId))
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
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: '待我审批'),
                      Tab(text: '我发起的请求'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _requestList(incoming, incoming: true),
                        _requestList(outgoing, incoming: false),
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
    required bool incoming,
  }) {
    if (requests.isEmpty) {
      return const Center(child: Text('暂无审批请求'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(MuyuSpacing.md),
      itemCount: requests.length,
      itemBuilder: (context, index) =>
          _requestCard(context, requests[index], incoming: incoming),
    );
  }

  Widget _requestCard(
    BuildContext context,
    TaskApprovalRequest request, {
    required bool incoming,
  }) {
    final task = widget.sync.state.snapshot?.tasks
        .where((item) => item.id == request.taskId)
        .firstOrNull;
    final taskLabel = task == null
        ? request.requestType == 'CLASSIFICATION_CREATE'
              ? '新建分类：${request.proposedChanges['name'] ?? ''}'
              : (request.taskId ?? '协作请求')
        : '${task.taskNumber.isEmpty ? task.id : task.taskNumber} ${task.title}';
    final pending = request.status.toUpperCase() == 'PENDING';
    final submitting = _submittingRequestIds.contains(request.id);
    return Card(
      key: Key('approval-card-${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(MuyuSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(taskLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: MuyuSpacing.xs),
            Text(
              '${_typeLabel(request.requestType)} · ${_statusLabel(request.status)}',
            ),
            Text('发起人：${request.requesterId}'),
            Text('审批人：${request.approverId}'),
            if (!incoming && pending) const Text('等待对方审批，发起人不能审批自己的请求'),
            if (request.proposedChanges.isNotEmpty)
              Text('变更：${request.proposedChanges}'),
            if (request.rejectionReason != null)
              Text('说明：${_reasonLabel(request.rejectionReason!)}'),
            if (incoming && pending && widget.canWrite)
              Row(
                children: [
                  FilledButton(
                    key: Key('approval-approve-${request.id}'),
                    onPressed: submitting ? null : () => _approve(request),
                    child: _actionLabel('批准', submitting),
                  ),
                  const SizedBox(width: MuyuSpacing.sm),
                  OutlinedButton(
                    key: Key('approval-reject-${request.id}'),
                    onPressed: submitting ? null : () => _reject(request),
                    child: _actionLabel('拒绝', submitting),
                  ),
                ],
              ),
            if (!incoming && pending && widget.canWrite)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: Key('approval-cancel-${request.id}'),
                  onPressed: submitting ? null : () => _confirmCancel(request),
                  child: _actionLabel('撤回请求', submitting),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(TaskApprovalRequest request) async {
    await _performAction(
      request,
      widget.sync.approveApproval,
      successMessage: '审批已通过',
    );
  }

  Future<void> _reject(TaskApprovalRequest request) async {
    await _performAction(
      request,
      widget.sync.rejectApproval,
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
    if (confirmed == true && mounted) await _cancel(request);
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

  static String _typeLabel(String type) => switch (type) {
    'TASK_UPDATE' => '任务修改',
    'QUADRANT_UPDATE' => '四象限修改',
    'STATUS_UPDATE' => '状态修改',
    'TASK_DELETE' => '删除任务',
    'TASK_RESTORE' => '恢复任务',
    'COMMENT_DELETE' => '删除评论',
    'HANDLER_TRANSFER' => '负责人转移',
    'CLASSIFICATION_CREATE' => '新建分类',
    _ => type,
  };

  static String _statusLabel(String status) => switch (status.toUpperCase()) {
    'PENDING' => '待审批',
    'APPROVED' => '已批准',
    'REJECTED' => '已拒绝',
    'CONFLICTED' => '已失效',
    'CANCELLED' => '已撤回',
    _ => status,
  };

  static String _reasonLabel(String reason) => switch (reason) {
    'cancelled by requester' => '发起人已撤回请求',
    'task handler changed' => '任务负责人已变更',
    'task was deleted' => '任务已删除',
    'task was restored' => '任务已恢复',
    _ => reason,
  };
}
