import 'package:flutter/material.dart';

import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../platform/device_signing_key.dart';
import '../workspace/device_authorization_repository.dart';
import '../workspace/device_repository.dart';
import '../workspace/workspace_bootstrap_repository.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    required this.session,
    required this.repository,
    this.managementRepository,
    this.workspaceRepository,
    this.authorizationRepository,
    this.signingKey,
    this.enrollmentReady,
    this.canWrite = true,
    this.showAppBar = true,
    this.onWebQrLogin,
  });

  final MobileSession session;
  final DeviceRepository repository;
  final DeviceManagementRepository? managementRepository;
  final WorkspaceBootstrapRepository? workspaceRepository;
  final DeviceAuthorizationRepository? authorizationRepository;
  final DeviceSigningKey? signingKey;
  final Future<void>? enrollmentReady;
  final bool canWrite;
  final bool showAppBar;
  final VoidCallback? onWebQrLogin;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<_ProfileData> _profile;
  String? _busyRequestId;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  void _reload() {
    setState(() {
      _profile = _loadProfile();
    });
  }

  Future<void> _refresh() async {
    final next = _loadProfile();
    setState(() => _profile = next);
    try {
      await next;
    } catch (_) {
      // FutureBuilder keeps the stable error state visible.
    }
  }

  Future<_ProfileData> _loadProfile() async {
    if (widget.enrollmentReady != null) {
      await widget.enrollmentReady;
    }
    final devices =
        await (widget.managementRepository?.list() ??
            widget.repository.listDevices());
    final androidDevices = devices
        .where((device) => device.platform.toUpperCase() == 'ANDROID')
        .toList(growable: false);
    final workspace = widget.workspaceRepository == null
        ? null
        : await widget.workspaceRepository!.loadBootstrap();
    final requests = widget.authorizationRepository == null
        ? const <DeviceAuthorizationRequest>[]
        : await widget.authorizationRepository!.listRequests();
    return _ProfileData(
      devices: androidDevices,
      workspace: workspace,
      requests: requests,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(
                widget.session.user.nickname.isEmpty
                    ? '我的账号'
                    : widget.session.user.nickname,
              ),
              subtitle: Text(widget.session.user.phone),
            ),
          ),
          if (widget.onWebQrLogin != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                key: const Key('profile-web-qr-login'),
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('扫码登录 Web'),
                onTap: widget.onWebQrLogin,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FutureBuilder<_ProfileData>(
            future: _profile,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('个人信息加载失败，请重试'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                );
              }
              final data = snapshot.data!;
              return _profileSections(context, data);
            },
          ),
        ],
      ),
    );
    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '刷新设备',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _profileSections(BuildContext context, _ProfileData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.workspaceRepository != null) ...[
        _workspaceCard(data.workspace),
        const SizedBox(height: 16),
      ],
      Text('登录设备', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (data.devices.isEmpty)
        const Text('暂无登录设备')
      else
        for (final device in data.devices) _deviceTile(device),
      if (widget.authorizationRepository != null) ...[
        const SizedBox(height: 16),
        _authorizationSections(data.requests),
      ],
    ],
  );

  Widget _workspaceCard(WorkspaceBootstrapPayload? payload) {
    final workspace = payload?.workspace;
    final matchStatus = workspace?.matchStatus;
    final status = switch (matchStatus) {
      WorkspaceMatchStatus.matched => '已匹配 · 2/2 位成员',
      WorkspaceMatchStatus.error => '匹配异常',
      WorkspaceMatchStatus.waitingPartner => '等待对方加入',
      null =>
        payload?.state == WorkspaceBootstrapPhase.needsPartner
            ? '尚未匹配对方'
            : '共享空间暂不可用',
    };
    return Card(
      key: const Key('profile-workspace-match'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '共享空间',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(status),
              ],
            ),
            if (workspace?.members.isNotEmpty == true) ...[
              const Divider(height: 20),
              for (final member in workspace!.members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    member.isCurrent
                        ? Icons.person_outline
                        : Icons.person_add_alt_1_outlined,
                  ),
                  title: Text(member.isCurrent ? '我' : '对方'),
                  subtitle: Text(
                    member.displayName?.trim().isNotEmpty == true
                        ? '${member.displayName} · ${member.phoneMasked}'
                        : member.phoneMasked,
                  ),
                  trailing: Text(
                    member.membershipStatus == 'ACTIVE' ? '已加入' : '待加入',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _authorizationSections(List<DeviceAuthorizationRequest> requests) {
    final incoming = requests
        .where((request) => request.isIncoming && request.status == 'PENDING')
        .toList(growable: false);
    final outgoing = requests
        .where((request) => !request.isIncoming)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('待处理的设备验证', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (incoming.isEmpty)
          const Text('暂无待处理请求')
        else
          for (final request in incoming) _incomingRequestTile(request),
        const SizedBox(height: 16),
        Text('我发起的设备验证', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (outgoing.isEmpty)
          const Text('暂无发起请求')
        else
          for (final request in outgoing) _outgoingRequestTile(request),
      ],
    );
  }

  Widget _incomingRequestTile(DeviceAuthorizationRequest request) => Card(
    child: ListTile(
      title: Text(
        request.candidateDeviceLabel?.trim().isNotEmpty == true
            ? request.candidateDeviceLabel!
            : 'Android 设备',
      ),
      subtitle: Text(
        '${request.candidatePhoneMasked ?? '对方'} · ${request.candidatePlatform ?? 'ANDROID'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            key: const Key('profile-approve-device-request'),
            onPressed: _busyRequestId == request.id
                ? null
                : () => _approveRequest(request),
            child: _busyRequestId == request.id
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('验证设备'),
          ),
          IconButton(
            key: const Key('profile-reject-device-request'),
            tooltip: '拒绝设备',
            onPressed: _busyRequestId == request.id
                ? null
                : () => _rejectRequest(request),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );

  Widget _outgoingRequestTile(DeviceAuthorizationRequest request) => Card(
    child: ListTile(
      title: Text(
        request.candidateDeviceLabel?.trim().isNotEmpty == true
            ? request.candidateDeviceLabel!
            : 'Android 设备',
      ),
      subtitle: Text(
        request.status == 'PENDING'
            ? '等待另一位用户验证'
            : _requestStatusLabel(request.status),
      ),
    ),
  );

  Widget _deviceTile(DeviceSummary device) {
    final status = switch (device.status) {
      'VERIFIED' ||
      'ACTIVE' => device.canWrite ? '已验证 · 长期绑定 · 可读写' : '已验证 · 只读',
      'UNVERIFIED' || 'PENDING' => '未验证 · 只读 · 等待授权',
      'REVOKED' => '已撤销',
      _ => device.status,
    };
    final canRevoke =
        widget.managementRepository != null &&
        widget.canWrite &&
        !device.isCurrent &&
        device.status != 'REVOKED';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.phone_android_outlined),
        title: Text(
          device.label?.trim().isNotEmpty == true
              ? device.label!
              : 'Android 设备',
        ),
        subtitle: Text('$status · ${device.platform}'),
        trailing: device.isCurrent
            ? const Chip(label: Text('当前设备'))
            : canRevoke
            ? IconButton(
                key: Key('profile-revoke-device-${device.id}'),
                tooltip: '撤销设备',
                onPressed: () => _confirmRevoke(device),
                icon: const Icon(Icons.block_outlined),
              )
            : null,
        isThreeLine: false,
      ),
    );
  }

  Future<void> _confirmRevoke(DeviceSummary device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备'),
        content: Text('确定撤销“${device.label ?? 'Android 设备'}”的登录权限吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('profile-confirm-revoke-device'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.managementRepository!.revoke(device.id);
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('撤销设备失败，请稍后重试')));
    }
  }

  Future<void> _approveRequest(DeviceAuthorizationRequest request) async {
    final repository = widget.authorizationRepository;
    final signingKey = widget.signingKey;
    if (repository == null || signingKey == null) {
      _showMessage('当前设备不支持设备验证');
      return;
    }
    setState(() => _busyRequestId = request.id);
    try {
      final challenge = await repository.beginApproval(request.id);
      final payload = challenge.signaturePayload;
      if (payload == null || payload.isEmpty) {
        throw const DeviceAuthorizationFailure('设备验证挑战不可用');
      }
      await repository.approve(
        request.id,
        signingKey: signingKey,
        signaturePayload: payload,
      );
      if (!mounted) return;
      _showMessage('设备验证成功');
      _reload();
    } catch (_) {
      if (mounted) _showMessage('设备验证失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busyRequestId = null);
    }
  }

  Future<void> _rejectRequest(DeviceAuthorizationRequest request) async {
    final repository = widget.authorizationRepository;
    if (repository == null) return;
    setState(() => _busyRequestId = request.id);
    try {
      await repository.reject(request.id);
      if (!mounted) return;
      _reload();
    } catch (_) {
      if (mounted) _showMessage('拒绝设备验证失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busyRequestId = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _requestStatusLabel(String status) => switch (status) {
    'PENDING' => '等待验证',
    'APPROVED' => '已通过',
    'REJECTED' => '已拒绝',
    'EXPIRED' => '已过期',
    _ => status,
  };
}

class _ProfileData {
  const _ProfileData({
    required this.devices,
    required this.workspace,
    required this.requests,
  });

  final List<DeviceSummary> devices;
  final WorkspaceBootstrapPayload? workspace;
  final List<DeviceAuthorizationRequest> requests;
}
