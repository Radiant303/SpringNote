import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/widgets/markdown_code_block.dart';
import 'markdown_local_image_stub.dart'
    if (dart.library.io) 'markdown_local_image_io.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    super.key,
    required this.markdown,
    this.localImageBasePath,
  });

  final String markdown;
  final String? localImageBasePath;

  @override
  Widget build(BuildContext context) {
    if (markdown.trim().isEmpty) {
      return Center(
        child: Text(
          '预览区域会随着 Markdown 源码实时刷新',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8A8A8A)),
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 56),
        child: DefaultTextStyle.merge(
          style: textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF3A3A3A),
            fontSize: 14,
            height: 1.55,
          ),
          child: GptMarkdown(
            markdown,
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
              color: const Color(0xFF3A3A3A),
              fontSize: 14,
              height: 1.55,
            ),
            onLinkTap: (url, title) {},
          ),
        ),
      ),
    );
  }
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
    return Container(
      width: 120,
      height: 88,
      alignment: Alignment.center,
      color: const Color(0xFFF5F5F5),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFF8A8A8A),
      ),
    );
  }
}
