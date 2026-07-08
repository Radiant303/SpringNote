import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SpringNotePageScaffold extends StatelessWidget {
  const SpringNotePageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Material(
      color: colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1184),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 30, 48, 22),
                child: Row(
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    ...?actions,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class SpringNoteIconButton extends StatelessWidget {
  const SpringNoteIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: colors.textSubtle,
      style: IconButton.styleFrom(
        fixedSize: const Size(34, 34),
        minimumSize: const Size(34, 34),
        maximumSize: const Size(34, 34),
        backgroundColor: Colors.transparent,
        hoverColor: colors.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return button;
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = 24,
    this.backgroundColor = AppTheme.surface,
    this.withShadow = true,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color backgroundColor;
  final bool withShadow;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor == AppTheme.surface
            ? colors.surface
            : backgroundColor,
        border: Border.all(color: borderColor ?? colors.border),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: withShadow
            ? boxShadow ??
                  [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
            : null,
      ),
      child: child,
    );
  }
}
