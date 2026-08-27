import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../platform/device_signing_key.dart';
import '../workspace/device_authorization_repository.dart';

class WebQrScannerScreen extends StatefulWidget {
  const WebQrScannerScreen({
    super.key,
    required this.repository,
    required this.signingKey,
  });

  final DeviceAuthorizationRepository repository;
  final DeviceSigningKey signingKey;

  @override
  State<WebQrScannerScreen> createState() => _WebQrScannerScreenState();
}

class _WebQrScannerScreenState extends State<WebQrScannerScreen> {
  final _scanner = MobileScannerController();
  DeviceAuthorizationRequest? _request;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _scan(BarcodeCapture capture) async {
    if (_busy || _request != null) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await widget.repository.scanWebQr(value);
      await _scanner.stop();
      if (mounted) {
        setState(() {
          _request = request;
          _busy = false;
        });
      }
    } on DeviceAuthorizationFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _approve() async {
    final request = _request;
    if (request == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.approveWebLogin(
        request,
        signingKey: widget.signingKey,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DeviceAuthorizationFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码登录 Web')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: _request == null
          ? Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MobileScanner(controller: _scanner, onDetect: _scan),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('请扫描 Web 页面上的登录二维码'),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '请核对 Web 来源和安全码',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SelectableText(_request!.origin ?? '未知来源'),
                const SizedBox(height: 12),
                SelectableText(
                  _request!.safetyCode ?? '安全码不可用，请重新扫码',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text('有效期至 ${_request!.expiresAt.toLocal()}'),
                const Spacer(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(_busy ? '处理中...' : '批准登录'),
                ),
              ],
            ),
    ),
  );
}
