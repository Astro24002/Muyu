import 'package:flutter/material.dart';

import '../auth/mobile_session_store.dart';
import '../models/user.dart';
import '../profile/profile_repository.dart';
import '../theme/muyu_theme.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.repository,
    required this.initialDisplayName,
    this.sessionStore,
    this.onSaved,
  });

  final ProfileRepository repository;
  final String initialDisplayName;
  final MobileSessionStore? sessionStore;
  final ValueChanged<User>? onSaved;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDisplayName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      key: const Key('profile-edit-app-bar'),
      title: Text('编辑个人资料', style: Theme.of(context).textTheme.titleLarge),
    ),
    body: ListView(
      padding: const EdgeInsets.all(MuyuSpacing.lg),
      children: [
        TextField(
          key: const Key('profile-edit-name'),
          controller: _controller,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: '用户名称'),
          onSubmitted: (_) => _save(),
        ),
        if (_error != null) ...[
          const SizedBox(height: MuyuSpacing.sm),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: MuyuSpacing.lg),
        FilledButton.icon(
          key: const Key('profile-edit-submit'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.repository.updateDisplayName(
        _controller.text.trim(),
      );
      if (widget.sessionStore != null) {
        await widget.sessionStore!.replaceUser(user);
      }
      widget.onSaved?.call(user);
      if (mounted) Navigator.of(context).pop(user);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请稍后重试';
      });
    }
  }
}
