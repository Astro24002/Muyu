import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/life/life_controller.dart';
import 'package:muyu_client/life/life_repository.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';
import 'package:muyu_client/sync/workspace_sync_repository.dart';

Map<String, dynamic> lifeSnapshotJson({int cursor = 1}) => {
  'workspace_id': 'workspace-1',
  'workspace': {'id': 'workspace-1', 'name': 'Muyu', 'status': 'ACTIVE'},
  'viewer_user_id': 'user-1',
  'members': [],
  'tasks': [],
  'conflicts': [],
  'comments': [],
  'approval_requests': [],
  'classifications': [],
  'ledger_entries': [
    {
      'id': 'ledger-1',
      'workspace_id': 'workspace-1',
      'type': 'EXPENSE',
      'amount_minor': 1234,
      'amount': '12.34',
      'currency': 'CNY',
      'title': '早餐',
      'category': '餐饮',
      'payer_or_payee_id': 'user-1',
      'payer_or_payee_name': '我',
      'date': '2026-09-21',
      'note': null,
      'created_by': 'user-1',
      'updated_by': 'user-1',
      'version': 1,
      'deleted_at': null,
    },
  ],
  'habits': [
    {
      'id': 'habit-1',
      'workspace_id': 'workspace-1',
      'owner_id': 'user-1',
      'title': '阅读',
      'note': null,
      'frequency': 'DAILY',
      'start_date': '2026-09-01',
      'status': 'ACTIVE',
      'version': 1,
      'current_period_key': '2026-09-21',
      'checked_in': false,
      'current_checkin': null,
      'checkins': [],
      'deleted_at': null,
    },
  ],
  'habit_checkins': [],
  'anniversaries': [
    {
      'id': 'anniversary-1',
      'workspace_id': 'workspace-1',
      'title': '纪念日',
      'anchor_date': '2020-10-01',
      'kind': 'ANNIVERSARY',
      'prepare_days': 7,
      'note': null,
      'next_occurrence': '2026-10-01',
      'days_until': 10,
      'is_today': false,
      'version': 1,
      'deleted_at': null,
    },
  ],
  'cursor': cursor,
};

class LifeSyncFake implements WorkspaceSyncRepository {
  LifeSyncFake(this._snapshot, this._changes);

  final WorkspaceSnapshot _snapshot;
  final WorkspaceChanges _changes;

  @override
  Future<WorkspaceSnapshot> snapshot() async => _snapshot;

  @override
  Future<WorkspaceChanges> changes({required int afterCursor}) async =>
      _changes;

  @override
  Stream<WorkspaceChanged> openWorkspaceHints() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LifeControllerRepository implements LifeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('parses life resources in the authoritative workspace snapshot', () {
    final snapshot = WorkspaceSnapshot.fromJson(lifeSnapshotJson());

    expect(snapshot.ledgerEntries.single.title, '早餐');
    expect(snapshot.ledgerEntries.single.workspaceId, 'workspace-1');
    expect(snapshot.habits.single.title, '阅读');
    expect(snapshot.anniversaries.single.title, '纪念日');
    expect(snapshot.habitCheckins, isEmpty);
  });

  test(
    'applies a life resource change without replacing the task snapshot',
    () async {
      final initial = WorkspaceSnapshot.fromJson(lifeSnapshotJson());
      final changedLedger = {
        ...lifeSnapshotJson()['ledger_entries'][0] as Map<String, dynamic>,
        'title': '午餐',
        'version': 2,
      };
      final changes = WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 2,
        'changes': [
          {
            'cursor': 2,
            'resource_type': 'ledger_entry',
            'resource_id': 'ledger-1',
            'action': 'UPDATED',
            'operation_id': 'op-1',
            'resource': changedLedger,
          },
        ],
      });
      final controller = WorkspaceSyncController(
        LifeSyncFake(initial, changes),
      );

      await controller.refresh();
      await controller.pull();

      expect(controller.state.snapshot?.ledgerEntries.single.title, '午餐');
      expect(controller.state.cursor, 2);
    },
  );

  test(
    'applies a null life tombstone and removes the resource by id',
    () async {
      final initial = WorkspaceSnapshot.fromJson(lifeSnapshotJson());
      final changes = WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 2,
        'changes': [
          {
            'cursor': 2,
            'resource_type': 'ledger_entry',
            'resource_id': 'ledger-1',
            'action': 'DELETED',
            'operation_id': 'op-delete-1',
            'resource': null,
          },
        ],
      });
      final controller = WorkspaceSyncController(
        LifeSyncFake(initial, changes),
      );

      await controller.refresh();
      await controller.pull();

      expect(controller.state.snapshot?.ledgerEntries, isEmpty);
      expect(controller.state.cursor, 2);
    },
  );

  test(
    'projects an incremental check-in onto the habit consumed by the page',
    () async {
      final initial = WorkspaceSnapshot.fromJson(lifeSnapshotJson());
      final changes = WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 2,
        'changes': [
          {
            'cursor': 2,
            'resource_type': 'habit_checkin',
            'resource_id': 'checkin-1',
            'action': 'CREATED',
            'operation_id': 'op-checkin-1',
            'resource': {
              'id': 'checkin-1',
              'habit_id': 'habit-1',
              'workspace_id': 'workspace-1',
              'actor_id': 'user-1',
              'frequency_snapshot': 'DAILY',
              'period_key': '2026-09-21',
              'day': '2026-09-21',
              'occurred_at': '2026-09-21T08:00:00Z',
              'revoked_at': null,
            },
          },
        ],
      });
      final controller = WorkspaceSyncController(
        LifeSyncFake(initial, changes),
      );

      await controller.refresh();
      await controller.pull();

      final habit = controller.state.snapshot?.habits.single;
      expect(habit?.checkedIn, isTrue);
      expect(habit?.currentCheckin?.id, 'checkin-1');
    },
  );

  test(
    'life screens can consume the same snapshot resources by month and owner',
    () {
      final controller = LifeController(LifeControllerRepository())
        ..month = DateTime(2026, 9)
        ..habitOwner = 'mine';
      addTearDown(controller.dispose);

      controller.applyWorkspaceSnapshot(
        WorkspaceSnapshot.fromJson(lifeSnapshotJson()),
        viewerId: 'user-1',
      );

      expect(controller.entries.single.id, 'ledger-1');
      expect(controller.habits.single.id, 'habit-1');
      expect(controller.anniversaries.single.id, 'anniversary-1');
    },
  );
}
