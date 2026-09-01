import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace_snapshot.dart';

abstract interface class WorkspaceCache {
  Future<WorkspaceSnapshot?> read(String workspaceId);

  Future<void> write(WorkspaceSnapshot snapshot);

  Future<void> clear(String workspaceId);
}

class SharedPreferencesWorkspaceCache implements WorkspaceCache {
  SharedPreferencesWorkspaceCache(this._preferences);

  final SharedPreferences _preferences;

  String _key(String id) => 'muyu.workspace.snapshot.v2.$id';

  @override
  Future<WorkspaceSnapshot?> read(String workspaceId) async {
    final value = _preferences.getString(_key(workspaceId));
    if (value == null) return null;
    try {
      return WorkspaceSnapshot.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } on FormatException {
      await clear(workspaceId);
      return null;
    }
  }

  @override
  Future<void> write(WorkspaceSnapshot snapshot) async {
    await _preferences.setString(
      _key(snapshot.workspaceId),
      jsonEncode(snapshot.toJson()),
    );
  }

  @override
  Future<void> clear(String workspaceId) =>
      _preferences.remove(_key(workspaceId));
}
