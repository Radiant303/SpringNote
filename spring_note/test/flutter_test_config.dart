import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings
      .withTrackedAll()
      // Image decoding and math font registration use process-lifetime global
      // services, so their bookkeeping intentionally remains alive at teardown.
      .withIgnored(
        classes: ['ImageStreamCompleterHandle', '_LiveImage', 'FontsLoaded'],
      )
      .withCreationStackTrace();
  await testMain();
}
