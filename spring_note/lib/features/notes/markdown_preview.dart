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
    this.padding = const EdgeInsets.fromLTRB(32, 32, 32, 56),
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
                child: GptMarkdown(
                  _markdownWithRenderableImageUris(markdown),
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
    );
  }
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
