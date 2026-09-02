import 'package:flutter/material.dart';

import '../devices/device_management_repository.dart';
import '../theme/muyu_theme.dart';
import '../workspace/device_repository.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    required this.repository,
    this.canWrite = true,
  });

  final DeviceManagementRepository repository;
  final bool canWrite;

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  late Future<List<DeviceSummary>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.repository.list();
  }

  void _reload() {
    setState(() {
      _devices = widget.repository.list();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      key: const Key('device-management-app-bar'),
      title: Text('设备管理', style: Theme.of(context).textTheme.titleLarge),
      actions: [
        IconButton(
          tooltip: '刷新设备',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<DeviceSummary>>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        final devices = snapshot.data ?? const <DeviceSummary>[];
        if (devices.isEmpty) {
          return const Center(child: Text('暂无 Android 设备'));
        }
        return ListView(
          padding: const EdgeInsets.all(MuyuSpacing.lg),
          children: [
            for (final device in devices) ...[
              _deviceTile(device),
              const SizedBox(height: MuyuSpacing.xs),
            ],
          ],
        );
      },
    ),
  );

  Widget _deviceTile(DeviceSummary device) {
    final canRevoke =
        widget.canWrite && !device.isCurrent && device.status != 'REVOKED';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.phone_android_outlined),
        title: Text(
          device.label?.trim().isNotEmpty == true
              ? device.label!
              : 'Android 设备',
        ),
        subtitle: Text('${_statusLabel(device.status)} · ${device.platform}'),
        trailing: device.isCurrent
            ? const Chip(label: Text('当前设备'))
            : canRevoke
            ? IconButton(
                key: Key('revoke-device-${device.id}'),
                tooltip: '撤销设备',
                onPressed: () => _confirmRevoke(device),
                icon: const Icon(Icons.block_outlined),
              )
            : null,
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
            key: const Key('confirm-revoke-device'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.revoke(device.id);
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('撤销设备失败，请稍后重试')));
    }
  }

  static String _statusLabel(String status) => switch (status) {
    'VERIFIED' || 'ACTIVE' => '已验证',
    'UNVERIFIED' || 'PENDING' => '未验证',
    'REVOKED' => '已撤销',
    _ => status,
  };
}
