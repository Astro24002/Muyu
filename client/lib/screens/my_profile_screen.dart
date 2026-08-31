import 'package:flutter/material.dart';

import '../auth/mobile_session_store.dart';
import '../devices/device_management_repository.dart';
import '../workspace/device_repository.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    required this.session,
    required this.repository,
    this.managementRepository,
    this.canWrite = true,
    this.showAppBar = true,
    this.onWebQrLogin,
  });

  final MobileSession session;
  final DeviceRepository repository;
  final DeviceManagementRepository? managementRepository;
  final bool canWrite;
  final bool showAppBar;
  final VoidCallback? onWebQrLogin;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<List<DeviceSummary>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = _loadDevices();
  }

  void _reload() {
    setState(() {
      _devices = _loadDevices();
    });
  }

  Future<List<DeviceSummary>> _loadDevices() async {
    final devices =
        await (widget.managementRepository?.list() ??
            widget.repository.listDevices());
    return devices
        .where((device) => device.platform.toUpperCase() == 'ANDROID')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
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
        const SizedBox(height: 20),
        Text('登录设备', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<DeviceSummary>>(
          future: _devices,
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
                  Text('设备列表加载失败，请重试'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              );
            }
            final devices = snapshot.data ?? const <DeviceSummary>[];
            if (devices.isEmpty) return const Text('暂无登录设备');
            return Column(
              children: [for (final device in devices) _deviceTile(device)],
            );
          },
        ),
      ],
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

  Widget _deviceTile(DeviceSummary device) {
    final status = switch (device.status) {
      'VERIFIED' || 'ACTIVE' => '已验证 · 长期绑定',
      'UNVERIFIED' || 'PENDING' => '未验证 · 等待授权',
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
}
