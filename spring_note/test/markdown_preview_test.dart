import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/markdown_local_image_io.dart';
import 'package:spring_note/features/notes/markdown_preview.dart';

void main() {
  late Directory noteDirectory;

  setUp(() async {
    noteDirectory = await Directory.systemTemp.createTemp(
      'spring_note_markdown_preview_',
    );
  });

  tearDown(() async {
    if (await noteDirectory.exists()) {
      await noteDirectory.delete(recursive: true);
    }
  });

  testWidgets('markdown preview renders strong emphasis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: MarkdownPreview(markdown: '这里要强调 **SQL 注入** 风险。'),
        ),
      ),
    );

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainText = richTexts
        .map((richText) => richText.text.toPlainText())
        .join('\n');

    expect(plainText, contains('SQL 注入'));
    expect(plainText, isNot(contains('**SQL 注入**')));
    expect(_hasBoldText(richTexts, 'SQL 注入'), isTrue);
  });

  test(
    'markdown local image uses file provider for file uri inside note directory',
    () {
      final imageFile = File(
        _joinPath(noteDirectory.path, 'images/screenshot.png'),
      );
      final imageUri = imageFile.uri.toString();

      final image = buildMarkdownLocalImage(
        url: imageUri,
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isA<Image>());
      expect((image as Image).image, isA<FileImage>());
    },
  );

  test(
    'markdown local image uses file provider for relative images inside note directory',
    () {
      final image = buildMarkdownLocalImage(
        url: 'images/screenshot.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isA<Image>());
      expect((image as Image).image, isA<FileImage>());
    },
  );

  test(
    'markdown local image allows shared notes image directory references',
    () async {
      final notesRoot = Directory(_joinPath(noteDirectory.path, 'notes'));
      final dailyDirectory = Directory(_joinPath(notesRoot.path, 'daily'));
      final imageFile = File(
        _joinPath(notesRoot.path, 'images/shared screenshot.png'),
      );
      await dailyDirectory.create(recursive: true);
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: '../images/shared%20screenshot.png',
        baseDirectoryPath: dailyDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isA<Image>());
      final provider = (image as Image).image;
      expect(provider, isA<FileImage>());
      expect(
        (provider as FileImage).file.path,
        File(
          _joinPath(dailyDirectory.path, '../images/shared screenshot.png'),
        ).path,
      );
    },
  );

  test(
    'markdown local image accepts readable non-ascii relative image paths',
    () async {
      final imageFile = File(
        _joinPath(noteDirectory.path, 'images/【哲风壁纸】庭院雨景.png'),
      );
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: 'images/【哲风壁纸】庭院雨景.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isA<Image>());
      final provider = (image as Image).image;
      expect(provider, isA<FileImage>());
      expect((provider as FileImage).file.path, imageFile.path);
    },
  );

  test('markdown local image decodes escaped relative image paths', () async {
    final imageFile = File(
      _joinPath(noteDirectory.path, 'images/screenshot #1.png'),
    );
    await imageFile.parent.create(recursive: true);
    await imageFile.writeAsBytes(_pngBytes);

    final image = buildMarkdownLocalImage(
      url: 'images/screenshot%20%231.png',
      baseDirectoryPath: noteDirectory.path,
      width: null,
      height: null,
      fit: BoxFit.contain,
      errorBuilder: _imageErrorBuilder,
    );

    expect(image, isA<Image>());
    final provider = (image as Image).image;
    expect(provider, isA<FileImage>());
    expect((provider as FileImage).file.path, imageFile.path);
  });

  test(
    'markdown local image blocks file images outside note directory',
    () async {
      final outsideFile = File(
        _joinPath(noteDirectory.parent.path, 'outside-secret.png'),
      );
      await outsideFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: outsideFile.uri.toString(),
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  test(
    'markdown local image blocks absolute local paths without scheme',
    () async {
      final outsideFile = File(
        _joinPath(noteDirectory.parent.path, 'absolute-secret.png'),
      );
      await outsideFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: outsideFile.path,
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  test('markdown local image blocks Windows paths outside note directory', () {
    final image = buildMarkdownLocalImage(
      url: 'C:/Windows/secret.png',
      baseDirectoryPath: noteDirectory.path,
      width: null,
      height: null,
      fit: BoxFit.contain,
      errorBuilder: _imageErrorBuilder,
    );

    expect(image, isNull);
  });

  test(
    'markdown local image blocks relative traversal outside note directory',
    () async {
      final secretFile = File(
        _joinPath(noteDirectory.parent.path, 'secret.png'),
      );
      await secretFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: '../secret.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  test(
    'markdown local image blocks nested relative traversal outside note directory',
    () async {
      final secretFile = File(
        _joinPath(noteDirectory.parent.path, 'secret.png'),
      );
      await secretFile.writeAsBytes(_pngBytes);

      final image = buildMarkdownLocalImage(
        url: 'images/../../secret.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  test(
    'markdown local image blocks symlink images outside note directory',
    () async {
      if (Platform.isWindows) {
        return;
      }

      final outsideFile = File(
        _joinPath(noteDirectory.parent.path, 'linked-secret.png'),
      );
      await outsideFile.writeAsBytes(_pngBytes);
      final link = Link(_joinPath(noteDirectory.path, 'images/linked.png'));
      await link.parent.create(recursive: true);
      await link.create(outsideFile.path);

      final image = buildMarkdownLocalImage(
        url: 'images/linked.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  test(
    'markdown local image blocks images under symlinked directories',
    () async {
      if (Platform.isWindows) {
        return;
      }

      final outsideDirectory = Directory(
        _joinPath(noteDirectory.parent.path, 'outside-images'),
      );
      await outsideDirectory.create();
      final outsideFile = File(_joinPath(outsideDirectory.path, 'secret.png'));
      await outsideFile.writeAsBytes(_pngBytes);
      final link = Link(_joinPath(noteDirectory.path, 'images/linked-dir'));
      await link.parent.create(recursive: true);
      await link.create(outsideDirectory.path);

      final image = buildMarkdownLocalImage(
        url: 'images/linked-dir/secret.png',
        baseDirectoryPath: noteDirectory.path,
        width: null,
        height: null,
        fit: BoxFit.contain,
        errorBuilder: _imageErrorBuilder,
      );

      expect(image, isNull);
    },
  );

  testWidgets('markdown preview keeps network images on network provider', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '![remote](https://example.com/image.png)');

    final image = tester.widget<Image>(find.byType(Image));

    expect(image.image, isA<NetworkImage>());
  });
}

Widget _imageErrorBuilder(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
) {
  return const SizedBox.shrink();
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

Future<void> _pumpPreview(
  WidgetTester tester,
  String markdown, {
  String? localImageBasePath,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MarkdownPreview(
          markdown: markdown,
          localImageBasePath: localImageBasePath,
        ),
      ),
    ),
  );
}

bool _hasBoldText(Iterable<RichText> richTexts, String text) {
  for (final richText in richTexts) {
    if (_spanHasBoldText(richText.text, text, null)) {
      return true;
    }
  }
  return false;
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

bool _spanHasBoldText(InlineSpan span, String text, TextStyle? inheritedStyle) {
  final style = inheritedStyle?.merge(span.style) ?? span.style;

  if (span is TextSpan) {
    if ((span.text ?? '').contains(text) &&
        style?.fontWeight == FontWeight.w700) {
      return true;
    }

    final children = span.children;
    if (children != null) {
      for (final child in children) {
        if (_spanHasBoldText(child, text, style)) {
          return true;
        }
      }
    }
  }

  return false;
}
