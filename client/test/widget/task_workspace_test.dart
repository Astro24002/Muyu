import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/app.dart';
import 'package:muyu_client/auth/auth_repository.dart';
import 'package:muyu_client/auth/session_controller.dart';
import 'package:muyu_client/auth/token_store.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/user.dart';

import '../support/fake_task_repository.dart';

class MemoryTokenStore implements TokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {}
}

class FakeAuthRepository implements AuthRepository {
  static const user = User(
    id: '1',
    phone: '15028180169',
    nickname: '用户一',
    avatarKey: 'avatar-1',
    role: '成员',
  );

  @override
  Future<AuthSession> login(String phone, String password) async =>
      const AuthSession(
        user: user,
        accessToken: 'access',
        refreshToken: 'refresh',
      );

  @override
  Future<void> logout() async {}

  @override
  Future<User> me() async => user;

  @override
  Future<AuthSession> refresh() => throw UnimplementedError();

  @override
  Future<User> updateProfile({String? nickname, String? role}) async => user;

  @override
  Future<List<User>> users() async => const [user];
}

Future<void> pumpSignedIn(WidgetTester tester, FakeTaskRepository tasks) async {
  final controller = SessionController(FakeAuthRepository(), MemoryTokenStore())
    ..status = SessionStatus.signedIn
    ..currentUser = FakeAuthRepository.user;
  await tester.pumpWidget(
    MuyuApp(
      controller: controller,
      taskRepository: tasks,
      initializeSession: false,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-in workspace opens tasks and creates a task', (
    tester,
  ) async {
    await pumpSignedIn(tester, FakeTaskRepository());

    expect(find.text('暂无任务'), findsOneWidget);
    await tester.tap(find.byTooltip('新建任务'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title-field')), '购买车票');
    await tester.tap(find.widgetWithText(FilledButton, '保存任务'));
    await tester.pumpAndSettle();

    expect(find.text('购买车票'), findsOneWidget);
  });

  testWidgets('task detail exposes valid status action', (tester) async {
    await pumpSignedIn(tester, FakeTaskRepository(values: [fakeTask('one')]));

    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '开始'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();

    expect(find.text('进行中'), findsOneWidget);
  });

  testWidgets('waiting task shows blocking facts and unblocks', (tester) async {
    await pumpSignedIn(
      tester,
      FakeTaskRepository(
        values: [
          fakeTask(
            'waiting',
            status: 'WAITING',
            blockedReason: '等待确认行程',
            blockedSince: DateTime.utc(2026, 8, 17),
            resumeHandlerId: '1',
            waitingForUserId: '1',
          ),
        ],
      ),
    );

    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();
    expect(find.text('等待确认行程'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '解除阻塞'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '解除阻塞'));
    await tester.pumpAndSettle();
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('等待确认行程'), findsNothing);
  });

  testWidgets('block dialog validates reason and submits', (tester) async {
    await pumpSignedIn(tester, FakeTaskRepository(values: [fakeTask('one')]));
    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '阻塞'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-block-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请输入阻塞原因'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-block-reason')),
      '等待确认行程',
    );
    await tester.tap(find.byKey(const Key('task-block-submit')));
    await tester.pumpAndSettle();
    expect(find.text('等待中'), findsOneWidget);
  });

  testWidgets('delay dialog requires OTHER note and updates summary', (
    tester,
  ) async {
    await pumpSignedIn(
      tester,
      FakeTaskRepository(
        values: [fakeTask('one', dueAt: DateTime.utc(2026, 9, 3))],
      ),
    );
    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '延期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-delay-reason')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-delay-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请填写补充说明'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-delay-note')),
      '需要重新协调时间',
    );
    await tester.tap(find.byKey(const Key('task-delay-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('延期 1 次'), findsOneWidget);
  });

  testWidgets('task detail renders immutable delay history', (tester) async {
    final record = TaskDelayRecord(
      id: 'delay-1',
      taskId: 'one',
      userId: '1',
      originalDueAt: DateTime.utc(2026, 9, 3),
      newDueAt: DateTime.utc(2026, 9, 4),
      delayedAt: DateTime.utc(2026, 9, 1),
      delayDurationMinutes: 1440,
      reason: 'NO_TIME',
      note: '当天没有时间',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await pumpSignedIn(
      tester,
      FakeTaskRepository(
        values: [
          fakeTask(
            'one',
            dueAt: DateTime.utc(2026, 9, 4),
            delayCount: 1,
            totalDelayMinutes: 1440,
          ),
        ],
        delayValues: [record],
      ),
    );

    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();
    expect(find.text('延期记录'), findsOneWidget);
    expect(find.text('没有时间'), findsOneWidget);
    expect(find.textContaining('1440 分钟'), findsWidgets);
  });

  testWidgets('failed block keeps dialog input', (tester) async {
    await pumpSignedIn(
      tester,
      FakeTaskRepository(values: [fakeTask('one')], actionFailure: '操作失败'),
    );
    await tester.tap(find.text('准备旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '阻塞'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-block-reason')), '等待材料');

    await tester.tap(find.byKey(const Key('task-block-submit')));
    await tester.pumpAndSettle();

    expect(find.text('操作失败'), findsOneWidget);
    expect(find.text('等待材料'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
