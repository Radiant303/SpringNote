import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../core/theme/app_theme.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final blocks = _MarkdownParser(markdown).parse();

    if (blocks.isEmpty) {
      return Center(
        child: Text(
          '预览区域会随着 Markdown 源码实时刷新',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(34, 30, 34, 48),
        itemCount: blocks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 18),
        itemBuilder: (context, index) =>
            _MarkdownBlockView(block: blocks[index]),
      ),
    );
  }
}

class _MarkdownBlockView extends StatelessWidget {
  const _MarkdownBlockView({required this.block});

  final _MarkdownBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      _HeadingBlock(:final level, :final text) => Text(
        text,
        style: _headingStyle(context, level),
      ),
      _ParagraphBlock(:final text) => _InlineText(text: text),
      _QuoteBlock(:final text) => Container(
        padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFDCE3EB), width: 3)),
        ),
        child: _InlineText(
          text: text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppTheme.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      _ListBlock(:final ordered, :final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      ordered ? '${item.$1 + 1}.' : '•',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  Expanded(child: _InlineText(text: item.$2)),
                ],
              ),
            ),
        ],
      ),
      _CodeBlock(:final language, :final code) => _HighlightedCodeBlock(
        language: language,
        code: code,
      ),
      _MathBlock(:final formula) => _MathBlockView(formula: formula),
      _TableBlock(:final rows) => _MarkdownTable(rows: rows),
    };
  }

  TextStyle? _headingStyle(BuildContext context, int level) {
    final base = Theme.of(context).textTheme;
    return switch (level) {
      1 => base.headlineLarge?.copyWith(fontSize: 34, letterSpacing: -0.8),
      2 => base.headlineMedium?.copyWith(fontSize: 26),
      3 => base.titleLarge?.copyWith(fontSize: 21),
      _ => base.titleMedium,
    };
  }
}

