import 'package:flutter/foundation.dart';

import '../models/user.dart';
import 'auth_repository.dart';
import 'token_store.dart';

enum SessionStatus { signedOut, loading, signedIn, failure }

class SessionController extends ChangeNotifier {
  SessionController(this._repository, this._tokenStore);

  final AuthRepository _repository;
  final TokenStore _tokenStore;

  SessionStatus status = SessionStatus.signedOut;
  User? currentUser;
  List<User> users = const [];
  String? errorMessage;

  Future<void> login(String phone, String password) async {
    _setLoading();
    try {
      final result = await _repository.login(phone, password);
      await _saveSession(result);
      status = SessionStatus.signedIn;
    } on AuthFailure catch (error) {
      status = SessionStatus.failure;
      errorMessage = error.message;
    } finally {
      notifyListeners();
    }
  }

  Future<void> restore() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) {
      status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    _setLoading();
    try {
      final result = await _repository.refresh();
      await _saveSession(result);
      currentUser = await _repository.me();
      status = SessionStatus.signedIn;
    } on AuthFailure {
      await _clearSession();
    } finally {
      notifyListeners();
    }
  }

  Future<void> loadUsers() async {
    try {
      users = await _repository.users();
      errorMessage = null;
    } on AuthFailure catch (error) {
      errorMessage = error.message;
    }
    notifyListeners();
  }

  Future<bool> updateProfile({
    required String nickname,
    required String role,
  }) async {
    try {
      currentUser = await _repository.updateProfile(
        nickname: nickname,
        role: role,
      );
      await loadUsers();
      return true;
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _repository.logout();
    } finally {
      await _clearSession();
      notifyListeners();
    }
  }

  Future<void> _saveSession(AuthSession session) async {
    await _tokenStore.write(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    currentUser = session.user;
    errorMessage = null;
  }

  Future<void> _clearSession() async {
    await _tokenStore.clear();
    currentUser = null;
    users = const [];
    errorMessage = null;
    status = SessionStatus.signedOut;
  }

  void _setLoading() {
    status = SessionStatus.loading;
    errorMessage = null;
    notifyListeners();
  }
}
