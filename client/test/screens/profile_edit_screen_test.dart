import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/user.dart';
import 'package:muyu_client/profile/profile_repository.dart';
import 'package:muyu_client/screens/profile_edit_screen.dart';

class RecordingProfileRepository implements ProfileRepository {
  String? submittedName;

  @override
  Future<User> updateDisplayName(String? displayName) async {
    submittedName = displayName;
    return User(
      id: 'user-1',
      phone: '+8613800138000',
      nickname: displayName ?? '',
      avatarKey: '',
      role: 'member',
    );
  }
}

void main() {
  testWidgets('profile edit submits the entered display name', (tester) async {
    final repository = RecordingProfileRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditScreen(
          repository: repository,
          initialDisplayName: 'Old name',
        ),
      ),
    );

    expect(find.byKey(const Key('profile-edit-app-bar')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profile-edit-name')),
      'New name',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.submittedName, 'New name');
  });
}