class _InlineText extends StatelessWidget {
  const _InlineText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ?? Theme.of(context).textTheme.bodyLarge;
    return RichText(
      text: TextSpan(
        style: defaultStyle,
        children: _inlineSpans(context, text),
      ),
    );
  }

  List<InlineSpan> _inlineSpans(BuildContext context, String source) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(`[^`]+`)|(\[[^\]]+\]\([^)]+\))|(\$(?!\$)([^\n$]+)\$)',
    );
    var index = 0;

    for (final match in pattern.allMatches(source)) {
      if (match.start > index) {
        spans.add(TextSpan(text: source.substring(index, match.start)));
      }

      final token = match.group(0)!;
      if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 13,
              color: AppTheme.text,
              backgroundColor: Color(0xFFF1F5F9),
            ),
          ),
        );
      } else if (token.startsWith(r'$')) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _InlineMath(formula: token.substring(1, token.length - 1)),
          ),
        );
      } else {
        final linkMatch = RegExp(
          r'^\[([^\]]+)\]\(([^)]+)\)$',
        ).firstMatch(token);
        spans.add(
          TextSpan(
            text: linkMatch?.group(1) ?? token,
            style: const TextStyle(
              color: Color(0xFF2563EB),
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer(),
          ),
        );
      }

      index = match.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index)));
    }

    return spans;
  }
}

class _HighlightedCodeBlock extends StatelessWidget {
  const _HighlightedCodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  Widget build(BuildContext context) {
    final label = language.isEmpty ? 'text' : language;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEFF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8EDF3))),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSubtle,
                fontFamily: 'Consolas',
                fontSize: 11,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(18),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontFamily: 'Consolas',
                  fontSize: 13,
                  height: 1.65,
                ),
                children: _CodeHighlighter(
                  language: language,
                  code: code,
                ).spans(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeHighlighter {
  const _CodeHighlighter({required this.language, required this.code});

  final String language;
  final String code;

  static const _keywordColor = Color(0xFF2563EB);
  static const _stringColor = Color(0xFF059669);
  static const _commentColor = Color(0xFF94A3B8);
  static const _numberColor = Color(0xFFDC2626);
  static const _typeColor = Color(0xFF7C3AED);

  List<InlineSpan> spans() {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'("([^"\\]|\\.)*"|'
      "'([^'\\\\]|\\\\.)*'"
      r'|//.*|#.*|/\*[\s\S]*?\*/|\b\d+(\.\d+)?\b|\b[A-Z][A-Za-z0-9_]*\b|\b[a-zA-Z_][a-zA-Z0-9_]*\b)',
      multiLine: true,
    );
    var index = 0;

    for (final match in pattern.allMatches(code)) {
      if (match.start > index) {
        spans.add(TextSpan(text: code.substring(index, match.start)));
      }

      final token = match.group(0)!;
      spans.add(TextSpan(text: token, style: _styleFor(token)));
      index = match.end;
    }

    if (index < code.length) {
      spans.add(TextSpan(text: code.substring(index)));
    }

    return spans;
  }

  TextStyle? _styleFor(String token) {
    if (token.startsWith('//') ||
        token.startsWith('#') ||
        token.startsWith('/*')) {
      return const TextStyle(color: _commentColor, fontStyle: FontStyle.italic);
    }
    if (token.startsWith('"') || token.startsWith("'")) {
      return const TextStyle(color: _stringColor);
    }
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(token)) {
      return const TextStyle(color: _numberColor);
    }
    if (_keywordsFor(language).contains(token)) {
      return const TextStyle(color: _keywordColor, fontWeight: FontWeight.w700);
    }
    if (RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(token)) {
      return const TextStyle(color: _typeColor);
    }
    return null;
  }

  Set<String> _keywordsFor(String language) {
    final normalized = language.toLowerCase();
    final common = {
      'class',
      'enum',
      'extends',
      'implements',
      'import',
      'export',
      'return',
      'if',
      'else',
      'for',
      'while',
      'switch',
      'case',
      'break',
      'continue',
      'try',
      'catch',
      'finally',
      'true',
      'false',
      'null',
    };

    if (normalized == 'rust' || normalized == 'rs') {
      return {
        ...common,
        'fn',
        'let',
        'mut',
        'pub',
        'mod',
        'use',
        'struct',
        'impl',
        'trait',
        'match',
        'async',
        'await',
        'move',
        'const',
        'static',
        'ref',
        'Self',
        'self',
        'crate',
      };
    }

    if (normalized == 'dart') {
      return {
        ...common,
        'final',
        'var',
        'const',
        'void',
        'Future',
        'async',
        'await',
        'required',
        'this',
        'super',
        'new',
        'mixin',
        'with',
      };
    }

    if (normalized == 'js' ||
        normalized == 'javascript' ||
        normalized == 'ts' ||
        normalized == 'typescript') {
      return {
        ...common,
        'const',
        'let',
        'var',
        'function',
        'async',
        'await',
        'new',
        'this',
        'type',
        'interface',
      };
    }

    return common;
  }
}

class _InlineMath extends StatelessWidget {
  const _InlineMath({required this.formula});

  final String formula;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: _MathFormula(formula: formula, inline: true),
    );
  }
}

class _MathBlockView extends StatelessWidget {
  const _MathBlockView({required this.formula});

  final String formula;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: _MathFormula(formula: formula, inline: false),
    );
  }
}

class _MathFormula extends StatelessWidget {
  const _MathFormula({required this.formula, required this.inline});

  final String formula;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: AppTheme.text,
      fontSize: inline ? 15.5 : 23,
    );

    return Math.tex(
      formula,
      textStyle: textStyle,
      mathStyle: inline ? MathStyle.text : MathStyle.display,
      textScaleFactor: 1,
      onErrorFallback: (error) => Text(
        formula,
        textAlign: inline ? TextAlign.start : TextAlign.center,
        style: TextStyle(
          color: AppTheme.text,
          fontFamily: 'Consolas',
          fontSize: inline ? 13 : 15,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final header = rows.first;
    final body = rows.skip(1).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFEFF2F7)),
          bottom: BorderSide(color: Color(0xFFEFF2F7)),
        ),
        columnWidths: {
          for (var index = 0; index < header.length; index++)
            index: const FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
            children: [
              for (final cell in header) _TableCell(text: cell, header: true),
            ],
          ),
          for (final row in body)
            TableRow(
              children: [
                for (var index = 0; index < header.length; index++)
                  _TableCell(text: index < row.length ? row[index] : ''),
              ],
            ),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.text, this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: header ? AppTheme.text : AppTheme.textMuted,
          fontWeight: header ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock(this.level, this.text);

  final int level;
  final String text;
}

class _ParagraphBlock extends _MarkdownBlock {
  const _ParagraphBlock(this.text);

  final String text;
}

class _QuoteBlock extends _MarkdownBlock {
  const _QuoteBlock(this.text);

  final String text;
}

class _ListBlock extends _MarkdownBlock {
  const _ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<String> items;
}

class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;
}

class _MathBlock extends _MarkdownBlock {
  const _MathBlock(this.formula);

  final String formula;
}

class _TableBlock extends _MarkdownBlock {
  const _TableBlock(this.rows);

  final List<List<String>> rows;
}

class _MarkdownParser {
  const _MarkdownParser(this.markdown);

  final String markdown;

  List<_MarkdownBlock> parse() {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_MarkdownBlock>[];
    var index = 0;

    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        index++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        final language = trimmed.substring(3).trim();
        final codeLines = <String>[];
        index++;
        while (index < lines.length && !lines[index].trim().startsWith('```')) {
          codeLines.add(lines[index]);
          index++;
        }
        if (index < lines.length) {
          index++;
        }
        blocks.add(_CodeBlock(language: language, code: codeLines.join('\n')));
        continue;
      }

      if (trimmed == r'$$') {
        final mathLines = <String>[];
        index++;
        while (index < lines.length && lines[index].trim() != r'$$') {
          mathLines.add(lines[index]);
          index++;
        }
        if (index < lines.length) {
          index++;
        }
        blocks.add(_MathBlock(mathLines.join(' ').trim()));
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        blocks.add(
          _HeadingBlock(heading.group(1)!.length, heading.group(2)!.trim()),
        );
        index++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (index < lines.length && lines[index].trim().startsWith('>')) {
          quoteLines.add(
            lines[index].trim().replaceFirst(RegExp(r'^>\s?'), ''),
          );
          index++;
        }
        blocks.add(_QuoteBlock(quoteLines.join('\n')));
        continue;
      }

      if (_isListLine(trimmed, ordered: false)) {
        final items = <String>[];
        while (index < lines.length &&
            _isListLine(lines[index].trim(), ordered: false)) {
          items.add(lines[index].trim().replaceFirst(RegExp(r'^[-*+]\s+'), ''));
          index++;
        }
        blocks.add(_ListBlock(ordered: false, items: items));
        continue;
      }

      if (_isListLine(trimmed, ordered: true)) {
        final items = <String>[];
        while (index < lines.length &&
            _isListLine(lines[index].trim(), ordered: true)) {
          items.add(
            lines[index].trim().replaceFirst(RegExp(r'^\d+[.)]\s+'), ''),
          );
          index++;
        }
        blocks.add(_ListBlock(ordered: true, items: items));
        continue;
      }

      if (_isTableStart(lines, index)) {
        final rows = <List<String>>[];
        rows.add(_splitTableRow(lines[index]));
        index += 2;
        while (index < lines.length && lines[index].trim().contains('|')) {
          rows.add(_splitTableRow(lines[index]));
          index++;
        }
        blocks.add(_TableBlock(rows));
        continue;
      }

      final paragraph = <String>[];
      while (index < lines.length && lines[index].trim().isNotEmpty) {
        final value = lines[index].trim();
        if (_startsBlock(value) && paragraph.isNotEmpty) {
          break;
        }
        paragraph.add(value);
        index++;
      }
      blocks.add(_ParagraphBlock(paragraph.join(' ')));
    }

    return blocks;
  }

  bool _startsBlock(String line) {
    return line.startsWith('#') ||
        line.startsWith('>') ||
        line.startsWith('```') ||
        line == r'$$' ||
        _isListLine(line, ordered: false) ||
        _isListLine(line, ordered: true);
  }

  bool _isListLine(String line, {required bool ordered}) {
    final pattern = ordered ? RegExp(r'^\d+[.)]\s+') : RegExp(r'^[-*+]\s+');
    return pattern.hasMatch(line);
  }

  bool _isTableStart(List<String> lines, int index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    final header = lines[index].trim();
    final separator = lines[index + 1].trim();
    return header.contains('|') &&
        RegExp(
          r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$',
        ).hasMatch(separator);
  }

  List<String> _splitTableRow(String line) {
    var value = line.trim();
    if (value.startsWith('|')) {
      value = value.substring(1);
    }
    if (value.endsWith('|')) {
      value = value.substring(0, value.length - 1);
    }
    return value.split('|').map((cell) => cell.trim()).toList();
  }
}
