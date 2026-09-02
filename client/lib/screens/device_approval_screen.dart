import 'package:flutter/material.dart';

import '../theme/muyu_theme.dart';
import '../workspace/device_authorization_repository.dart';

class DeviceApprovalScreen extends StatelessWidget {
  const DeviceApprovalScreen({
    super.key,
    required this.request,
    required this.onApprove,
  });

  final DeviceAuthorizationRequest request;
  final Future<void> Function() onApprove;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备授权')),
    body: Padding(
      padding: const EdgeInsets.all(MuyuSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('请核对安全码', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: MuyuSpacing.md),
          SelectableText(
            request.safetyCode ?? '请在另一台设备核对安全码',
            textAlign: TextAlign.center,
          ),
          Text('有效期至 ${request.expiresAt.toLocal()}'),
          const SizedBox(height: MuyuSpacing.xl),
          FilledButton.icon(
            onPressed: request.status == 'PENDING' ? onApprove : null,
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('批准设备'),
          ),
        ],
      ),
    ),
  );
}
