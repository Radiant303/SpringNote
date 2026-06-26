import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/clipboard_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('spring_note/test_clipboard_image');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('read png image returns bytes from method channel', () async {
    final expectedBytes = Uint8List.fromList([1, 2, 3]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'readPngImage');
          return expectedBytes;
        });

    final bytes = await const ClipboardImageService(channel).readPngImage();

    expect(bytes, expectedBytes);
  });

  test('read png image ignores empty channel result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => Uint8List(0));

    final bytes = await const ClipboardImageService(channel).readPngImage();

    expect(bytes, isNull);
  });

  test('read png image ignores platform channel failures', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'clipboard-error');
        });

    final bytes = await const ClipboardImageService(channel).readPngImage();

    expect(bytes, isNull);
  });

  test('read png image ignores missing platform plugin', () async {
    final bytes = await const ClipboardImageService(channel).readPngImage();

    expect(bytes, isNull);
  });
}
