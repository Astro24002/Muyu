import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../models/user.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final SessionController controller;
  final bool embedded;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _roleController;
  bool _saving = false;
  String? _saveMessage;

  @override
  void initState() {
    super.initState();
    final user = widget.controller.currentUser!;
    _nicknameController = TextEditingController(text: user.nickname);
    _roleController = TextEditingController(text: user.role);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.loadUsers(),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    final role = _roleController.text.trim();
    if (nickname.isEmpty || role.isEmpty) {
      setState(() => _saveMessage = '昵称和角色不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    final saved = await widget.controller.updateProfile(
      nickname: nickname,
      role: role,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveMessage = saved ? '资料已保存' : widget.controller.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.currentUser!;
    final content = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IdentityHeader(user: user),
                const SizedBox(height: 32),
                Text('个人资料', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      TextField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(labelText: '昵称'),
                      ),
                      TextField(
                        controller: _roleController,
                        decoration: const InputDecoration(labelText: '角色'),
                      ),
                    ];
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存'),
                    ),
                    if (_saveMessage != null) ...[
                      const SizedBox(width: 12),
                      Flexible(child: Text(_saveMessage!)),
                    ],
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Divider(),
                ),
                Text('成员', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (widget.controller.users.isEmpty &&
                    widget.controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(child: Text(widget.controller.errorMessage!)),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: widget.controller.loadUsers,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                else if (widget.controller.users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ...widget.controller.users.map(
                    (member) => _UserTile(user: member),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            tooltip: '退出登录',
            onPressed: widget.controller.logout,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: content,
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(radius: 28, child: Text(user.nickname.characters.first)),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.nickname, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(user.phone, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: CircleAvatar(child: Text(user.nickname.characters.first)),
      title: Text(user.nickname),
      subtitle: Text(user.phone),
      trailing: Text(user.role),
    ),
  );
}
