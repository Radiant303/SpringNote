import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../theme/app_theme.dart';
import 'markdown_local_image_stub.dart'
    if (dart.library.io) 'markdown_local_image_io.dart';

GptMarkdownThemeData springMarkdownThemeData(
  BuildContext context,
  GptMarkdownThemeData base,
) {
  final colors = AppTheme.colors(context);
  final headingColor = Theme.of(context).brightness == Brightness.dark
      ? colors.text
      : const Color(0xFF333333);
  final h1FontSize = base.h1?.fontSize ?? 32;
  return base.copyWith(
    h1: _headingStyle(
      base.h1,
      color: headingColor,
      fontSize: h1FontSize,
      fontWeight: FontWeight.w700,
      height: 0.92,
    ),
    h2: _headingStyle(
      base.h2,
      color: headingColor,
      fontSize: h1FontSize * 0.75,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
    h3: _headingStyle(
      base.h3,
      color: headingColor,
      fontSize: h1FontSize * 0.625,
      fontWeight: FontWeight.w700,
      height: 1.26,
    ),
    h4: _headingStyle(
      base.h4,
      color: headingColor,
      fontSize: h1FontSize * 0.50,
      fontWeight: FontWeight.w700,
      height: 1.30,
    ),
    h5: _headingStyle(
      base.h5,
      color: headingColor,
      fontSize: h1FontSize * 0.438,
      fontWeight: FontWeight.w700,
      height: 1.34,
    ),
    h6: _headingStyle(
      base.h6,
      color: headingColor,
      fontSize: h1FontSize * 0.425,
      fontWeight: FontWeight.w700,
      height: 1.38,
    ),
    hrLinePadding: const EdgeInsets.only(bottom: 16),
  );
}

final _springTaskCheckboxMd = _SpringTaskCheckboxMd();
final _springNewLines = _SpringNewLines();
final _springInlineCodeMd = _SpringInlineCodeMd();

final List<MarkdownComponent> springMarkdownComponents = [
  for (final component in MarkdownComponent.globalComponents)
    if (component is CheckBoxMd)
      _springTaskCheckboxMd
    else if (component is NewLines)
      _springNewLines
    else if (component is HighlightedText)
      _springInlineCodeMd
    else
      component,
];

final List<MarkdownComponent> springMarkdownInlineComponents = [
  for (final component in MarkdownComponent.inlineComponents)
    if (component is HighlightedText) _springInlineCodeMd else component,
];

Widget springMarkdownUnorderedListBuilder(
  BuildContext context,
  Widget child,
  GptMarkdownConfig config,
) {
  final isTaskItem =
      child is MdWidget && _springTaskCheckboxMd.exp.hasMatch(child.exp.trim());
  final style = config.style ?? DefaultTextStyle.of(context).style;
  return UnorderedListView(
    bulletColor: style.color,
    padding: 7,
    spacing: isTaskItem ? 0 : 10,
    bulletSize: isTaskItem ? 0 : 0.3 * (style.fontSize ?? kDefaultFontSize),
    textDirection: config.textDirection,
    child: child,
  );
}

Widget springMarkdownLatexBuilder(
  BuildContext context,
  String tex,
  TextStyle textStyle,
  bool inline,
) {
  final colors = AppTheme.colors(context);
  final defaultStyle = DefaultTextStyle.of(context).style;
  final baseStyle = defaultStyle
      .merge(textStyle)
      .copyWith(color: textStyle.color ?? defaultStyle.color ?? colors.text);
  final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
  if (inline) {
    return _SpringInlineMath(tex: tex, style: baseStyle, fontSize: fontSize);
  }
  return _SpringDisplayMath(
    tex: tex,
    style: baseStyle.copyWith(fontSize: fontSize * 1.08),
    padding: EdgeInsets.symmetric(vertical: fontSize * 1.12),
  );
}

String prepareSpringMarkdownText(String markdown) {
  return _markdownWithRenderableImageUris(
    normalizeSpringMarkdownText(markdown),
  );
}

String normalizeSpringMarkdownText(String markdown) {
  if (markdown.isEmpty) {
    return markdown;
  }

  final lines = _normalizeHeadingLeadingBlankLines(
    markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'),
  );
  final buffer = StringBuffer();
  var inFence = false;
  String? fenceCharacter;
  var fenceLength = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final headingLevelBeforeFenceUpdate = inFence
        ? null
        : _atxHeadingLevel(line);
    if (headingLevelBeforeFenceUpdate != null &&
        headingLevelBeforeFenceUpdate > 1 &&
        _needsLeadingHeadingGap(lines, index)) {
      buffer.write('\n');
    }

    buffer.write(line);
    if (index < lines.length - 1) {
      buffer.write('\n');
    }

    final fenceMatch = _fencedCodeBlockPattern.firstMatch(line);
    if (fenceMatch != null) {
      final fence = fenceMatch.group(1)!;
      final currentFenceCharacter = fence[0];
      if (!inFence) {
        inFence = true;
        fenceCharacter = currentFenceCharacter;
        fenceLength = fence.length;
      } else if (currentFenceCharacter == fenceCharacter &&
          fence.length >= fenceLength) {
        inFence = false;
        fenceCharacter = null;
        fenceLength = 0;
      }
    }

    final headingLevel = _atxHeadingLevel(line);
    if (inFence || index >= lines.length - 1 || headingLevel == null) {
      continue;
    }

    var nextContentIndex = index + 1;
    while (nextContentIndex < lines.length &&
        lines[nextContentIndex].trim().isEmpty) {
      nextContentIndex++;
    }

    if (nextContentIndex >= lines.length) {
      continue;
    }

    final blankRun = nextContentIndex - index - 1;
    final nextLineIsHeading = _isAtxHeading(lines[nextContentIndex]);
    final structuralGap = headingLevel > 1 || nextLineIsHeading ? 1 : 0;
    final outputGap = structuralGap + (blankRun - 2).clamp(0, blankRun);

    for (var gapIndex = 0; gapIndex < outputGap; gapIndex++) {
      buffer.write('\n');
    }
    if (blankRun > 0) {
      index = nextContentIndex - 1;
    }
  }

  return _normalizeMediaBlankLines(
    _normalizeImagesAsMediaBlocks(buffer.toString()),
  );
}

