import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
// Import the pure highlighter directly. The package's public barrel also exports
// CodeEditor, which depends on native clipboard plugins that are not used here.
// ignore: implementation_imports
import 'package:syntax_highlight/src/highlighter.dart';

import '../../l10n/l10n.dart';
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

const _codeTextStyle = TextStyle(fontSize: 14, height: 22 / 14);
const _copySvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
  <rect x="8" y="8" width="12" height="12" rx="2" />
  <path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" />
</svg>
''';
const _checkSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="m5 12 4 4L19 6" />
</svg>
''';

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
  final ScrollController _scrollController = ScrollController();
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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      key: const ValueKey('markdown-code-block-card'),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('markdown-code-block-header'),
            height: 38,
            padding: const EdgeInsets.only(left: 18, right: 3),
            decoration: BoxDecoration(
              color: colors.surfaceHover,
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Text(
                  displayLanguage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSubtle,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  key: const ValueKey('markdown-code-copy-button'),
                  width: 32,
                  height: 32,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _copyCode,
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: const Color(0x08000000),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: Center(
                        child: Semantics(
                          button: true,
                          label: _copied
                              ? l10n(context).coreCodeCopied
                              : l10n(context).coreCodeCopy,
                          child: SvgPicture.string(
                            _copied ? _checkSvg : _copySvg,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              colors.textSubtle,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  key: const ValueKey('markdown-code-scroll-view'),
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                  child: highlightLanguage == null
                      ? _PlainCodeText(
                          code: widget.code,
                          color: colors.textMuted,
                        )
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
                            return Text.rich(
                              highlighter.highlight(widget.code),
                            );
                          },
                        ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 0,
                height: 14,
                child: _CodeScrollbar(controller: _scrollController),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeScrollbar extends StatefulWidget {
  const _CodeScrollbar({required this.controller});

  final ScrollController controller;

  @override
  State<_CodeScrollbar> createState() => _CodeScrollbarState();
}

class _CodeScrollbarState extends State<_CodeScrollbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final CurvedAnimation _expansion = CurvedAnimation(
    parent: _expandController,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeOut,
  );

  bool _hovered = false;
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartOffset = 0;

  void _syncExpansion() {
    if (_hovered || _dragging) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  bool get _canScroll {
    final controller = widget.controller;
    return controller.hasClients &&
        controller.position.hasContentDimensions &&
        controller.position.maxScrollExtent > 0;
  }

  void _startDrag(DragStartDetails details) {
    if (!_canScroll) {
      return;
    }
    _dragging = true;
    _dragStartX = details.localPosition.dx;
    _dragStartOffset = widget.controller.position.pixels;
    _syncExpansion();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging || !_canScroll) {
      return;
    }
    final width = context.size?.width ?? 0;
    final position = widget.controller.position;
    final thumbWidth = _thumbWidth(width, position);
    final thumbTravel = width - thumbWidth;
    if (thumbTravel <= 0) {
      return;
    }
    final delta = details.localPosition.dx - _dragStartX;
    final offset =
        _dragStartOffset + delta * position.maxScrollExtent / thumbTravel;
    position.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    _syncExpansion();
  }

  void _cancelDrag() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    _syncExpansion();
  }

  @override
  void dispose() {
    _expansion.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      key: const ValueKey('markdown-code-scrollbar'),
      onEnter: (_) {
        _hovered = true;
        _syncExpansion();
      },
      onExit: (_) {
        _hovered = false;
        _syncExpansion();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _startDrag,
        onHorizontalDragUpdate: _updateDrag,
        onHorizontalDragEnd: _endDrag,
        onHorizontalDragCancel: _cancelDrag,
        child: CustomPaint(
          painter: _CodeScrollbarPainter(
            controller: widget.controller,
            expansion: _expansion,
            idleColor: isDark
                ? const Color(0x3DFFFFFF)
                : const Color(0x2E000000),
            activeColor: isDark
                ? const Color(0xA6FFFFFF)
                : const Color(0x8C000000),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

double _thumbWidth(double trackWidth, ScrollPosition position) {
  final contentWidth = position.viewportDimension + position.maxScrollExtent;
  if (trackWidth <= 0 || contentWidth <= 0) {
    return 0;
  }
  return math.min(
    trackWidth,
    math.max(24, trackWidth * position.viewportDimension / contentWidth),
  );
}

class _CodeScrollbarPainter extends CustomPainter {
  _CodeScrollbarPainter({
    required this.controller,
    required this.expansion,
    required this.idleColor,
    required this.activeColor,
  }) : super(repaint: Listenable.merge([controller, expansion]));

  final ScrollController controller;
  final Animation<double> expansion;
  final Color idleColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }

    final thumbWidth = _thumbWidth(size.width, position);
    final thumbTravel = size.width - thumbWidth;
    final progress = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final expansionValue = expansion.value;
    final height = 4 + 6 * expansionValue;
    final baseline = size.height - 5;
    final rect = Rect.fromLTRB(
      thumbTravel * progress,
      baseline - height,
      thumbTravel * progress + thumbWidth,
      baseline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
      Paint()..color = Color.lerp(idleColor, activeColor, expansionValue)!,
    );
  }

  @override
  bool shouldRepaint(_CodeScrollbarPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.expansion != expansion ||
        oldDelegate.idleColor != idleColor ||
        oldDelegate.activeColor != activeColor;
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
