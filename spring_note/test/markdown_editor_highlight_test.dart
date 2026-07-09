import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/core/widgets/markdown_editor_highlight.dart';

void main() {
  testWidgets('markdown editor highlight preserves markdown source', (
    WidgetTester tester,
  ) async {
    const source =
        '# 🚀 1级标题: 欢迎测试高亮器\r\n'
        '**`memory_page.dart` 工具调用缓存策略**:\r\n'
        '*`memory_page.dart` 工具调用缓存策略*:\r\n'
        '***粗斜体***\r\n'
        '* `memory_page.dart`\r\n'
        '* 这是**加粗文本**，用于测试强重音。\r\n'
        '* 这是*斜体文本*，用于测试弱重音。\r\n'
        '* 这是一个带有 `inline code test()` 的行内代码。\r\n'
        r'\['
        '\r\n'
        r'\int_D f(x,y)\,dx\,dy \quad \iiint_{V}\rho\,dV'
        '\r\n'
        r'\]'
        '\r\n'
        '- [x] 完成任务\r\n'
        '> ### 引用里面的标题\r\n'
        '![图表](images/chart.png)\r\n'
        '[![Star History Chart](https://api.star-history.com/svg?repos=Radiant303/SpringNote&type=Date)](https://star-history.com/#Radiant303/SpringNote&Date)\r\n'
        '[链接](https://example.com)\r\n'
        '[#71](https://github.com/Radiant303/SpringNote/issues/71)\r\n'
        '```dart\r\n'
        'print("hi");\r\n'
        '```\r\n'
        '---';
    const baseColor = Color(0xFF171717);

    late final TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            span = MarkdownEditorHighlightSpanBuilder(
              context,
              includeBottomSpacer: false,
            ).build(source, textStyle: const TextStyle(color: baseColor));
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(span.toPlainText(), source);
    expect(_hasNonBaseColor(span, baseColor), isTrue);
    expect(
      _styleOfText(span, ' 🚀 1级标题: 欢迎测试高亮器')?.color,
      const Color(0xFFD3604F),
    );
    expect(_styleOfText(span, '加粗文本')?.color, const Color(0xFFAD6E25));
    expect(_styleOfText(span, '加粗文本')?.fontWeight, FontWeight.w700);
    expect(_styleOfText(span, '粗斜体')?.color, const Color(0xFFAD6E25));
    expect(_styleOfText(span, '粗斜体')?.fontWeight, FontWeight.w700);
    expect(_styleOfText(span, '斜体文本')?.color, const Color(0xFF5B79E3));
    expect(_styleOfText(span, '斜体文本')?.fontStyle, isNull);
    expect(
      _styleOfText(span, 'inline code test()')?.color,
      const Color(0xFF3E8B45),
    );
    expect(_styleOfText(span, 'inline code test()')?.fontFamily, isNull);
    expect(_styleOfText(span, 'https://example.com')?.fontFamily, isNull);
    expect(_styleOfText(span, '图表')?.color, const Color(0xFF5B79E3));
    expect(
      _styleOfText(span, 'Star History Chart')?.color,
      const Color(0xFF5B79E3),
    );
    expect(
      _styleOfText(
        span,
        'https://star-history.com/#Radiant303/SpringNote&Date',
      )?.color,
      const Color(0xFF3882B7),
    );
    expect(_styleOfText(span, '链接')?.color, const Color(0xFF5B79E3));
    expect(_styleOfText(span, '#71')?.color, const Color(0xFF5B79E3));
    expect(
      _stylesOfText(
        span,
        '[',
      ).where((style) => style.color == const Color(0xFF5B79E3)).length,
      greaterThanOrEqualTo(3),
    );
    expect(
      _stylesOfText(
        span,
        ']',
      ).where((style) => style.color == const Color(0xFF5B79E3)).length,
      greaterThanOrEqualTo(3),
    );
    expect(
      _styleOfText(
        span,
        r'\int_D f(x,y)\,dx\,dy \quad \iiint_{V}\rho\,dV',
      )?.color,
      const Color(0xFF5B79E3),
    );
    expect(
      _styleOfText(span, 'https://example.com')?.color,
      const Color(0xFF3882B7),
    );
    expect(_stylesOfText(span, '**').map((style) => style.color), {
      const Color(0xFFAD6E25),
    });
    expect(
      _stylesOfText(span, '**').every((style) => style.fontWeight == null),
      isTrue,
    );
    expect(
      _stylesOfText(
        span,
        '*',
      ).map((style) => style.color).contains(const Color(0xFF5B79E3)),
      isTrue,
    );
    expect(
      _stylesOfText(span, '*').any(
        (style) =>
            style.color == const Color(0xFF5B79E3) &&
            style.fontWeight == FontWeight.w700,
      ),
      isFalse,
    );
    expect(
      _stylesOfText(
        span,
        '*',
      ).map((style) => style.color).contains(const Color(0xFF5B79E3)),
      isTrue,
    );
    expect(
      _stylesOfText(
        span,
        '*',
      ).map((style) => style.color).contains(const Color(0xFFD3604F)),
      isTrue,
    );
    expect(
      _styleOfText(span, 'memory_page.dart')?.color,
      const Color(0xFF3E8B45),
    );
  });
}

bool _hasNonBaseColor(InlineSpan span, Color baseColor) {
  var found = false;
  span.visitChildren((child) {
    if (child is TextSpan) {
      final color = child.style?.color;
      if (color != null &&
          color != baseColor &&
          child.text?.isNotEmpty == true) {
        found = true;
        return false;
      }
    }
    return true;
  });
  return found;
}

TextStyle? _styleOfText(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text) {
      return span.style;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final style = _styleOfText(child, text);
      if (style != null) {
        return style;
      }
    }
  }
  return null;
}

List<TextStyle> _stylesOfText(InlineSpan span, String text) {
  final styles = <TextStyle>[];
  _collectStylesOfText(span, text, styles);
  return styles;
}

void _collectStylesOfText(
  InlineSpan span,
  String text,
  List<TextStyle> styles,
) {
  if (span is! TextSpan) {
    return;
  }
  if (span.text == text && span.style != null) {
    styles.add(span.style!);
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    _collectStylesOfText(child, text, styles);
  }
}