class SpringMarkdownImage extends StatelessWidget {
  const SpringMarkdownImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.localImageBasePaths,
  });

  final String url;
  final double? width;
  final double? height;
  final Iterable<String?> localImageBasePaths;

  @override
  Widget build(BuildContext context) {
    for (final basePath in localImageBasePaths) {
      final localImage = buildMarkdownLocalImage(
        url: url,
        baseDirectoryPath: basePath,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const _ImageFallbackIcon(),
      );
      if (localImage != null) {
        return _MarkdownImageFrame(child: localImage);
      }
    }

    final Widget image;
    if (_isLocalReference(url)) {
      image = const _ImageFallbackIcon();
    } else {
      image = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const _ImageFallbackIcon(),
      );
    }

    return _MarkdownImageFrame(child: image);
  }
}

class _MarkdownImageFrame extends StatelessWidget {
  const _MarkdownImageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fontSize =
        DefaultTextStyle.of(context).style.fontSize ?? kDefaultFontSize;
    return Container(
      key: const ValueKey('markdown-image-frame'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.72),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 520),
          child: child,
        ),
      ),
    );
  }
}

class _ImageFallbackIcon extends StatelessWidget {
  const _ImageFallbackIcon();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      width: 120,
      height: 88,
      alignment: Alignment.center,
      color: colors.surfaceMuted,
      child: Icon(Icons.image_not_supported_outlined, color: colors.textSubtle),
    );
  }
}

class _SpringDisplayMath extends StatelessWidget {
  const _SpringDisplayMath({
    required this.tex,
    required this.style,
    required this.padding,
  });

  final String tex;
  final TextStyle style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('markdown-display-math'),
      width: double.infinity,
      padding: padding,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _SpringMath(
          tex: tex,
          style: style,
          mathStyle: MathStyle.display,
        ),
      ),
    );
  }
}

