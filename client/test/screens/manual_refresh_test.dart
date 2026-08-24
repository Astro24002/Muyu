import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/sync/workspace_sync_controller.dart';

void main() {
  test(
    'offline mutation is rejected and does not create a queue entry',
    () async {
      final controller = WorkspaceSyncController.unavailable();

      expect(await controller.canMutate, isFalse);
      expect(controller.inFlightMutations, isEmpty);
    },
  );
}
