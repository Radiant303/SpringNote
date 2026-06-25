import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/security_scoped_directory_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'method channel access reports missing macOS plugin as failure',
    () async {
      const access = MethodChannelSecurityScopedDirectoryAccess(
        MethodChannel('spring_note/test_missing_security_scoped_directories'),
      );

      expect(
        await access.saveBookmark('/tmp/spring-note'),
        Platform.isMacOS ? isFalse : isTrue,
      );
      expect(
        await access.startAccessing('/tmp/spring-note'),
        Platform.isMacOS ? isFalse : isTrue,
      );
    },
  );
}
