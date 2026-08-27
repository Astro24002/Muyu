import 'package:flutter/material.dart';

import '../auth/mobile_session_store.dart';
import '../workspace/device_repository.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    required this.session,
    required this.repository,
  });

  final MobileSession session;
  final DeviceRepository repository;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<List<DeviceSummary>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.repository.listDevices();
  }

  void _reload() {
    setState(() => _devices = widget.repository.listDevices());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
    body: ListView(
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
    ),
  );

  Widget _deviceTile(DeviceSummary device) {
    final status = switch (device.status) {
      'ACTIVE' => '长期绑定',
      'PENDING' => '等待授权',
      'REVOKED' => '已撤销',
      _ => device.status,
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.phone_android_outlined),
        title: Text(device.label?.trim().isNotEmpty == true
            ? device.label!
            : 'Android 设备'),
        subtitle: Text('$status · ${device.platform}'),
        trailing: device.isCurrent
            ? const Chip(label: Text('当前设备'))
            : null,
        isThreeLine: false,
      ),
    );
  }
}
