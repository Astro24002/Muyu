import 'package:flutter/widgets.dart';

/// Waits until the overlay that just returned a result has been removed from
/// the widget tree before notifying a long-lived workspace listener.
///
/// Dialog routes complete their futures when they are popped, before the
/// reverse transition has finished. Updating an AnimatedBuilder-backed page
/// in that gap can leave an inherited element with active dependents.
Future<void> waitForRouteDismissal() async {
  // Material dialog routes currently use a 150-200 ms reverse transition.
  // Keep a small margin so this remains safe across Android animation scales.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await WidgetsBinding.instance.endOfFrame;
}
