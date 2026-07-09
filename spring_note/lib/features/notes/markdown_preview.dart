import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/markdown_code_block.dart';
import '../../core/widgets/spring_markdown.dart';

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
                  gptThemeData: springMarkdownThemeData(context, markdownTheme),
                  child: GptMarkdown(
                    prepareSpringMarkdownText(markdown),
                    followLinkColor: true,
                    useDollarSignsForLatex: true,
                    latexBuilder: springMarkdownLatexBuilder,
                    components: springMarkdownComponents,
                    inlineComponents: springMarkdownInlineComponents,
                    unOrderedListBuilder: springMarkdownUnorderedListBuilder,
                    codeBuilder: (context, name, code, closed) =>
                        MarkdownCodeBlock(language: name, code: code),
                    imageBuilder: (context, url, width, height) =>
                        SpringMarkdownImage(
                          url: url,
                          width: width,
                          height: height,
                          localImageBasePaths: [localImageBasePath],
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
