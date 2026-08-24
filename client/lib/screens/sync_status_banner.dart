import 'package:flutter/material.dart';

import '../sync/workspace_sync_controller.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({
    super.key,
    required this.controller,
    required this.onRefresh,
  });

  final WorkspaceSyncController controller;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final label =
        state.errorMessage ??
        (state.isStale ? '缓存可能已过期' : '已同步到游标 ${state.cursor}');
    return MaterialBanner(
      content: Text(label),
      leading: Icon(
        state.isStale ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
      ),
      actions: [
        IconButton(
          tooltip: '手动刷新',
          onPressed: state.loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