class _SpringInlineMath extends StatelessWidget {
  const _SpringInlineMath({
    required this.tex,
    required this.style,
    required this.fontSize,
  });

  final String tex;
  final TextStyle style;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return _SpringMath(
      key: const ValueKey('markdown-inline-math'),
      tex: tex,
      style: style.copyWith(fontSize: fontSize),
      mathStyle: MathStyle.text,
    );
  }
}

class _SpringMath extends StatelessWidget {
  const _SpringMath({
    super.key,
    required this.tex,
    required this.style,
    required this.mathStyle,
  });

  final String tex;
  final TextStyle style;
  final MathStyle mathStyle;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      tex,
      textStyle: style,
      mathStyle: mathStyle,
      textScaleFactor: 1,
      settings: const TexParserSettings(strict: Strict.ignore),
      onErrorFallback: (error) => Text(tex, style: style),
    );
  }
}

class _SpringTaskCheckboxMd extends CheckBoxMd {
  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final checked = match?.group(1) == 'x';
    final content = match?.group(2) ?? '';
    final fontSize =
        config.style?.fontSize ??
        DefaultTextStyle.of(context).style.fontSize ??
        kDefaultFontSize;
    return _SpringTaskCheckboxRow(
      checked: checked,
      textDirection: config.textDirection,
      checkboxSize: fontSize * 0.8,
      topPadding: fontSize * 0.36,
      child: MdWidget(context, content, false, config: config),
    );
  }
}

class _SpringNewLines extends NewLines {
  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final style = config.style ?? DefaultTextStyle.of(context).style;
    return TextSpan(
      text: text,
      style: TextStyle(
        fontSize: style.fontSize ?? kDefaultFontSize,
        height: 1.15,
        color: style.color,
      ),
    );
  }
}

class _SpringInlineCodeMd extends HighlightedText {
  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final code = match?[1] ?? '';
    final colors = AppTheme.colors(context);
    final baseStyle = config.style ?? DefaultTextStyle.of(context).style;
    final fontSize = baseStyle.fontSize ?? kDefaultFontSize;
    final textColor = baseStyle.color ?? colors.text;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        key: const ValueKey('markdown-inline-code'),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isDark
              ? colors.surfaceMuted.withValues(alpha: 0.45)
              : const Color(0xFFF3F4F4),
          border: Border.all(
            color: isDark
                ? colors.border.withValues(alpha: 0.75)
                : const Color(0xFFE7EAED),
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          code,
          style: baseStyle.copyWith(
            color: textColor,
            fontSize: fontSize * 0.9,
            height: 1.08,
            fontWeight: baseStyle.fontWeight,
            fontFamily: 'monospace',
            background: null,
          ),
        ),
      ),
    );
  }
}

class _SpringTaskCheckboxRow extends StatelessWidget {
  const _SpringTaskCheckboxRow({
    required this.checked,
    required this.textDirection,
    required this.checkboxSize,
    required this.topPadding,
    required this.child,
  });

  final bool checked;
  final TextDirection textDirection;
  final double checkboxSize;
  final double topPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(top: topPadding, end: 8),
            child: _SpringTaskCheckboxIcon(
              checked: checked,
              size: checkboxSize,
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class _SpringTaskCheckboxIcon extends StatelessWidget {
  const _SpringTaskCheckboxIcon({required this.checked, required this.size});

  static const _blue = Color(0xFF1677FF);
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(
        checked ? 'markdown-task-checkbox-checked' : 'markdown-task-checkbox',
      ),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? _blue : Colors.transparent,
        border: Border.all(color: _blue, width: 1.1),
        borderRadius: BorderRadius.circular(2.2),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: size * 0.78, color: Colors.white)
          : null,
    );
  }
}

TextStyle _headingStyle(
  TextStyle? base, {
  required Color color,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
}) {
  return (base ?? const TextStyle()).copyWith(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
  );
}

