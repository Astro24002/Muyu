import 'package:flutter/material.dart';

import '../theme/muyu_theme.dart';
import '../workspace/workspace_bootstrap_controller.dart';
import '../workspace/workspace_bootstrap_repository.dart';

class WorkspaceBootstrapScreen extends StatefulWidget {
  const WorkspaceBootstrapScreen({
    super.key,
    required this.state,
    this.onCreate,
    this.onBindPartner,
    this.onAcceptInvite,
    required this.onRetry,
  });

  final WorkspaceBootstrapState state;
  final Future<void> Function()? onCreate;
  final Future<void> Function(String phone)? onBindPartner;
  final Future<void> Function()? onAcceptInvite;
  final Future<void> Function() onRetry;

  @override
  State<WorkspaceBootstrapScreen> createState() =>
      _WorkspaceBootstrapScreenState();
}

class _WorkspaceBootstrapScreenState extends State<WorkspaceBootstrapScreen> {
  final _phone = TextEditingController();
  String? _validationError;
  bool _submitted = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _bindPartner() async {
    final callback = widget.onBindPartner;
    if (callback == null || _submitted) return;
    final raw = _phone.text.trim();
    try {
      final normalized = normalizePhone(raw);
      setState(() {
        _validationError = null;
        _submitted = true;
      });
      await callback(normalized);
    } on FormatException {
      setState(() => _validationError = '请输入有效的手机号');
    } finally {
      if (mounted) setState(() => _submitted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final content = switch (state.status) {
      WorkspaceBootstrapStatus.needsPartner ||
      WorkspaceBootstrapStatus.bindingPartner => _partnerContent(context),
      WorkspaceBootstrapStatus.waitingForPartner => _waitingContent(context),
      WorkspaceBootstrapStatus.invited ||
      WorkspaceBootstrapStatus.acceptingInvite => _invitedContent(context),
      WorkspaceBootstrapStatus.needsWorkspace ||
      WorkspaceBootstrapStatus.creatingWorkspace => _legacyContent(context),
      WorkspaceBootstrapStatus.failure ||
      WorkspaceBootstrapStatus.loading => _failureContent(context),
      WorkspaceBootstrapStatus.ready ||
      WorkspaceBootstrapStatus.readOnlyDevice => const SizedBox.shrink(),
    };
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(MuyuSpacing.xl),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _partnerContent(BuildContext context) {
    final submitting =
        _submitted ||
        widget.state.status == WorkspaceBootstrapStatus.bindingPartner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '绑定共同使用人',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MuyuSpacing.md),
        Text(
          widget.state.errorMessage ?? '填写另一位共同使用人的手机号，创建两人共享空间。',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MuyuSpacing.xl),
        TextField(
          key: const Key('partner-phone-input'),
          controller: _phone,
          enabled: !submitting,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _bindPartner(),
          decoration: InputDecoration(
            labelText: '共同使用人手机号',
            hintText: '请输入 11 位手机号',
            errorText: _validationError,
          ),
        ),
        const SizedBox(height: MuyuSpacing.lg),
        FilledButton(
          key: const Key('bind-partner-button'),
          onPressed: submitting ? null : _bindPartner,
          child: submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建共享空间'),
        ),
      ],
    );
  }

  Widget _waitingContent(BuildContext context) => _statusContent(
    title: '等待对方加入',
    message:
        widget.state.errorMessage ??
        '邀请已发送至 ${widget.state.payload?.invite?.phoneMasked ?? '对方手机号'}。对方接受后即可共同使用。',
    action: OutlinedButton.icon(
      key: const Key('bootstrap-refresh-button'),
      onPressed: widget.onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('重新加载'),
    ),
  );

  Widget _invitedContent(BuildContext context) {
    final accepting =
        widget.state.status == WorkspaceBootstrapStatus.acceptingInvite;
    return _statusContent(
      title: '收到共享空间邀请',
      message:
          widget.state.errorMessage ??
          '${widget.state.payload?.invite?.phoneMasked ?? '对方'} 邀请你加入共享空间。',
      action: FilledButton(
        key: const Key('accept-invite-button'),
        onPressed: accepting ? null : widget.onAcceptInvite,
        child: accepting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('接受邀请'),
      ),
    );
  }

  Widget _legacyContent(BuildContext context) {
    final creating =
        widget.state.status == WorkspaceBootstrapStatus.creatingWorkspace;
    final loading = widget.state.status == WorkspaceBootstrapStatus.loading;
    return _statusContent(
      title: '创建共享空间',
      message: widget.state.errorMessage ?? '先创建一个共享空间，然后开始协作。',
      action: FilledButton(
        onPressed: creating || loading ? null : widget.onCreate,
        child: creating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('创建共享空间'),
      ),
    );
  }

  Widget _failureContent(BuildContext context) => _statusContent(
    title: '共享空间',
    message: widget.state.errorMessage ?? '无法加载共享空间，请稍后重试',
    action: OutlinedButton.icon(
      key: const Key('bootstrap-retry-button'),
      onPressed: widget.onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('重试'),
    ),
  );

  Widget _statusContent({
    required String title,
    required String message,
    required Widget action,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: MuyuSpacing.md),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: MuyuSpacing.xl),
      action,
    ],
  );
}
