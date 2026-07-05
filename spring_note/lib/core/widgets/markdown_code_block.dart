import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Import the pure highlighter directly. The package's public barrel also exports
// CodeEditor, which depends on native clipboard plugins that are not used here.
// ignore: implementation_imports
import 'package:syntax_highlight/src/highlighter.dart';

import '../theme/app_theme.dart';

const _supportedHighlightLanguages = <String>[
  'css',
  'dart',
  'go',
  'html',
  'java',
  'javascript',
  'json',
  'kotlin',
  'python',
  'rust',
  'serverpod_protocol',
  'sql',
  'swift',
  'typescript',
  'yaml',
];

const _languageAliases = <String, String>{
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rs': 'rust',
  'yml': 'yaml',
};

const _codeTextStyle = TextStyle(fontSize: 13, height: 1.4);

final Future<HighlighterTheme> _lightHighlightThemeFuture = _loadHighlightTheme(
  Brightness.light,
);
final Future<HighlighterTheme> _darkHighlightThemeFuture = _loadHighlightTheme(
  Brightness.dark,
);

Future<HighlighterTheme> _loadHighlightTheme(Brightness brightness) async {
  await Highlighter.initialize(_supportedHighlightLanguages);
  final isDark = brightness == Brightness.dark;
  return HighlighterTheme.loadFromAssets(
    isDark
        ? const [
            'packages/syntax_highlight/themes/dark_vs.json',
            'packages/syntax_highlight/themes/dark_plus.json',
          ]
        : const [
            'packages/syntax_highlight/themes/light_vs.json',
            'packages/syntax_highlight/themes/light_plus.json',
          ],
    _codeTextStyle.copyWith(
      color: isDark ? SpringThemeColors.dark.textMuted : AppTheme.textMuted,
    ),
  );
}

class MarkdownCodeBlock extends StatefulWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.language,
    required this.code,
  });

  final String language;
  final String code;

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawLanguage = widget.language.trim();
    final displayLanguage = rawLanguage.isEmpty ? 'code' : rawLanguage;
    final highlightLanguage = _normalizeLanguage(rawLanguage);
    final colors = AppTheme.colors(context);
    final highlightThemeFuture = Theme.of(context).brightness == Brightness.dark
        ? _darkHighlightThemeFuture
        : _lightHighlightThemeFuture;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Text(
                  displayLanguage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copyCode,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSubtle,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 13,
                  ),
                  label: Text(_copied ? '已复制' : '复制'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: highlightLanguage == null
                ? _PlainCodeText(code: widget.code, color: colors.textMuted)
                : FutureBuilder<HighlighterTheme>(
                    future: highlightThemeFuture,
                    builder: (context, snapshot) {
                      final theme = snapshot.data;
                      if (theme == null) {
                        return _PlainCodeText(
                          code: widget.code,
                          color: colors.textMuted,
                        );
                      }

                      final highlighter = Highlighter(
                        language: highlightLanguage,
                        theme: theme,
                      );
                      return Text.rich(highlighter.highlight(widget.code));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlainCodeText extends StatelessWidget {
  const _PlainCodeText({required this.code, required this.color});

  final String code;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(code, style: _codeTextStyle.copyWith(color: color));
  }
}

String? _normalizeLanguage(String language) {
  final normalized = language.trim().toLowerCase().split(RegExp(r'\s+')).first;
  if (normalized.isEmpty) {
    return null;
  }
  final aliased = _languageAliases[normalized] ?? normalized;
  return _supportedHighlightLanguages.contains(aliased) ? aliased : null;
}
