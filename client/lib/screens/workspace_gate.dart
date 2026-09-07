import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../auth/mobile_session_store.dart';
import '../platform/device_signing_key.dart';
import '../sync/workspace_cache.dart';
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
    this.session,
    this.sessionStore,
    this.workspaceCache,
  });

  final ApiClient api;
  final DeviceSigningKey signingKey;
  final WorkspaceBootstrapRepository repository;
  final MobileSession? session;
  final MobileSessionStore? sessionStore;
  final WorkspaceCache? workspaceCache;

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
        case WorkspaceBootstrapStatus.readOnlyDevice:
          return CloudWorkspaceScreen(
            key: ValueKey(_controller.state.workspace!.id),
            api: widget.api,
            signingKey: widget.signingKey,
            session: widget.session,
            sessionStore: widget.sessionStore,
            canWrite: _controller.state.canWrite,
            workspaceBootstrapRepository: widget.repository,
            workspaceCache: widget.workspaceCache,
            workspaceId: _controller.state.workspace!.id,
          );
        case WorkspaceBootstrapStatus.waitingForPartner:
          return CloudWorkspaceScreen(
            key: ValueKey(_controller.state.workspace!.id),
            api: widget.api,
            signingKey: widget.signingKey,
            session: widget.session,
            sessionStore: widget.sessionStore,
            canWrite: _controller.state.canWrite,
            waitingForPartner: true,
            workspaceBootstrapRepository: widget.repository,
            workspaceCache: widget.workspaceCache,
            workspaceId: _controller.state.workspace!.id,
          );
        case WorkspaceBootstrapStatus.loading:
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        case WorkspaceBootstrapStatus.needsPartner:
        case WorkspaceBootstrapStatus.bindingPartner:
        case WorkspaceBootstrapStatus.invited:
        case WorkspaceBootstrapStatus.acceptingInvite:
        case WorkspaceBootstrapStatus.needsWorkspace:
        case WorkspaceBootstrapStatus.creatingWorkspace:
        case WorkspaceBootstrapStatus.failure:
          return WorkspaceBootstrapScreen(
            state: _controller.state,
            onCreate: _controller.createWorkspace,
            onBindPartner: _controller.bindPartner,
            onAcceptInvite: _controller.acceptInvite,
            onRetry: _controller.load,
          );
      }
    },
  );
}
