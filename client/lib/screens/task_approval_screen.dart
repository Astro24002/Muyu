import 'package:flutter/material.dart';

import '../models/task_approval_request.dart';
import '../sync/workspace_sync_controller.dart';

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
  Widget build(BuildContext context) {
    final state = widget.sync.state;
    final incoming = state.approvalRequests
        .where((request) => request.isIncoming(widget.currentUserId))
        .toList();
    final outgoing = state.approvalRequests
        .where((request) => request.isOutgoing(widget.currentUserId))
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
              padding: const EdgeInsets.all(12),
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
      padding: const EdgeInsets.all(12),
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
        ? request.taskId
        : '${task.taskNumber.isEmpty ? task.id : task.taskNumber} ${task.title}';
    final pending = request.status == 'PENDING';
    return Card(
      key: Key('approval-card-${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(taskLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${_typeLabel(request.requestType)} · ${request.status}'),
            Text('发起人：${request.requesterId}'),
            Text('审批人：${request.approverId}'),
            if (request.proposedChanges.isNotEmpty)
              Text('变更：${request.proposedChanges}'),
            if (request.rejectionReason != null)
              Text('说明：${request.rejectionReason}'),
            if (incoming && pending && widget.canWrite)
              Row(
                children: [
                  FilledButton(
                    key: Key('approval-approve-${request.id}'),
                    onPressed: () => _approve(request),
                    child: const Text('批准'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: Key('approval-reject-${request.id}'),
                    onPressed: () => _reject(request),
                    child: const Text('拒绝'),
                  ),
                ],
              ),
            if (!incoming && pending && widget.canWrite)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: Key('approval-cancel-${request.id}'),
                  onPressed: () => _cancel(request),
                  child: const Text('取消请求'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(TaskApprovalRequest request) async {
    try {
      await widget.sync.approveApproval(request.id);
    } catch (_) {
      // The controller exposes the error in its state.
    }
  }

  Future<void> _reject(TaskApprovalRequest request) async {
    try {
      await widget.sync.rejectApproval(request.id);
    } catch (_) {
      // The controller exposes the error in its state.
    }
  }

  Future<void> _cancel(TaskApprovalRequest request) async {
    try {
      await widget.sync.cancelApproval(request.id);
    } catch (_) {
      // The controller exposes the error in its state.
    }
  }

  static String _typeLabel(String type) => switch (type) {
    'TASK_UPDATE' => '任务修改',
    'QUADRANT_UPDATE' => '四象限修改',
    'STATUS_UPDATE' => '状态修改',
    'TASK_DELETE' => '删除任务',
    'TASK_RESTORE' => '恢复任务',
    'COMMENT_DELETE' => '删除评论',
    'ASSIGNEE_UPDATE' => '协作者修改',
    'HANDLER_TRANSFER' => '负责人转移',
    _ => type,
  };
}
