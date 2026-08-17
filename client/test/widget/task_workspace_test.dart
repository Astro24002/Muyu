import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/app.dart';
import 'package:muyu_client/auth/auth_repository.dart';
import 'package:muyu_client/auth/session_controller.dart';
import 'package:muyu_client/auth/token_store.dart';
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
}
