import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../platform/device_signing_key.dart';
import '../workspace/workspace_bootstrap_controller.dart';
import '../workspace/workspace_bootstrap_repository.dart';
import 'cloud_workspace_screen.dart';
import 'workspace_bootstrap_screen.dart';

class WorkspaceGate extends StatefulWidget {
  const WorkspaceGate({
    super.key,
    required this.api,
    required this.signingKey,
    required this.repository,
  });

  final ApiClient api;
  final DeviceSigningKey signingKey;
  final WorkspaceBootstrapRepository repository;

  @override
  State<WorkspaceGate> createState() => _WorkspaceGateState();
}

class _WorkspaceGateState extends State<WorkspaceGate> {
  late final WorkspaceBootstrapController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WorkspaceBootstrapController(widget.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      switch (_controller.state.status) {
        case WorkspaceBootstrapStatus.ready:
          return CloudWorkspaceScreen(
            key: ValueKey(_controller.state.workspace!.id),
            api: widget.api,
            signingKey: widget.signingKey,
          );
        case WorkspaceBootstrapStatus.loading:
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        case WorkspaceBootstrapStatus.needsWorkspace:
        case WorkspaceBootstrapStatus.creatingWorkspace:
        case WorkspaceBootstrapStatus.failure:
          return WorkspaceBootstrapScreen(
            state: _controller.state,
            onCreate: _controller.createWorkspace,
            onRetry: _controller.load,
          );
      }
    },
  );
}
