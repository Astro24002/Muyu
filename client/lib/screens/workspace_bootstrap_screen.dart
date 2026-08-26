import 'package:flutter/material.dart';

import '../workspace/workspace_bootstrap_controller.dart';

class WorkspaceBootstrapScreen extends StatelessWidget {
  const WorkspaceBootstrapScreen({
    super.key,
    required this.state,
    required this.onCreate,
    required this.onRetry,
  });

  final WorkspaceBootstrapState state;
  final Future<void> Function() onCreate;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final creating = state.status == WorkspaceBootstrapStatus.creatingWorkspace;
    final loading = state.status == WorkspaceBootstrapStatus.loading;
    final failed = state.status == WorkspaceBootstrapStatus.failure;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '创建共享空间',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ??
                      (failed ? '无法加载共享空间，请稍后重试' : '先创建一个共享空间，然后开始协作。'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (failed)
                  OutlinedButton(onPressed: onRetry, child: const Text('重试'))
                else
                  FilledButton(
                    onPressed: creating || loading ? null : onCreate,
                    child: creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('创建共享空间'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