final _atxHeadingPattern = RegExp(
  r'^[ \t]{0,3}#{1,6}(?!#)(?:[ \t]+.*|[ \t]*)$',
);
final _fencedCodeBlockPattern = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})');
final _displayMathOpeningLinePattern = RegExp(r'\\\[');
final _displayMathClosingLinePattern = RegExp(r'\\\]\s*$');
final _markdownImagePattern = RegExp(r'!\[[^\[\]]*\]\([^\s]*\)');
final _standaloneImageLinePattern = RegExp(
  r'^[ \t]{0,3}!\[[^\[\]]*\]\([^\s]*\)\s*$',
);

bool _isAtxHeading(String line) {
  return _atxHeadingPattern.hasMatch(line);
}

List<String> _normalizeHeadingLeadingBlankLines(List<String> lines) {
  final normalized = <String>[];
  var inFence = false;
  String? fenceCharacter;
  var fenceLength = 0;

  for (final line in lines) {
    final headingLevel = inFence ? null : _atxHeadingLevel(line);
    if (headingLevel != null && normalized.isNotEmpty) {
      final blankRun = _removeTrailingBlankLines(normalized);
      final structuralGap = headingLevel > 1 && normalized.isNotEmpty ? 1 : 0;
      final outputGap = structuralGap + (blankRun - 2).clamp(0, blankRun);
      for (var index = 0; index < outputGap; index++) {
        normalized.add('');
      }
    }

    normalized.add(line);

    final fenceMatch = _fencedCodeBlockPattern.firstMatch(line);
    if (fenceMatch == null) {
      continue;
    }
    final fence = fenceMatch.group(1)!;
    final currentFenceCharacter = fence[0];
    if (!inFence) {
      inFence = true;
      fenceCharacter = currentFenceCharacter;
      fenceLength = fence.length;
    } else if (currentFenceCharacter == fenceCharacter &&
        fence.length >= fenceLength) {
      inFence = false;
      fenceCharacter = null;
      fenceLength = 0;
    }
  }

  return normalized;
}

int _removeTrailingBlankLines(List<String> lines) {
  var removed = 0;
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
    removed++;
  }
  return removed;
}

String _normalizeImagesAsMediaBlocks(String markdown) {
  final lines = markdown.split('\n');
  final normalized = <String>[];
  var inFence = false;
  String? fenceCharacter;
  var fenceLength = 0;

  for (final line in lines) {
    final fenceMatch = _fencedCodeBlockPattern.firstMatch(line);
    final splitLine = !inFence && fenceMatch == null
        ? _splitImagesAsMediaBlocks(line)
        : [line];
    normalized.addAll(splitLine);

    if (fenceMatch == null) {
      continue;
    }
    final fence = fenceMatch.group(1)!;
    final currentFenceCharacter = fence[0];
    if (!inFence) {
      inFence = true;
      fenceCharacter = currentFenceCharacter;
      fenceLength = fence.length;
    } else if (currentFenceCharacter == fenceCharacter &&
        fence.length >= fenceLength) {
      inFence = false;
      fenceCharacter = null;
      fenceLength = 0;
    }
  }

  return normalized.join('\n');
}

List<String> _splitImagesAsMediaBlocks(String line) {
  final matches = _markdownImagePattern.allMatches(line).toList();
  if (matches.isEmpty || _standaloneImageLinePattern.hasMatch(line)) {
    return [line];
  }

  final result = <String>[];
  var start = 0;
  for (final match in matches) {
    _addNonEmptyMediaSegment(result, line.substring(start, match.start));
    result.add(match.group(0)!);
    start = match.end;
  }
  _addNonEmptyMediaSegment(result, line.substring(start));

  return result.isEmpty ? [line] : result;
}

void _addNonEmptyMediaSegment(List<String> result, String value) {
  final trimmed = value.trim();
  if (trimmed.isNotEmpty) {
    result.add(trimmed);
  }
}

