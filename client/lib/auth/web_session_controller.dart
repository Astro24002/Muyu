import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import 'web_login_repository.dart';

enum WebSessionStatus {
  signedOut,
  waitingForApproval,
  exchanging,
  signedIn,
  expired,
  failure,
}

class WebSessionController extends ChangeNotifier {
  WebSessionController(this._repository, {Random? random})
    : _random = random ?? Random.secure();

  final WebLoginApi _repository;
  final Random _random;
  WebSessionStatus status = WebSessionStatus.signedOut;
  WebLoginChallenge? challenge;
  String? errorMessage;
  String? _browserProof;
  bool _exchanged = false;

  Future<void> start() async {
    _browserProof = List<int>.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    _exchanged = false;
    errorMessage = null;
    try {
      challenge = await _repository.createChallenge(_browserProof!);
      status = WebSessionStatus.waitingForApproval;
    } catch (error) {
      _discardProof();
      status = WebSessionStatus.failure;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> poll() async {
    final current = challenge;
    if (current == null || status != WebSessionStatus.waitingForApproval) {
      return;
    }
    if (!current.expiresAt.isAfter(DateTime.now())) {
      expire();
      return;
    }
    try {
      final result = await _repository.status(current.challengeId);
      if (result == 'APPROVED' && !_exchanged) {
        _exchanged = true;
        status = WebSessionStatus.exchanging;
        await _repository.exchange(current.challengeId, _browserProof!);
        _discardProof();
        status = WebSessionStatus.signedIn;
      } else if (result == 'EXPIRED' || result == 'REVOKED') {
        expire();
      }
    } catch (error) {
      if (error is ApiException &&
          (error.statusCode == 401 || error.statusCode == 410)) {
        expire();
        return;
      }
      status = WebSessionStatus.failure;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  void expire() {
    _discardProof();
    status = WebSessionStatus.expired;
    notifyListeners();
  }

  void logout() {
    _discardProof();
    challenge = null;
    status = WebSessionStatus.signedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    _discardProof();
    super.dispose();
  }

  void _discardProof() => _browserProof = null;
}
