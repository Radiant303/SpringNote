import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/core/widgets/markdown_code_block.dart';

const _code =
    'final message = "A deliberately long line that overflows the available code viewport";\nprint(message);';

void main() {
  testWidgets('code block uses the requested card and icon-only layout', (
    WidgetTester tester,
  ) async {
    await _pumpCodeBlock(tester);

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('markdown-code-block-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(card.margin, const EdgeInsets.symmetric(vertical: 16));
    expect(decoration.color, AppTheme.surface);
    expect((decoration.border! as Border).top.color, AppTheme.border);
    expect((decoration.border! as Border).top.width, 1);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(card.clipBehavior, Clip.none);
    final contentClip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byKey(const ValueKey('markdown-code-block-card')),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(contentClip.borderRadius, BorderRadius.circular(11));

    final headerFinder = find.byKey(
      const ValueKey('markdown-code-block-header'),
    );
    final header = tester.widget<Container>(headerFinder);
    final headerDecoration = header.decoration! as BoxDecoration;
    expect(tester.getSize(headerFinder).height, 38);
    expect(headerDecoration.color, const Color(0xFFF5F5F5));

    final language = tester.widget<Text>(find.text('text'));
    expect(language.style?.fontSize, 14);
    expect(language.style?.fontWeight, FontWeight.w500);

    final copyButtonFinder = find.byKey(
      const ValueKey('markdown-code-copy-button'),
    );
    expect(tester.getSize(copyButtonFinder), const Size(32, 32));
    expect(tester.getSize(find.byType(SvgPicture)), const Size(20, 20));
    expect(find.text('Copy'), findsNothing);
    expect(find.text('复制'), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('markdown-code-scroll-view')),
    );
    expect(scrollView.padding, const EdgeInsets.fromLTRB(18, 14, 18, 12));
    expect(find.byType(Scrollbar), findsNothing);

    final codeText = tester.widget<Text>(find.text(_code));
    expect(codeText.style?.fontSize, 14);
    expect(codeText.style?.height, closeTo(22 / 14, 0.0001));

    final scrollbarFinder = find.byKey(
      const ValueKey('markdown-code-scrollbar'),
    );
    final cardRect = tester.getRect(
      find.byKey(const ValueKey('markdown-code-block-card')),
    );
    final scrollbarRect = tester.getRect(scrollbarFinder);
    expect(scrollbarRect.height, 14);
    expect(scrollbarRect.left - cardRect.left, 19);
    expect(cardRect.right - scrollbarRect.right, 19);
  });

  testWidgets('copy button copies code without showing copy status text', (
    WidgetTester tester,
  ) async {
    await _pumpCodeBlock(tester);

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.byKey(const ValueKey('markdown-code-copy-button')));
    await tester.pump();

    final clipboardCall = calls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect((clipboardCall.arguments as Map<Object?, Object?>)['text'], _code);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Copied'), findsNothing);
    expect(find.text('复制'), findsNothing);
    expect(find.text('已复制'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('custom indicator drags the horizontal code viewport', (
    WidgetTester tester,
  ) async {
    await _pumpCodeBlock(tester);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('markdown-code-scroll-view')),
    );
    final controller = scrollView.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));

    final scrollbarFinder = find.byKey(
      const ValueKey('markdown-code-scrollbar'),
    );
    final drag = await tester.startGesture(
      tester.getCenter(scrollbarFinder),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 80));
    await drag.moveBy(const Offset(64, 0));
    await tester.pump();

    expect(controller.offset, greaterThan(0));

    await drag.up();
    await tester.pump(const Duration(milliseconds: 160));
  });

  testWidgets('custom indicator expands smoothly while hovered', (
    WidgetTester tester,
  ) async {
    await _pumpCodeBlock(tester);

    final scrollbarFinder = find.byKey(
      const ValueKey('markdown-code-scrollbar'),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: scrollbarFinder, matching: find.byType(CustomPaint)),
    );
    final expansion =
        (paint.painter! as dynamic).expansion as Animation<double>;
    expect(expansion.value, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final center = tester.getCenter(scrollbarFinder);
    await mouse.moveTo(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(expansion.value, greaterThan(0));
    expect(expansion.value, lessThan(1));

    await tester.pump(const Duration(milliseconds: 80));
    expect(expansion.value, 1);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(expansion.value, 0);
  });

  testWidgets('dark theme uses a light scrollbar palette', (
    WidgetTester tester,
  ) async {
    await _pumpCodeBlock(tester, theme: AppTheme.dark());

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('markdown-code-scrollbar')),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as dynamic;
    expect(painter.idleColor, const Color(0x3DFFFFFF));
    expect(painter.activeColor, const Color(0xA6FFFFFF));
  });
}

Future<void> _pumpCodeBlock(WidgetTester tester, {ThemeData? theme}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 460,
            child: MarkdownCodeBlock(language: 'text', code: _code),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
