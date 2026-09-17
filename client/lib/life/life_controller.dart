import 'dart:math';

import 'package:flutter/foundation.dart';

import 'life_repository.dart';

class LifeController extends ChangeNotifier {
  LifeController(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final LifeRepository repository;
  final DateTime Function() now;
  List<LedgerItem> entries = const [];
  LedgerSummary? summary;
  List<HabitItem> habits = const [];
  List<AnniversaryItem> anniversaries = const [];
  String habitOwner = 'mine';
  bool loadingLedger = false;
  bool loadingCheckins = false;
  bool writing = false;
  String? ledgerError;
  String? checkinsError;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _disposed = false;

  String get monthKey =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

  Future<void> loadLedger() async {
    loadingLedger = true;
    ledgerError = null;
    _notify();
    try {
      final loadedSummary = await repository.ledgerSummary(monthKey);
      final loadedEntries = await repository.ledger(monthKey);
      if (_disposed) return;
      summary = loadedSummary;
      entries = loadedEntries;
    } catch (_) {
      ledgerError = '记账刷新失败，请检查网络后重试';
    } finally {
      loadingLedger = false;
      _notify();
    }
  }

  Future<void> changeMonth(int offset) async {
    month = DateTime(month.year, month.month + offset);
    await loadLedger();
  }

  Future<void> loadCheckins() async {
    loadingCheckins = true;
    checkinsError = null;
    _notify();
    try {
      final loadedHabits = await repository.habits(habitOwner);
      final loadedAnniversaries = await repository.anniversaries();
      if (_disposed) return;
      habits = loadedHabits;
      anniversaries = loadedAnniversaries;
    } catch (_) {
      checkinsError = '打卡刷新失败，请检查网络后重试';
    } finally {
      loadingCheckins = false;
      _notify();
    }
  }

  Future<void> changeHabitOwner(String value) async {
    habitOwner = value;
    await loadCheckins();
  }

  Future<bool> writeLedger(Future<void> Function(String requestId) action) =>
      _write(action, loadLedger, ledger: true);

  Future<bool> writeCheckins(Future<void> Function(String requestId) action) =>
      _write(action, loadCheckins, ledger: false);

  Future<bool> _write(
    Future<void> Function(String requestId) action,
    Future<void> Function() refresh, {
    required bool ledger,
  }) async {
    if (writing) return false;
    writing = true;
    _notify();
    final requestId = _requestId();
    try {
      await action(requestId);
      await refresh();
      return true;
    } catch (_) {
      if (ledger) {
        ledgerError = '操作失败，内容已保留，请检查网络后重试';
      } else {
        checkinsError = '操作失败，内容已保留，请检查网络后重试';
      }
      return false;
    } finally {
      writing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
