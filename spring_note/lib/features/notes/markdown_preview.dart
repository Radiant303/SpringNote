import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/widgets/markdown_code_block.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.markdown});

  final String markdown;

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
            fontSize: 15,
            height: 1.65,
          ),
          child: GptMarkdown(
            markdown,
            followLinkColor: true,
            useDollarSignsForLatex: true,
            codeBuilder: (context, name, code, closed) =>
                MarkdownCodeBlock(language: name, code: code),
            style: textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF3A3A3A),
              fontSize: 15,
              height: 1.65,
            ),
            onLinkTap: (url, title) {},
          ),
        ),
      ),
    );
  }
}
