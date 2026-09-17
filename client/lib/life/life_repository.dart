import '../core/api_client.dart';

class LedgerItem {
  const LedgerItem({
    required this.id,
    required this.title,
    required this.category,
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.payerId,
    required this.payerName,
    required this.version,
    this.note,
  });

  final String id;
  final String title;
  final String category;
  final String type;
  final int amountMinor;
  final DateTime date;
  final String payerId;
  final String payerName;
  final int version;
  final String? note;

  factory LedgerItem.fromJson(Map<String, dynamic> json) => LedgerItem(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    type: json['type'] as String,
    amountMinor: json['amount_minor'] as int,
    date: DateTime.parse(json['date'] as String),
    payerId: json['payer_or_payee_id'] as String,
    payerName: json['payer_or_payee_name'] as String? ?? '',
    version: json['version'] as int,
    note: json['note'] as String?,
  );

  String get formattedAmount => (amountMinor / 100).toStringAsFixed(2);
}

class LedgerSummary {
  const LedgerSummary({
    required this.expenseMinor,
    required this.incomeMinor,
    required this.balanceMinor,
    required this.categories,
    required this.payerTotals,
  });
  final int expenseMinor;
  final int incomeMinor;
  final int balanceMinor;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> payerTotals;

  factory LedgerSummary.fromJson(Map<String, dynamic> json) => LedgerSummary(
    expenseMinor: json['expense_minor'] as int,
    incomeMinor: json['income_minor'] as int,
    balanceMinor: json['balance_minor'] as int,
    categories: (json['categories'] as List<dynamic>? ?? const [])
        .map((item) => item as Map<String, dynamic>)
        .toList(),
    payerTotals: (json['payer_totals'] as List<dynamic>? ?? const [])
        .map((item) => item as Map<String, dynamic>)
        .toList(),
  );
}

class HabitItem {
  const HabitItem({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.frequency,
    required this.status,
    required this.startDate,
    required this.checkedIn,
    required this.version,
    required this.periodKey,
  });
  final String id;
  final String ownerId;
  final String title;
  final String frequency;
  final String status;
  final DateTime startDate;
  final bool checkedIn;
  final int version;
  final String periodKey;

  factory HabitItem.fromJson(Map<String, dynamic> json) => HabitItem(
    id: json['id'] as String,
    ownerId: json['owner_id'] as String,
    title: json['title'] as String,
    frequency: json['frequency'] as String,
    status: json['status'] as String,
    startDate: DateTime.parse(json['start_date'] as String),
    checkedIn: json['checked_in'] as bool? ?? false,
    version: json['version'] as int,
    periodKey: json['current_period_key'] as String? ?? '',
  );
}

class AnniversaryItem {
  const AnniversaryItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.anchorDate,
    required this.nextOccurrence,
    required this.daysUntil,
    required this.prepareDays,
    required this.version,
  });
  final String id;
  final String title;
  final String kind;
  final DateTime anchorDate;
  final DateTime nextOccurrence;
  final int daysUntil;
  final int prepareDays;
  final int version;

  factory AnniversaryItem.fromJson(Map<String, dynamic> json) =>
      AnniversaryItem(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        anchorDate: DateTime.parse(json['anchor_date'] as String),
        nextOccurrence: DateTime.parse(json['next_occurrence'] as String),
        daysUntil: json['days_until'] as int,
        prepareDays: json['prepare_days'] as int,
        version: json['version'] as int,
      );
}

abstract interface class LifeRepository {
  Future<List<LedgerItem>> ledger(String month);
  Future<LedgerSummary> ledgerSummary(String month);
  Future<LedgerItem> createLedger(Map<String, Object?> body);
  Future<LedgerItem> updateLedger(String id, Map<String, Object?> body);
  Future<void> deleteLedger(String id, int version, String requestId);
  Future<List<HabitItem>> habits(String owner);
  Future<HabitItem> createHabit(Map<String, Object?> body);
  Future<HabitItem> updateHabit(String id, Map<String, Object?> body);
  Future<HabitItem> habitAction(
    String id,
    String action,
    int version,
    String requestId,
  );
  Future<void> deleteHabit(String id, int version, String requestId);
  Future<List<AnniversaryItem>> anniversaries();
  Future<AnniversaryItem> createAnniversary(Map<String, Object?> body);
  Future<AnniversaryItem> updateAnniversary(
    String id,
    Map<String, Object?> body,
  );
  Future<void> deleteAnniversary(String id, int version, String requestId);
  Future<String> prepareAnniversary(String id, String requestId);
}

