import 'dart:math';

import 'package:flutter/foundation.dart';

import 'life_repository.dart';
import '../models/workspace_snapshot.dart';

class LifeController extends ChangeNotifier {
  LifeController(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now,
      month = _monthOf((now ?? DateTime.now)());

  final LifeRepository repository;
  final DateTime Function() now;
  DateTime month;
  List<LedgerItem> entries = const [];
  LedgerSummary? summary;
  List<HabitItem> habits = const [];
  List<AnniversaryItem> anniversaries = const [];
  String habitOwner = 'mine';
  String? loadedLedgerMonthKey;
  String? loadedLedgerSummaryMonthKey;
  bool hasLoadedCheckins = false;
  bool loadingLedger = false;
  bool loadingCheckins = false;
  bool writing = false;
  String? ledgerError;
  String? checkinsError;
  bool _disposed = false;
  int _ledgerLoadGeneration = 0;

  String get monthKey =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

  Future<void> loadLedger() async {
    final generation = ++_ledgerLoadGeneration;
    final requestedMonth = monthKey;
    loadingLedger = true;
    ledgerError = null;
    _notify();
    try {
      final loadedSummary = await repository.ledgerSummary(requestedMonth);
      final loadedEntries = await repository.ledger(requestedMonth);
      if (_disposed || generation != _ledgerLoadGeneration) return;
      summary = loadedSummary;
      entries = loadedEntries;
      loadedLedgerMonthKey = requestedMonth;
      loadedLedgerSummaryMonthKey = requestedMonth;
    } catch (_) {
      if (generation == _ledgerLoadGeneration) {
        ledgerError = '记账刷新失败，请检查网络后重试';
      }
    } finally {
      if (generation == _ledgerLoadGeneration) {
        loadingLedger = false;
        _notify();
      }
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
      hasLoadedCheckins = true;
    } catch (_) {
      checkinsError = '打卡刷新失败，请检查网络后重试';
    } finally {
      loadingCheckins = false;
      _notify();
    }
  }

  /// Applies the authoritative life resources carried by workspace sync.
  ///
  /// Writes still use the life REST commands, while reads converge through the
  /// same snapshot/cursor stream as tasks. Older snapshots without these
  /// resources are left untouched for compatibility.
  void applyWorkspaceSnapshot(WorkspaceSnapshot? snapshot, {String? viewerId}) {
    if (_disposed || snapshot == null || !snapshot.hasLifeDomainContract) {
      return;
    }
    final monthEntries = snapshot.ledgerEntries
        .where(
          (entry) =>
              entry.date.year == month.year && entry.date.month == month.month,
        )
        .toList();
    final visibleHabits = snapshot.habits.where((habit) {
      if (habitOwner == 'all' || viewerId == null) return true;
      return habitOwner == 'mine'
          ? habit.ownerId == viewerId
          : habit.ownerId != viewerId;
    }).toList();
    final changed =
        !_sameLedger(entries, monthEntries) ||
        !_sameHabits(habits, visibleHabits) ||
        !_sameAnniversaries(anniversaries, snapshot.anniversaries);
    final ledgerMonthChanged = loadedLedgerMonthKey != monthKey;
    final firstLifeSnapshot = !hasLoadedCheckins;
    hasLoadedCheckins = true;
    if (!changed && !ledgerMonthChanged && !firstLifeSnapshot) return;
    if (!_sameLedger(entries, monthEntries)) {
      summary = null;
      loadedLedgerSummaryMonthKey = null;
    }
    entries = monthEntries;
    loadedLedgerMonthKey = monthKey;
    habits = visibleHabits;
    anniversaries = List<AnniversaryItem>.from(snapshot.anniversaries);
    hasLoadedCheckins = true;
    _notify();
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

  static DateTime _monthOf(DateTime value) => DateTime(value.year, value.month);

  static bool _sameLedger(List<LedgerItem> left, List<LedgerItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].version != right[index].version ||
          left[index].deletedAt != right[index].deletedAt) {
        return false;
      }
    }
    return true;
  }

  static bool _sameHabits(List<HabitItem> left, List<HabitItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].version != right[index].version ||
          left[index].checkedIn != right[index].checkedIn ||
          left[index].status != right[index].status ||
          !_sameDays(left[index].recentDays, right[index].recentDays) ||
          !_sameDays(
            left[index].recentCheckinDays,
            right[index].recentCheckinDays,
          )) {
        return false;
      }
    }
    return true;
  }

  static bool _sameAnniversaries(
    List<AnniversaryItem> left,
    List<AnniversaryItem> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].version != right[index].version ||
          left[index].nextOccurrence != right[index].nextOccurrence) {
        return false;
      }
    }
    return true;
  }

  static bool _sameDays(List<DateTime> left, List<DateTime> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].year != right[index].year ||
          left[index].month != right[index].month ||
          left[index].day != right[index].day) {
        return false;
      }
    }
    return true;
  }
}
