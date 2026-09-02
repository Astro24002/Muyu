import 'package:flutter/material.dart';

import '../auth/mobile_login_controller.dart';
import '../theme/muyu_theme.dart';

class MobilePhoneLoginScreen extends StatefulWidget {
  const MobilePhoneLoginScreen({super.key, required this.controller});

  final MobileLoginController controller;

  @override
  State<MobilePhoneLoginScreen> createState() => _MobilePhoneLoginScreenState();
}

class _MobilePhoneLoginScreenState extends State<MobilePhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(MuyuSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Muyu', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: MuyuSpacing.xl),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '手机号'),
                ),
                const SizedBox(height: MuyuSpacing.md),
                if (widget.controller.status == MobileLoginStatus.codeSent ||
                    widget.controller.status == MobileLoginStatus.failure)
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '短信验证码'),
                  ),
                if (widget.controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MuyuSpacing.md),
                    child: Text(
                      widget.controller.errorMessage!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: MuyuSpacing.xl),
                FilledButton(
                  onPressed:
                      widget.controller.status == MobileLoginStatus.codeSent
                      ? () => widget.controller.verifyCode(_code.text.trim())
                      : () => widget.controller.requestCode(_phone.text.trim()),
                  child: Text(
                    widget.controller.status == MobileLoginStatus.codeSent
                        ? '验证并登录'
                        : '发送验证码',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
