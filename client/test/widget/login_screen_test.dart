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
  FakeAuthRepository({this.loginError, this.usersError});

  final AuthFailure? loginError;
  final AuthFailure? usersError;

  static const currentUser = User(
    id: '1',
    phone: '15028180169',
    nickname: '用户一',
    avatarKey: 'avatar-1',
    role: '成员',
  );

  @override
  Future<AuthSession> login(String phone, String password) async {
    if (loginError != null) throw loginError!;
    return const AuthSession(
      user: currentUser,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<User> me() async => currentUser;

  @override
  Future<AuthSession> refresh() => throw UnimplementedError();

  @override
  Future<User> updateProfile({String? nickname, String? role}) async =>
      currentUser;

  @override
  Future<List<User>> users() async {
    if (usersError != null) throw usersError!;
    return const [currentUser];
  }
}

void main() {
  testWidgets('login form validates required fields', (tester) async {
    final controller = SessionController(
      FakeAuthRepository(),
      MemoryTokenStore(),
    );
    await tester.pumpWidget(
      MuyuApp(
        controller: controller,
        taskRepository: FakeTaskRepository(),
        initializeSession: false,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();

    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets('invalid credentials stay on login and show the API error', (
    tester,
  ) async {
    final controller = SessionController(
      FakeAuthRepository(loginError: const AuthFailure('手机号或密码错误')),
      MemoryTokenStore(),
    );
    await tester.pumpWidget(
      MuyuApp(
        controller: controller,
        taskRepository: FakeTaskRepository(),
        initializeSession: false,
      ),
    );

    await tester.enterText(find.byKey(const Key('phone-field')), '15028180169');
    await tester.enterText(find.byKey(const Key('password-field')), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('手机号或密码错误'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
  });

  testWidgets('successful login opens tasks and keeps account navigation', (
    tester,
  ) async {
    final controller = SessionController(
      FakeAuthRepository(),
      MemoryTokenStore(),
    );
    await tester.pumpWidget(
      MuyuApp(
        controller: controller,
        taskRepository: FakeTaskRepository(),
        initializeSession: false,
      ),
    );

    await tester.enterText(find.byKey(const Key('phone-field')), '15028180169');
    await tester.enterText(find.byKey(const Key('password-field')), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('暂无任务'), findsOneWidget);
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();
    expect(find.text('用户一'), findsWidgets);
    expect(find.byTooltip('退出登录'), findsOneWidget);
  });

  testWidgets('account user loading failure shows a retry action', (
    tester,
  ) async {
    final controller = SessionController(
      FakeAuthRepository(usersError: const AuthFailure('成员加载失败')),
      MemoryTokenStore(),
    );
    await tester.pumpWidget(
      MuyuApp(
        controller: controller,
        taskRepository: FakeTaskRepository(),
        initializeSession: false,
      ),
    );
    await tester.enterText(find.byKey(const Key('phone-field')), '15028180169');
    await tester.enterText(find.byKey(const Key('password-field')), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();

    expect(find.text('成员加载失败'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
