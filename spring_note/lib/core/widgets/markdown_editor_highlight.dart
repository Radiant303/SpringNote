import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MarkdownEditorHighlightSpanBuilder {
  MarkdownEditorHighlightSpanBuilder(
    BuildContext context, {
    this.includeBottomSpacer = true,
  }) : _palette = _MarkdownEditorHighlightPalette.from(context);

  MarkdownEditorHighlightSpanBuilder._(
    this._palette, {
    this.includeBottomSpacer = true,
  });

  final bool includeBottomSpacer;
  final _MarkdownEditorHighlightPalette _palette;

  static final RegExp _fencePattern = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
  static final RegExp _headingPattern = RegExp(
    r'^( {0,3})(#{1,6})(?=\s|$)(.*)$',
  );
  static final RegExp _blockquotePattern = RegExp(r'^( {0,3})(>+\s?)(.*)$');
  static final RegExp _listPattern = RegExp(
    r'^(\s*)((?:[-+*])|(?:\d+[.)]))(\s+)(\[[ xX]\])?(\s*)(.*)$',
  );
  static final RegExp _hrPattern = RegExp(r'^\s{0,3}(?:([-*_])\s*){3,}$');
  static final RegExp _mathBlockStartPattern = RegExp(r'^\s*(?:\$\$|\\\[)');

  TextSpan build(String data, {TextStyle? textStyle}) {
    final style = textStyle ?? const TextStyle();
    final children = <InlineSpan>[];

    _appendMarkdown(children, data, style);
    if (includeBottomSpacer) {
      children.add(
        TextSpan(
          text: '\n',
          style: style.copyWith(color: Colors.transparent),
        ),
      );
    }

    return TextSpan(style: style, children: children);
  }

  TextSpan buildTextEditingValue(
    TextEditingValue value, {
    TextStyle? textStyle,
    required bool withComposing,
  }) {
    final style = textStyle ?? const TextStyle();
    if (!withComposing ||
        !value.composing.isValid ||
        !value.isComposingRangeValid) {
      return build(value.text, textStyle: style);
    }

    final children = <InlineSpan>[
      MarkdownEditorHighlightSpanBuilder._(
        _palette,
        includeBottomSpacer: false,
      ).build(value.composing.textBefore(value.text), textStyle: style),
      TextSpan(
        text: value.composing.textInside(value.text),
        style: style.merge(
          const TextStyle(decoration: TextDecoration.underline),
        ),
      ),
      MarkdownEditorHighlightSpanBuilder._(
        _palette,
        includeBottomSpacer: false,
      ).build(value.composing.textAfter(value.text), textStyle: style),
    ];
    if (includeBottomSpacer) {
      children.add(
        TextSpan(
          text: '\n',
          style: style.copyWith(color: Colors.transparent),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }

  void _appendMarkdown(
    List<InlineSpan> children,
    String data,
    TextStyle style,
  ) {
    var offset = 0;
    var inFence = false;
    var inMathBlock = false;
    String? fenceMarker;

    while (offset < data.length) {
      final newlineIndex = data.indexOf('\n', offset);
      final lineEnd = newlineIndex < 0 ? data.length : newlineIndex + 1;
      final line = data.substring(offset, lineEnd);
      final hasNewline = line.endsWith('\n');
      final withoutLf = hasNewline ? line.substring(0, line.length - 1) : line;
      final hasCr = withoutLf.endsWith('\r');
      final content = hasCr
          ? withoutLf.substring(0, withoutLf.length - 1)
          : withoutLf;
      final lineEnding = '${hasCr ? '\r' : ''}${hasNewline ? '\n' : ''}';

      if (inFence) {
        _appendStyled(children, content, _codeBlockStyle(style));
        _appendLineEnding(children, lineEnding, style);
        if (_isClosingFence(content, fenceMarker)) {
          inFence = false;
          fenceMarker = null;
        }
        offset = lineEnd;
        continue;
      }

      if (inMathBlock) {
        _appendStyled(children, content, _mathStyle(style));
        _appendLineEnding(children, lineEnding, style);
        if (_isClosingMathBlock(content)) {
          inMathBlock = false;
        }
        offset = lineEnd;
        continue;
      }

      if (_mathBlockStartPattern.hasMatch(content)) {
        _appendStyled(children, content, _mathStyle(style));
        _appendLineEnding(children, lineEnding, style);
        if (!_isClosingMathBlock(content)) {
          inMathBlock = true;
        }
        offset = lineEnd;
        continue;
      }

      final fenceMatch = _fencePattern.firstMatch(content);
      if (fenceMatch != null) {
        _appendStyled(children, content, _codeBlockStyle(style));
        _appendLineEnding(children, lineEnding, style);
        inFence = true;
        fenceMarker = fenceMatch.group(1);
        offset = lineEnd;
        continue;
      }

      _appendLine(children, content, style);
      _appendLineEnding(children, lineEnding, style);
      offset = lineEnd;
    }
  }

  bool _isClosingFence(String line, String? fenceMarker) {
    if (fenceMarker == null || fenceMarker.isEmpty) {
      return false;
    }
    final trimmed = line.trimLeft();
    return trimmed.startsWith(
      List.filled(fenceMarker.length, fenceMarker[0]).join(),
    );
  }

  bool _isClosingMathBlock(String line) {
    final trimmed = line.trim();
    return trimmed == r'\]' ||
        trimmed.endsWith(r'\]') ||
        trimmed.endsWith(r'$$');
  }

  void _appendLine(List<InlineSpan> children, String line, TextStyle style) {
    if (line.isEmpty) {
      return;
    }

    if (_hrPattern.hasMatch(line)) {
      _appendStyled(children, line, _hrStyle(style));
      return;
    }

    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      final headingStyle = _headingStyle(style);
      _appendStyled(children, headingMatch.group(1), style);
      _appendStyled(children, headingMatch.group(2), headingStyle);
      _appendInline(children, headingMatch.group(3)!, headingStyle);
      return;
    }

    final quoteMatch = _blockquotePattern.firstMatch(line);
    if (quoteMatch != null) {
      _appendStyled(children, quoteMatch.group(1), style);
      _appendStyled(children, quoteMatch.group(2), _quoteMarkerStyle(style));
      _appendLine(children, quoteMatch.group(3)!, style);
      return;
    }

    final listMatch = _listPattern.firstMatch(line);
    if (listMatch != null) {
      _appendStyled(children, listMatch.group(1), style);
      _appendStyled(children, listMatch.group(2), _listMarkerStyle(style));
      _appendStyled(children, listMatch.group(3), style);
      final checkbox = listMatch.group(4);
      if (checkbox != null) {
        _appendStyled(children, checkbox, _checkboxStyle(style));
      }
      _appendStyled(children, listMatch.group(5), style);
      _appendInline(children, listMatch.group(6)!, style);
      return;
    }

    _appendInline(children, line, style);
  }

  void _appendInline(List<InlineSpan> children, String text, TextStyle style) {
    var index = 0;
    while (index < text.length) {
      final linkEnd = _appendLink(children, text, index, style);
      if (linkEnd != null) {
        index = linkEnd;
        continue;
      }

      final codeEnd = _appendInlineCode(children, text, index, style);
      if (codeEnd != null) {
        index = codeEnd;
        continue;
      }

      final mathEnd = _appendInlineMath(children, text, index, style);
      if (mathEnd != null) {
        index = mathEnd;
        continue;
      }

      final delimiterEnd = _appendDelimited(children, text, index, style);
      if (delimiterEnd != null) {
        index = delimiterEnd;
        continue;
      }

      final next = _nextInlineTrigger(text, index + 1);
      _appendStyled(children, text.substring(index, next), style);
      index = next;
    }
  }

  int? _appendLink(
    List<InlineSpan> children,
    String text,
    int index,
    TextStyle style,
  ) {
    var cursor = index;
    final isImage = text.startsWith('![', index);
    if (isImage) {
      cursor += 1;
    }
    if (!text.startsWith('[', cursor)) {
      return null;
    }

    final labelEnd = _findUnescaped(text, ']', cursor + 1);
    if (labelEnd == null ||
        labelEnd + 1 >= text.length ||
        text[labelEnd + 1] != '(') {
      return null;
    }
    final urlEnd = _findUnescaped(text, ')', labelEnd + 2);
    if (urlEnd == null) {
      return null;
    }

    final labelStyle = _imageStyle(style);
    final bracketStyle = _imageStyle(style);
    if (isImage) {
      _appendStyled(children, '!', _imageStyle(style));
    }
    _appendStyled(children, '[', bracketStyle);
    _appendInline(children, text.substring(cursor + 1, labelEnd), labelStyle);
    _appendStyled(children, ']', bracketStyle);
    _appendStyled(children, '(', _linkSyntaxStyle(style));
    _appendStyled(
      children,
      text.substring(labelEnd + 2, urlEnd),
      _linkUrlStyle(style),
    );
    _appendStyled(children, ')', _linkSyntaxStyle(style));
    return urlEnd + 1;
  }

  int? _appendInlineCode(
    List<InlineSpan> children,
    String text,
    int index,
    TextStyle style,
  ) {
    if (text[index] != '`') {
      return null;
    }

    var tickCount = 1;
    while (index + tickCount < text.length && text[index + tickCount] == '`') {
      tickCount += 1;
    }

    final fence = '`' * tickCount;
    final end = text.indexOf(fence, index + tickCount);
    final codeStyle = _inlineCodeStyle(style);
    if (end < 0) {
      _appendStyled(children, text.substring(index), codeStyle);
      return text.length;
    }

    _appendStyled(children, fence, codeStyle);
    _appendStyled(children, text.substring(index + tickCount, end), codeStyle);
    _appendStyled(children, fence, codeStyle);
    return end + tickCount;
  }

  int? _appendInlineMath(
    List<InlineSpan> children,
    String text,
    int index,
    TextStyle style,
  ) {
    if (text.startsWith(r'\(', index)) {
      return _appendDelimitedRaw(
        children,
        text,
        index,
        r'\(',
        r'\)',
        _mathStyle(style),
      );
    }
    if (text.startsWith(r'\[', index)) {
      return _appendDelimitedRaw(
        children,
        text,
        index,
        r'\[',
        r'\]',
        _mathStyle(style),
      );
    }
    if (text.startsWith(r'$$', index)) {
      return _appendDelimitedRaw(
        children,
        text,
        index,
        r'$$',
        r'$$',
        _mathStyle(style),
      );
    }
    if (text[index] == r'$') {
      return _appendDelimitedRaw(
        children,
        text,
        index,
        r'$',
        r'$',
        _mathStyle(style),
      );
    }
    return null;
  }

  int? _appendDelimitedRaw(
    List<InlineSpan> children,
    String text,
    int index,
    String startDelimiter,
    String endDelimiter,
    TextStyle style,
  ) {
    final end = text.indexOf(endDelimiter, index + startDelimiter.length);
    if (end < 0 || _isEscaped(text, end)) {
      return null;
    }
    final next = end + endDelimiter.length;
    _appendStyled(children, text.substring(index, next), style);
    return next;
  }

  int? _appendDelimited(
    List<InlineSpan> children,
    String text,
    int index,
    TextStyle style,
  ) {
    const delimiters = ['***', '___', '**', '__', '~~', '*', '_'];
    for (final delimiter in delimiters) {
      if (!text.startsWith(delimiter, index)) {
        continue;
      }
      if (delimiter.length == 1 &&
          index + 1 < text.length &&
          text[index + 1] == delimiter) {
        continue;
      }
      final end = _findClosingDelimiter(
        text,
        delimiter,
        index + delimiter.length,
      );
      if (end == null || end <= index + delimiter.length) {
        continue;
      }

      final contentStyle = _delimiterContentStyle(style, delimiter);
      final markerStyle = contentStyle;
      _appendStyled(children, delimiter, markerStyle);
      _appendInline(
        children,
        text.substring(index + delimiter.length, end),
        contentStyle,
      );
      _appendStyled(children, delimiter, markerStyle);
      return end + delimiter.length;
    }
    return null;
  }

  int? _findClosingDelimiter(String text, String delimiter, int start) {
    var index = start;
    while (index < text.length) {
      final found = text.indexOf(delimiter, index);
      if (found < 0) {
        return null;
      }
      if (!_isEscaped(text, found)) {
        return found;
      }
      index = found + delimiter.length;
    }
    return null;
  }

  int? _findUnescaped(String text, String target, int start) {
    var index = start;
    while (index < text.length) {
      if (text[index] == target && !_isEscaped(text, index)) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  bool _isEscaped(String text, int index) {
    var slashCount = 0;
    var cursor = index - 1;
    while (cursor >= 0 && text[cursor] == '\\') {
      slashCount += 1;
      cursor -= 1;
    }
    return slashCount.isOdd;
  }

  int _nextInlineTrigger(String text, int start) {
    var index = start;
    while (index < text.length) {
      final char = text[index];
      if (char == '!' ||
          char == '[' ||
          char == '`' ||
          char == r'$' ||
          char == r'\' ||
          char == '*' ||
          char == '_' ||
          char == '~') {
        return index;
      }
      index += 1;
    }
    return text.length;
  }

  TextStyle _headingStyle(TextStyle base) {
    return base.copyWith(color: _palette.heading);
  }

  TextStyle _hrStyle(TextStyle base) {
    return base.copyWith(color: _palette.heading);
  }

  TextStyle _listMarkerStyle(TextStyle base) {
    return base.copyWith(color: _palette.markup);
  }

  TextStyle _quoteMarkerStyle(TextStyle base) {
    return base.copyWith(color: _palette.markup);
  }

  TextStyle _checkboxStyle(TextStyle base) {
    return base.copyWith(color: _palette.checkbox);
  }

  TextStyle _linkSyntaxStyle(TextStyle base) {
    return base.copyWith(color: _palette.link);
  }

  TextStyle _linkUrlStyle(TextStyle base) {
    return base.copyWith(color: _palette.link);
  }

  TextStyle _imageStyle(TextStyle base) {
    return base.copyWith(color: _palette.image);
  }

  TextStyle _inlineCodeStyle(TextStyle base) {
    return base.copyWith(color: _palette.code);
  }

  TextStyle _codeBlockStyle(TextStyle base) {
    return base.copyWith(color: _palette.code);
  }

  TextStyle _mathStyle(TextStyle base) {
    return base.copyWith(color: _palette.math);
  }

  TextStyle _delimiterContentStyle(TextStyle base, String delimiter) {
    return switch (delimiter) {
      '***' || '___' => base.copyWith(
        color: _palette.strongEmphasis,
        fontWeight: FontWeight.w700,
      ),
      '**' || '__' => base.copyWith(
        color: _palette.strong,
        fontWeight: FontWeight.w700,
      ),
      '*' || '_' => base.copyWith(color: _palette.emphasis),
      '~~' => base.copyWith(color: _palette.strike),
      _ => base,
    };
  }

  void _appendLineEnding(
    List<InlineSpan> children,
    String lineEnding,
    TextStyle style,
  ) {
    if (lineEnding.isNotEmpty) {
      children.add(TextSpan(text: lineEnding, style: style));
    }
  }

  void _appendStyled(List<InlineSpan> children, String? text, TextStyle style) {
    if (text == null || text.isEmpty) {
      return;
    }
    children.add(TextSpan(text: text, style: style));
  }
}

class _MarkdownEditorHighlightPalette {
  const _MarkdownEditorHighlightPalette({
    required this.markup,
    required this.heading,
    required this.checkbox,
    required this.link,
    required this.image,
    required this.code,
    required this.math,
    required this.strong,
    required this.strongEmphasis,
    required this.emphasis,
    required this.strike,
  });

  final Color markup;
  final Color heading;
  final Color checkbox;
  final Color link;
  final Color image;
  final Color code;
  final Color math;
  final Color strong;
  final Color strongEmphasis;
  final Color emphasis;
  final Color strike;

  factory _MarkdownEditorHighlightPalette.from(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _MarkdownEditorHighlightPalette(
      markup: dark ? const Color(0xFFD3604F) : const Color(0xFFD3604F),
      heading: dark ? const Color(0xFFD3604F) : const Color(0xFFD3604F),
      checkbox: dark ? const Color(0xFF5B79E3) : const Color(0xFF5B79E3),
      link: dark ? const Color(0xFF3882B7) : const Color(0xFF3882B7),
      image: dark ? const Color(0xFF5B79E3) : const Color(0xFF5B79E3),
      code: dark ? const Color(0xFF9FCA8F) : const Color(0xFF3E8B45),
      math: dark ? const Color(0xFF5B79E3) : const Color(0xFF5B79E3),
      strong: dark ? const Color(0xFFAD6E25) : const Color(0xFFAD6E25),
      strongEmphasis: dark ? const Color(0xFFAD6E25) : const Color(0xFFAD6E25),
      emphasis: dark ? const Color(0xFF5B79E3) : const Color(0xFF5B79E3),
      strike: colors.textSubtle.withValues(alpha: dark ? 0.86 : 0.78),
    );
  }
}
