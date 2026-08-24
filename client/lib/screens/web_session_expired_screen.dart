import 'package:flutter/material.dart';

class WebSessionExpiredScreen extends StatelessWidget {
  const WebSessionExpiredScreen({super.key, required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton.icon(
        onPressed: onSignIn,
        icon: const Icon(Icons.qr_code_2),
        label: const Text('扫码重新登录'),
      ),
    ),
  );
}
