import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_cache.dart';

void main() {
  test(
    'legacy snapshot namespace is not read as the current snapshot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final legacySnapshot = WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 7,
        tasks: const [],
      );
      await preferences.setString(
        'muyu.workspace.snapshot.workspace-1',
        jsonEncode(legacySnapshot.toJson()),
      );

      final current = await SharedPreferencesWorkspaceCache(preferences)
          .read('workspace-1');

      expect(current, isNull);
    },
  );

  test('writing a current snapshot uses the versioned namespace', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final snapshot = WorkspaceSnapshot(
      workspaceId: 'workspace-1',
      cursor: 8,
      tasks: const [],
    );
    final cache = SharedPreferencesWorkspaceCache(preferences);

    await cache.write(snapshot);

    expect(
      preferences.getString('muyu.workspace.snapshot.workspace-1'),
      isNull,
    );
    expect(
      preferences.getString('muyu.workspace.snapshot.v2.workspace-1'),
      isNotNull,
    );
    expect((await cache.read('workspace-1'))?.cursor, 8);
  });
}
