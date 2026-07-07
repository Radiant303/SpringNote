import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_code_block.dart';
import 'markdown_local_image_stub.dart'
    if (dart.library.io) 'markdown_local_image_io.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    super.key,
    required this.markdown,
    this.localImageBasePath,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(32, 20, 32, 56),
    this.maxContentWidth = 760,
  });

  final String markdown;
  final String? localImageBasePath;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    if (markdown.trim().isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Text(
              '预览区域会随着 Markdown 源码实时刷新',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle),
            ),
          ),
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final markdownTheme = GptMarkdownTheme.of(context);
    return SelectionArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: SizedBox(
              width: double.infinity,
              child: DefaultTextStyle.merge(
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.text,
                  fontSize: 14,
                  height: 1.55,
                ),
                child: GptMarkdownTheme(
                  gptThemeData: markdownTheme.copyWith(
                    h1: markdownTheme.h1?.copyWith(height: 0.92),
                    hrLinePadding: const EdgeInsets.only(bottom: 16),
                  ),
                  child: GptMarkdown(
                    _markdownForPreview(markdown),
                    followLinkColor: true,
                    useDollarSignsForLatex: true,
                    codeBuilder: (context, name, code, closed) =>
                        MarkdownCodeBlock(language: name, code: code),
                    imageBuilder: (context, url, width, height) =>
                        _MarkdownPreviewImage(
                          url: url,
                          width: width,
                          height: height,
                          localImageBasePath: localImageBasePath,
                        ),
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.text,
                      fontSize: 14,
                      height: 1.55,
                    ),
                    onLinkTap: (url, title) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _markdownForPreview(String markdown) {
  return _markdownWithRenderableImageUris(
    _normalizeAtxHeadingSpacing(markdown),
  );
}

String _normalizeAtxHeadingSpacing(String markdown) {
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

    if (inFence || index >= lines.length - 1 || !_isAtxHeading(line)) {
      continue;
    }

    var nextContentIndex = index + 1;
    while (nextContentIndex < lines.length &&
        lines[nextContentIndex].trim().isEmpty) {
      nextContentIndex++;
    }

    if (nextContentIndex > index + 1 && nextContentIndex < lines.length) {
      index = nextContentIndex - 1;
    }
  }

  return buffer.toString();
}

final _atxHeadingPattern = RegExp(
  r'^[ \t]{0,3}#{1,6}(?!#)(?:[ \t]+.*|[ \t]*)$',
);
final _fencedCodeBlockPattern = RegExp(r'^[ \t]{0,3}(`{3,}|~{3,})');

bool _isAtxHeading(String line) {
  return _atxHeadingPattern.hasMatch(line);
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

class _MarkdownPreviewImage extends StatelessWidget {
  const _MarkdownPreviewImage({
    required this.url,
    required this.width,
    required this.height,
    required this.localImageBasePath,
  });

  final String url;
  final double? width;
  final double? height;
  final String? localImageBasePath;

  @override
  Widget build(BuildContext context) {
    final localImage = buildMarkdownLocalImage(
      url: url,
      baseDirectoryPath: localImageBasePath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const _ImageFallbackIcon(),
    );
    final Widget image;
    if (localImage != null) {
      image = localImage;
    } else if (_isLocalReference(url)) {
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 520),
          child: image,
        ),
      ),
    );
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
