import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/core/widgets/spring_markdown.dart';
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

  testWidgets('markdown preview renders inline code subtly', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '这是 `syntax` 测试');

    final inlineCode = tester.widget<Container>(
      find.byKey(const ValueKey('markdown-inline-code')),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('markdown-inline-code')),
        matching: find.text('syntax'),
      ),
    );
    final decoration = inlineCode.decoration as BoxDecoration;
    final border = decoration.border as Border;

    expect(text.style?.fontWeight, FontWeight.w400);
    expect(text.style?.fontSize, closeTo(12.6, 0.001));
    expect(text.style?.fontFamily, 'monospace');
    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(border.top.width, 1);
    expect(inlineCode.padding, const EdgeInsets.symmetric(horizontal: 2));
  });

  testWidgets('markdown preview keeps bold nesting for inline code', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '这是 **`语法`** 测试');

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('markdown-inline-code')),
        matching: find.text('语法'),
      ),
    );

    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.style?.fontSize, closeTo(12.6, 0.001));
    expect(text.style?.fontFamily, 'monospace');
    expect(text.style?.color, _bodyTextColor(tester));
  });

  testWidgets('markdown preview renders task checkbox like Typora', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '- [x] 完成任务\n- 普通列表');

    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.byKey(const ValueKey('markdown-task-checkbox-checked')),
      findsOneWidget,
    );
    final checkboxSize = tester.getSize(
      find.byKey(const ValueKey('markdown-task-checkbox-checked')),
    );
    expect(checkboxSize.width, closeTo(11.2, 0.001));
    expect(checkboxSize.height, closeTo(11.2, 0.001));
    expect(_previewPlainText(tester), contains('完成任务'));

    final lists = tester.widgetList<UnorderedListView>(
      find.byType(UnorderedListView),
    );

    expect(lists.any((list) => list.bulletSize == 0), isTrue);
    expect(lists.any((list) => list.bulletSize > 0), isTrue);
    expect(
      lists.any((list) => list.bulletSize == 0 && list.padding == 7),
      isTrue,
    );
  });

  testWidgets('markdown preview centers display math with balanced padding', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, r'\[E = mc^2\]');

    final displayMath = tester.widget<Container>(
      find.byKey(const ValueKey('markdown-display-math')),
    );

    expect(displayMath.alignment, Alignment.center);
    final padding = displayMath.padding as EdgeInsets;
    expect(padding.top, closeTo(15.68, 0.001));
    expect(padding.bottom, closeTo(15.68, 0.001));
  });

  testWidgets('markdown preview centers images with balanced padding', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '![remote](https://example.com/image.png)');

    final imageFrame = tester.widget<Container>(
      find.byKey(const ValueKey('markdown-image-frame')),
    );

    expect(imageFrame.alignment, Alignment.center);
    final padding = imageFrame.padding as EdgeInsets;
    expect(padding.top, closeTo(10.08, 0.001));
    expect(padding.bottom, closeTo(10.08, 0.001));
  });

  testWidgets('markdown preview renders retained blank lines by count', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '上\n\n\n\n下');

    expect(_previewPlainText(tester), contains('上\n\n\n\n下'));
  });

  test('spring markdown collapses blank lines after display math', () {
    expect(
      prepareSpringMarkdownText('\\[E = mc^2\\]\n\n正文'),
      '\\[E = mc^2\\]\n正文',
    );
    expect(
      prepareSpringMarkdownText('\\[E = mc^2\\]\n\n\n\n正文'),
      '\\[E = mc^2\\]\n\n正文',
    );
    expect(
      prepareSpringMarkdownText('\\[E = mc^2\\]\n\n\n\n\n正文'),
      '\\[E = mc^2\\]\n\n\n正文',
    );
  });

  test('spring markdown collapses blank lines before display math', () {
    expect(
      prepareSpringMarkdownText('正文\n\n\\[E = mc^2\\]'),
      '正文\n\\[E = mc^2\\]',
    );
    expect(
      prepareSpringMarkdownText('正文\n\n\n\n\\[E = mc^2\\]'),
      '正文\n\n\\[E = mc^2\\]',
    );
    expect(
      prepareSpringMarkdownText('正文\n\n\n\n\n\\[E = mc^2\\]'),
      '正文\n\n\n\\[E = mc^2\\]',
    );
  });

  test('spring markdown collapses blank lines around standalone images', () {
    expect(
      prepareSpringMarkdownText('正文\n\n![chart](images/chart.png)\n\n正文'),
      '正文\n![chart](images/chart.png)\n正文',
    );
    expect(
      prepareSpringMarkdownText(
        '正文\n\n\n\n![chart](images/chart.png)\n\n\n\n正文',
      ),
      '正文\n\n![chart](images/chart.png)\n\n正文',
    );
    expect(
      prepareSpringMarkdownText(
        '正文\n\n\n\n\n![chart](images/chart.png)\n\n\n\n\n正文',
      ),
      '正文\n\n\n![chart](images/chart.png)\n\n\n正文',
    );
  });

  test('spring markdown keeps extra blank lines around headings after two', () {
    expect(prepareSpringMarkdownText('# 标题\n\n正文'), '# 标题\n正文');
    expect(prepareSpringMarkdownText('# 标题\n\n\n\n正文'), '# 标题\n\n正文');
    expect(prepareSpringMarkdownText('# 标题\n\n\n\n\n正文'), '# 标题\n\n\n正文');
    expect(prepareSpringMarkdownText('正文\n\n# 标题'), '正文\n# 标题');
    expect(prepareSpringMarkdownText('正文\n\n\n\n# 标题'), '正文\n\n# 标题');
    expect(prepareSpringMarkdownText('正文\n\n\n\n\n# 标题'), '正文\n\n\n# 标题');
  });

  test('spring markdown promotes inline images to media blocks', () {
    expect(
      prepareSpringMarkdownText('正文 ![chart](images/chart.png) 后文'),
      '正文\n![chart](images/chart.png)\n后文',
    );
  });

  test('spring markdown preserves display math markers inside fenced code', () {
    const markdown = '```\n正文\n\n\\[E = mc^2\\]\n\n\\]\n\n正文\n```';

    expect(prepareSpringMarkdownText(markdown), markdown);
  });

  test('spring markdown preserves standalone images inside fenced code', () {
    const markdown =
        '```\n正文 ![chart](images/chart.png) 后文\n\n![chart](images/chart.png)\n\n正文\n```';

    expect(prepareSpringMarkdownText(markdown), markdown);
  });

  testWidgets('markdown preview keeps h1 divider close to heading', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, '# 标题\n\n正文');

    final markdownTheme = tester.widget<GptMarkdownTheme>(
      find.byType(GptMarkdownTheme),
    );

    expect(markdownTheme.gptThemeData.h1?.height, 0.92);
    expect(
      markdownTheme.gptThemeData.hrLinePadding,
      const EdgeInsets.only(bottom: 16),
    );
    final h1FontSize = markdownTheme.gptThemeData.h1?.fontSize;
    expect(h1FontSize, isNotNull);
    expect(markdownTheme.gptThemeData.h1?.color, const Color(0xFF333333));
    expect(
      markdownTheme.gptThemeData.h2?.fontSize,
      closeTo(h1FontSize! * 0.75, 0.001),
    );
    expect(markdownTheme.gptThemeData.h2?.fontWeight, FontWeight.w700);
    expect(markdownTheme.gptThemeData.h2?.color, const Color(0xFF333333));
    expect(
      markdownTheme.gptThemeData.h3?.fontSize,
      closeTo(h1FontSize * 0.625, 0.001),
    );
    expect(markdownTheme.gptThemeData.h3?.fontWeight, FontWeight.w700);
    expect(
      markdownTheme.gptThemeData.h4?.fontSize,
      closeTo(h1FontSize * 0.50, 0.001),
    );
    expect(
      markdownTheme.gptThemeData.h5?.fontSize,
      closeTo(h1FontSize * 0.438, 0.001),
    );
    expect(
      markdownTheme.gptThemeData.h6?.fontSize,
      closeTo(h1FontSize * 0.425, 0.001),
    );
    expect(markdownTheme.gptThemeData.h6?.fontWeight, FontWeight.w700);
  });

  testWidgets('markdown preview renders h1 followed by text consistently', (
    WidgetTester tester,
  ) async {
    const compact =
        '# 2026-07-07 日报\n'
        '今天完成了登录接口的开发工作，目前接口已可正常调用。下午点了一杯咖啡提神，继续跟进后续联调准备。';
    const spaced =
        '# 2026-07-07 日报\n\n'
        '今天完成了登录接口的开发工作，目前接口已可正常调用。下午点了一杯咖啡提神，继续跟进后续联调准备。';

    await _pumpPreview(tester, compact);
    final compactText = _previewPlainText(tester);

    await _pumpPreview(tester, spaced);
    final spacedText = _previewPlainText(tester);

    expect(compactText, spacedText);
  });

  testWidgets('markdown preview normalizes heading body spacing', (
    WidgetTester tester,
  ) async {
    const compact = '## 二级标题\n这是第二个测试';
    const spaced = '## 二级标题\n\n这是第二个测试';

    await _pumpPreview(tester, compact);
    final compactText = _previewPlainText(tester);

    await _pumpPreview(tester, spaced);
    final spacedText = _previewPlainText(tester);

    expect(compactText, spacedText);
  });

  testWidgets('markdown preview normalizes body heading spacing', (
    WidgetTester tester,
  ) async {
    const compact = '这是第二个测试\n### 三级标题\n这是第三个测试';
    const spaced = '这是第二个测试\n\n### 三级标题\n这是第三个测试';

    await _pumpPreview(tester, compact);
    final compactText = _previewPlainText(tester);

    await _pumpPreview(tester, spaced);
    final spacedText = _previewPlainText(tester);

    expect(compactText, spacedText);
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

String _previewPlainText(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((richText) => richText.text.toPlainText())
      .join('\n');
}

Color _bodyTextColor(WidgetTester tester) {
  return AppTheme.colors(tester.element(find.byType(MarkdownPreview))).text;
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