class HttpLifeRepository implements LifeRepository {
  HttpLifeRepository(this.api);
  final ApiClient api;

  Future<Map<String, dynamic>> _object(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async =>
      (await api.request(method, path, body: body, authenticated: true))
          as Map<String, dynamic>;

  @override
  Future<List<LedgerItem>> ledger(String month) async {
    final result = await _object('GET', '/api/v1/ledger?month=$month');
    return (result['items'] as List<dynamic>)
        .map((item) => LedgerItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<LedgerSummary> ledgerSummary(String month) async =>
      LedgerSummary.fromJson(
        await _object('GET', '/api/v1/ledger/summary?month=$month'),
      );

  @override
  Future<LedgerItem> createLedger(Map<String, Object?> body) async =>
      LedgerItem.fromJson(await _object('POST', '/api/v1/ledger', body: body));

  @override
  Future<LedgerItem> updateLedger(String id, Map<String, Object?> body) async =>
      LedgerItem.fromJson(
        await _object('PATCH', '/api/v1/ledger/$id', body: body),
      );

  @override
  Future<void> deleteLedger(String id, int version, String requestId) async {
    await _object(
      'DELETE',
      '/api/v1/ledger/$id',
      body: {
        'request_id': requestId,
        'expected_version': version,
        'confirm': true,
      },
    );
  }

  @override
  Future<List<HabitItem>> habits(String owner) async {
    final result = await _object('GET', '/api/v1/habits?owner=$owner');
    return (result['items'] as List<dynamic>)
        .map((item) => HabitItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<HabitItem> createHabit(Map<String, Object?> body) async =>
      HabitItem.fromJson(await _object('POST', '/api/v1/habits', body: body));

  @override
  Future<HabitItem> updateHabit(String id, Map<String, Object?> body) async =>
      HabitItem.fromJson(
        await _object('PATCH', '/api/v1/habits/$id', body: body),
      );

  @override
  Future<HabitItem> habitAction(
    String id,
    String action,
    int version,
    String requestId,
  ) async {
    final result = await _object(
      'POST',
      '/api/v1/habits/$id/$action',
      body: {'request_id': requestId, 'expected_version': version},
    );
    return HabitItem.fromJson(
      result['habit'] is Map<String, dynamic>
          ? result['habit'] as Map<String, dynamic>
          : result,
    );
  }

  @override
  Future<void> deleteHabit(String id, int version, String requestId) async {
    await _object(
      'DELETE',
      '/api/v1/habits/$id',
      body: {
        'request_id': requestId,
        'expected_version': version,
        'confirm': true,
      },
    );
  }

  @override
  Future<List<AnniversaryItem>> anniversaries() async {
    final result = await _object('GET', '/api/v1/anniversaries');
    return (result['items'] as List<dynamic>)
        .map((item) => AnniversaryItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AnniversaryItem> createAnniversary(Map<String, Object?> body) async =>
      AnniversaryItem.fromJson(
        await _object('POST', '/api/v1/anniversaries', body: body),
      );

  @override
  Future<AnniversaryItem> updateAnniversary(
    String id,
    Map<String, Object?> body,
  ) async => AnniversaryItem.fromJson(
    await _object('PATCH', '/api/v1/anniversaries/$id', body: body),
  );

  @override
  Future<void> deleteAnniversary(
    String id,
    int version,
    String requestId,
  ) async {
    await _object(
      'DELETE',
      '/api/v1/anniversaries/$id',
      body: {
        'request_id': requestId,
        'expected_version': version,
        'confirm': true,
      },
    );
  }

  @override
  Future<String> prepareAnniversary(String id, String requestId) async {
    final result = await _object(
      'POST',
      '/api/v1/anniversaries/$id/prepare',
      body: {'request_id': requestId},
    );
    return (result['task'] as Map<String, dynamic>)['id'] as String;
  }
}
