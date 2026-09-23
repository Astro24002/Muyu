import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/life/life_controller.dart';
import 'package:muyu_client/life/life_repository.dart';
import 'package:muyu_client/screens/checkins_screen.dart';
import 'package:muyu_client/screens/ledger_screen.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

class _LifeFixture implements LifeRepository {
  @override
  Future<LedgerSummary> ledgerSummary(String month) async =>
      const LedgerSummary(
        expenseMinor: 45200,
        incomeMinor: 200000,
        balanceMinor: 154800,
        categories: [
          {'category': '婚礼', 'amount_minor': 32000},
          {'category': '餐饮', 'amount_minor': 13200},
        ],
        payerTotals: [
          {'display_name': 'Bokang', 'amount_minor': 38400},
          {'display_name': '溪岸', 'amount_minor': 6800},
        ],
      );

  @override
  Future<List<LedgerItem>> ledger(String month) async => [
    LedgerItem(
      id: 'expense',
      title: '两个人的晚餐',
      category: '餐饮',
      type: 'EXPENSE',
      amountMinor: 12800,
      date: DateTime(2026, 9, 20),
      payerId: 'me',
      payerName: 'Bokang',
      version: 1,
    ),
    LedgerItem(
      id: 'income',
      title: '共同收入',
      category: '收入',
      type: 'INCOME',
      amountMinor: 200000,
      date: DateTime(2026, 9, 19),
      payerId: 'me',
      payerName: 'Bokang',
      version: 1,
    ),
  ];

  @override
  Future<List<HabitItem>> habits(String owner) async => [
    HabitItem(
      id: 'habit-me',
      ownerId: 'me',
      title: '读书 20 分钟',
      frequency: 'DAILY',
      status: 'ACTIVE',
      startDate: DateTime(2026, 9, 1),
      checkedIn: false,
      version: 1,
      periodKey: '2026-09-20',
      recentDays: [for (var day = 18; day <= 24; day++) DateTime(2026, 9, day)],
      recentCheckinDays: [DateTime(2026, 9, 18), DateTime(2026, 9, 22)],
    ),
    if (owner == 'all' || owner == 'other')
      HabitItem(
        id: 'habit-other',
        ownerId: 'other',
        title: '整理小角落',
        frequency: 'WEEKLY',
        status: 'ACTIVE',
        startDate: DateTime(2026, 9, 1),
        checkedIn: true,
        version: 1,
        periodKey: '2026-W38',
      ),
  ];

  @override
  Future<List<AnniversaryItem>> anniversaries() async => [
    AnniversaryItem(
      id: 'anniversary',
      title: '相识纪念日',
      kind: 'ANNIVERSARY',
      anchorDate: DateTime(2024, 9, 23),
      nextOccurrence: DateTime(2026, 9, 23),
      daysUntil: 3,
      prepareDays: 7,
      version: 1,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 393.0]) {
    testWidgets(
      'ledger preserves summary when detail filter changes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final controller = LifeController(_LifeFixture());
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: muyuLightTheme(),
            home: Scaffold(
              body: LedgerScreen(
                controller: controller,
                members: const [],
                viewerId: 'me',
                canWrite: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('¥ 452.00'), findsOneWidget);
        expect(find.text('婚礼 71%'), findsOneWidget);
        expect(find.byKey(const Key('ledger-create-fab')), findsOneWidget);
        await tester.tap(find.text('收入').last);
        await tester.pumpAndSettle();
        expect(find.text('¥ 452.00'), findsOneWidget);
        expect(find.byKey(const Key('ledger-entry-expense')), findsNothing);
        expect(find.byKey(const Key('ledger-entry-income')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'checkins uses period facts and keeps other habit read-only at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final controller = LifeController(_LifeFixture());
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: muyuLightTheme(),
            home: Scaffold(
              body: CheckinsScreen(
                controller: controller,
                viewerId: 'me',
                canWrite: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('本期已完成 0 / 1 项'), findsOneWidget);
        expect(find.text('打卡'), findsOneWidget);
        expect(find.byKey(const Key('habit-history-habit-me')), findsOneWidget);
        expect(find.bySemanticsLabel('2026-09-22 已打卡'), findsOneWidget);
        expect(find.bySemanticsLabel('2026-09-23 没有打卡记录'), findsOneWidget);
        await tester.tap(find.text('全部').last);
        await tester.pumpAndSettle();
        expect(find.text('本期已完成 1 / 2 项'), findsOneWidget);
        expect(find.text('打卡'), findsOneWidget);
        await tester.tap(find.text('纪念日').last);
        await tester.pumpAndSettle();
        expect(find.text('相识纪念日'), findsWidgets);
        expect(find.text('还有 3 天'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
