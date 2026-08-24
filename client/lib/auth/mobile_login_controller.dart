import 'package:flutter/foundation.dart';

import 'mobile_auth_repository.dart';
import 'mobile_session_store.dart';

enum MobileLoginStatus {
  signedOut,
  sendingCode,
  codeSent,
  verifying,
  signedIn,
  failure,
}

class MobileLoginController extends ChangeNotifier {
  MobileLoginController(
    this._repository,
    this._store, {
    required this._publicKey,
  });

  final MobileAuthRepository _repository;
  final MobileSessionStore _store;
  final Future<String> Function() _publicKey;

  MobileLoginStatus status = MobileLoginStatus.signedOut;
  String phone = '';
  String? errorMessage;
  MobileSession? currentSession;

  Future<void> requestCode(String value) async {
    phone = value.trim();
    status = MobileLoginStatus.sendingCode;
    errorMessage = null;
    notifyListeners();
    try {
      await _repository.sendSms(phone);
      status = MobileLoginStatus.codeSent;
    } on MobileAuthFailure catch (error) {
      status = MobileLoginStatus.failure;
      errorMessage = error.message;
    }
    notifyListeners();
  }

  Future<void> verifyCode(String code) async {
    status = MobileLoginStatus.verifying;
    errorMessage = null;
    notifyListeners();
    try {
      final session = await _repository.verifySms(
        phone: phone,
        code: code,
        publicKey: await _publicKey(),
      );
      await _store.write(session);
      currentSession = session;
      status = MobileLoginStatus.signedIn;
    } on MobileAuthFailure catch (error) {
      status = MobileLoginStatus.failure;
      errorMessage = error.message;
    }
    notifyListeners();
  }

  Future<void> restore() async {
    currentSession = await _store.read();
    if (currentSession == null) {
      status = MobileLoginStatus.signedOut;
    } else {
      try {
        currentSession = await _repository.refresh();
        await _store.write(currentSession!);
        status = MobileLoginStatus.signedIn;
      } on MobileAuthFailure catch (error) {
        await _store.clear();
        currentSession = null;
        status = MobileLoginStatus.failure;
        errorMessage = error.message;
      }
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _repository.logout();
    currentSession = null;
    status = MobileLoginStatus.signedOut;
    notifyListeners();
  }
}
