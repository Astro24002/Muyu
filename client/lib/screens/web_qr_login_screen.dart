import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../auth/web_session_controller.dart';

class WebQrLoginScreen extends StatefulWidget {
  const WebQrLoginScreen({super.key, required this.controller});

  final WebSessionController controller;

  @override
  State<WebQrLoginScreen> createState() => _WebQrLoginScreenState();
}

class _WebQrLoginScreenState extends State<WebQrLoginScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.start();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (widget.controller.status == WebSessionStatus.waitingForApproval) {
        widget.controller.poll();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final challenge = widget.controller.challenge;
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '使用 Android 扫码登录',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  if (challenge != null) ...[
                    QrImageView(data: challenge.qrPayload, size: 240),
                    Text('安全码 ${challenge.safetyCode}'),
                    Text(challenge.origin),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.controller.poll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('检查授权状态'),
                    ),
                  ] else if (widget.controller.errorMessage != null)
                    Text(widget.controller.errorMessage!),
                  if (widget.controller.status == WebSessionStatus.expired)
                    FilledButton(
                      onPressed: widget.controller.start,
                      child: const Text('重新生成二维码'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
