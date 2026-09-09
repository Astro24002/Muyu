import 'package:flutter/material.dart';

import '../models/classification.dart';
import '../sync/workspace_sync_controller.dart';
import '../theme/muyu_theme.dart';
import '../widgets/route_settle.dart';

/// Shows classifications that are already approved in the current workspace.
///
/// Creating a classification intentionally goes through the same approval
/// request used everywhere else in the client. This screen only owns the
/// entry point and the resulting user feedback.
class ClassificationManagementScreen extends StatefulWidget {
  const ClassificationManagementScreen({
    super.key,
    required this.sync,
    this.canWrite = true,
  });

  final WorkspaceSyncController sync;
  final bool canWrite;

  @override
  State<ClassificationManagementScreen> createState() =>
      _ClassificationManagementScreenState();
}

class _ClassificationManagementScreenState
    extends State<ClassificationManagementScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('classification-management-screen'),
    appBar: AppBar(title: const Text('分类管理')),
    body: AnimatedBuilder(
      animation: widget.sync,
      builder: (context, _) =>
          _body(context, widget.sync.state.classifications),
    ),
  );

  Widget _body(
    BuildContext context,
    List<WorkspaceClassification> classifications,
  ) => ListView(
    key: const Key('classification-management-list'),
    padding: const EdgeInsets.all(MuyuSpacing.lg),
    children: [
      Text('已批准分类', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: MuyuSpacing.sm),
      if (classifications.isEmpty)
        const Card(
          child: ListTile(
            key: Key('classification-management-empty'),
            leading: Icon(Icons.label_outline),
            title: Text('暂无已批准分类'),
            subtitle: Text('新建分类需要对方审批通过后才能用于任务'),
          ),
        )
      else
        Card(
          child: Column(
            children: [
              for (var index = 0; index < classifications.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                ListTile(
                  key: Key(
                    'classification-management-item-${classifications[index].id}',
                  ),
                  leading: const Icon(Icons.label_outline),
                  title: Text(classifications[index].name),
                  subtitle: const Text('已批准'),
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: MuyuSpacing.lg),
      if (widget.canWrite)
        FilledButton.icon(
          key: const Key('classification-management-create'),
          onPressed: _openCreateClassification,
          icon: const Icon(Icons.add),
          label: const Text('新建分类'),
        ),
    ],
  );

  Future<void> _openCreateClassification() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          key: const Key('create-classification-input'),
          controller: controller,
          autofocus: true,
          maxLength: WorkspaceClassification.maxNameLength,
          decoration: const InputDecoration(hintText: '最多 5 个字符'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('create-classification-submit'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('提交审批'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (!mounted || trimmed.isEmpty) {
      await waitForRouteDismissal();
      controller.dispose();
      return;
    }
    // The dialog future completes before its reverse transition has finished.
    // Wait for the overlay to leave the tree before notifying workspace
    // listeners, otherwise AnimatedBuilder can hit an inherited-element
    // deactivation assertion.
    await waitForRouteDismissal();
    controller.dispose();
    if (!mounted) return;
    try {
      final approval = await widget.sync.createClassification(trimmed);
      if (!mounted) return;
      _showFeedback(approval == null ? '分类暂时无法提交，请刷新后重试' : '分类已提交，等待对方审批');
    } catch (_) {
      if (!mounted) return;
      _showFeedback('分类提交失败，请检查后重试');
    }
  }

  void _showFeedback(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }
}
