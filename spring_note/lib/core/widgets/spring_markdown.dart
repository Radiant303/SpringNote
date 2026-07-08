import 'package:flutter/material.dart';
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

final List<MarkdownComponent> springMarkdownComponents = [
  for (final component in MarkdownComponent.globalComponents)
    if (component is CheckBoxMd) _springTaskCheckboxMd else component,
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

String prepareSpringMarkdownText(String markdown) {
  return _markdownWithRenderableImageUris(
    normalizeSpringMarkdownText(markdown),
  );
}

String normalizeSpringMarkdownText(String markdown) {
  if (markdown.isEmpty) {
    return markdown;
  }

  final lines = markdown
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
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

    final nextLineIsHeading = _isAtxHeading(lines[nextContentIndex]);
    final shouldKeepBlockGap = headingLevel > 1 || nextLineIsHeading;
    final hadBlockGap = nextContentIndex > index + 1;

    if (shouldKeepBlockGap) {
      if (!hadBlockGap) {
        buffer.write('\n');
      } else {
        index = nextContentIndex - 2;
      }
    } else if (hadBlockGap) {
      index = nextContentIndex - 1;
    }
  }

  return buffer.toString();
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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

bool _isAtxHeading(String line) {
  return _atxHeadingPattern.hasMatch(line);
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
