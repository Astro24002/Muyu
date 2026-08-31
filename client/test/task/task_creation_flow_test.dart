import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

void main() {
  test(
    'unavailable controller does not claim an offline task creation',
    () async {
      final controller = WorkspaceSyncController.unavailable();

      final created = await controller.create('Offline task', quadrant: 'Q1');

      expect(created, isNull);
      expect(controller.inFlightMutations, isEmpty);
    },
  );
}