String _normalizeMediaBlankLines(String markdown) {
  final lines = markdown.split('\n');
  final normalized = <String>[];
  var inFence = false;
  var inDisplayMath = false;
  String? fenceCharacter;
  var fenceLength = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final isStandaloneImage =
        !inFence && _standaloneImageLinePattern.hasMatch(line);
    final opensDisplayMath =
        !inFence && _displayMathOpeningLinePattern.hasMatch(line);
    if ((opensDisplayMath || isStandaloneImage) && normalized.isNotEmpty) {
      _removeUpToTwoTrailingBlankLines(normalized);
    }
    normalized.add(line);

    final fenceMatch = _fencedCodeBlockPattern.firstMatch(line);
    if (fenceMatch != null) {
      final fence = fenceMatch.group(1)!;
      final currentFenceCharacter = fence[0];
      if (!inFence) {
        inFence = true;
        fenceCharacter = currentFenceCharacter;
        fenceLength = fence.length;
      } else if (currentFenceCharacter == fenceCharacter &&
          fence.length >= fenceLength) {
        inFence = false;
        fenceCharacter = null;
        fenceLength = 0;
      }
    }

    if (opensDisplayMath) {
      inDisplayMath = true;
    }
    final closesDisplayMath =
        !inFence &&
        inDisplayMath &&
        _displayMathClosingLinePattern.hasMatch(line);
    if (closesDisplayMath) {
      inDisplayMath = false;
    }

    if (!closesDisplayMath && !isStandaloneImage) {
      continue;
    }
    var skippedBlankLines = 0;
    while (skippedBlankLines < 2 &&
        index + 1 < lines.length &&
        lines[index + 1].trim().isEmpty) {
      index++;
      skippedBlankLines++;
    }
  }

  return normalized.join('\n');
}

void _removeUpToTwoTrailingBlankLines(List<String> lines) {
  var removed = 0;
  while (removed < 2 && lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
    removed++;
  }
}

bool _needsLeadingHeadingGap(List<String> lines, int index) {
  if (index <= 0) {
    return false;
  }
  return lines[index - 1].trim().isNotEmpty;
}

int? _atxHeadingLevel(String line) {
  if (!_atxHeadingPattern.hasMatch(line)) {
    return null;
  }
  final trimmed = line.trimLeft();
  var level = 0;
  while (level < trimmed.length && trimmed.codeUnitAt(level) == 0x23) {
    level++;
  }
  return level == 0 ? null : level;
}

String _markdownWithRenderableImageUris(String markdown) {
  final buffer = StringBuffer();
  var index = 0;

  while (index < markdown.length) {
    final imageStart = markdown.indexOf('![', index);
    if (imageStart < 0) {
      buffer.write(markdown.substring(index));
      break;
    }

    buffer.write(markdown.substring(index, imageStart));
    final altEnd = markdown.indexOf('](', imageStart + 2);
    if (altEnd < 0) {
      buffer.write(markdown.substring(imageStart));
      break;
    }
    final destinationStart = altEnd + 2;
    final destinationEnd = markdown.indexOf(')', destinationStart);
    if (destinationEnd < 0) {
      buffer.write(markdown.substring(imageStart));
      break;
    }

    final destination = markdown.substring(destinationStart, destinationEnd);
    buffer
      ..write(markdown.substring(imageStart, destinationStart))
      ..write(_renderableImageDestination(destination))
      ..write(')');
    index = destinationEnd + 1;
  }

  return buffer.toString();
}

String _renderableImageDestination(String destination) {
  final trimmed = destination.trim();
  if (trimmed.isEmpty || !_isLocalImageDestination(trimmed)) {
    return destination;
  }

  final decoded = _decodeImageDestination(trimmed);
  return Uri(path: decoded).toString();
}

String _decodeImageDestination(String value) {
  try {
    return Uri.decodeFull(value);
  } catch (_) {
    return value;
  }
}

bool _isLocalImageDestination(String value) {
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
    return true;
  }
  final uri = Uri.tryParse(value);
  return uri != null && !uri.hasScheme;
}

bool _isLocalReference(String value) {
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
    return true;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return false;
  }
  return uri.scheme == 'file' || !uri.hasScheme;
}
