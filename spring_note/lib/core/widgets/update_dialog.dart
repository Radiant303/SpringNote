import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../l10n/l10n.dart';
import '../services/update_check_service.dart';
import '../theme/app_theme.dart';
import 'spring_tree.dart';
import 'spring_markdown.dart';

Future<void> showAppUpdateDialog({
  required BuildContext context,
  required UpdateCheckService updateCheckService,
  required String currentVersion,
  required AppUpdateInfo latest,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (context) {
      return AppUpdateDialog(
        updateCheckService: updateCheckService,
        currentVersion: currentVersion,
        latest: latest,
      );
    },
  );
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.updateCheckService,
    required this.currentVersion,
    required this.latest,
  });

  final UpdateCheckService updateCheckService;
  final String currentVersion;
  final AppUpdateInfo latest;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  UpdateInstallProgress? _progress;
  String? _errorMessage;
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = AppTheme.colors(context);
    return Dialog(
      backgroundColor: AppTheme.dialogSurface(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n(context).coreUpdateDialogTitle,
                    style: textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _installing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _UpdateMetaPill(
                    label: l10n(context).coreUpdateCurrentVersionLabel,
                    value: widget.currentVersion,
                  ),
                  _UpdateMetaPill(
                    label: l10n(context).coreUpdateLatestVersionLabel,
                    value: widget.latest.version,
                  ),
                  _UpdateMetaPill(
                    label: l10n(context).coreUpdateChangeTimeLabel,
                    value: widget.latest.changeTime.isEmpty
                        ? l10n(context).coreUpdateChangeTimeNotProvided
                        : widget.latest.changeTime,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                l10n(context).coreUpdateChangelogTitle,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.continuousBoxDecoration(
                    color: colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child:
                          widget.latest.changelogLoadFailed ||
                              widget.latest.changelog.trim().isEmpty
                          ? Text(
                              widget.latest.changelogLoadFailed
                                  ? l10n(context).coreUpdateChangelogLoadFailed
                                  : l10n(context).coreUpdateChangelogEmpty,
                              style: textTheme.bodyLarge?.copyWith(
                                color: springMarkdownTextColor(context),
                                fontSize: 14,
                                height: 1.55,
                              ),
                            )
                          : DefaultTextStyle.merge(
                              style: textTheme.bodyLarge?.copyWith(
                                color: springMarkdownTextColor(context),
                                fontSize: 14,
                                height: 1.55,
                              ),
                              child: GptMarkdownTheme(
                                gptThemeData: springMarkdownThemeData(
                                  context,
                                  GptMarkdownTheme.of(context),
                                ),
                                child: GptMarkdown(
                                  prepareSpringMarkdownText(
                                    widget.latest.changelog,
                                  ),
                                  followLinkColor: true,
                                  useDollarSignsForLatex: true,
                                  latexBuilder: springMarkdownLatexBuilder,
                                  components: springMarkdownComponents,
                                  inlineComponents:
                                      springMarkdownInlineComponents,
                                  unOrderedListBuilder:
                                      springMarkdownUnorderedListBuilder,
                                  tableBuilder: springMarkdownTableBuilder,
                                  imageBuilder: (context, url, width, height) =>
                                      SpringMarkdownImage(
                                        url: url,
                                        width: width,
                                        height: height,
                                        localImageBasePaths: const [],
                                      ),
                                  codeBuilder: buildSpringCodeBlock,
                                  style: textTheme.bodyLarge?.copyWith(
                                    color: springMarkdownTextColor(context),
                                    fontSize: 14,
                                    height: 1.55,
                                  ),
                                  onLinkTap: openSpringMarkdownLink,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_installing || _errorMessage != null) ...[
                _UpdateInstallStatus(
                  progress: _progress,
                  errorMessage: _errorMessage,
                ),
                const SizedBox(height: 12),
              ],
              _UpdateActionButton(
                fileName: widget.latest.installerName,
                installing: _installing,
                onTap: _installing ? null : _installUpdate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _installUpdate() async {
    setState(() {
      _installing = true;
      _errorMessage = null;
      _progress = null;
    });

    try {
      await widget.updateCheckService.installUpdate(
        widget.latest,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _progress = progress);
        },
      );
    } on UpdateInstallException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installing = false;
        _errorMessage = _localizedUpdateInstallError(context, error);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installing = false;
        _errorMessage = l10n(context).coreUpdateLaunchFailed;
      });
    }
  }
}

/// 把 [UpdateInstallException] 映射为当前语言的用户可见提示。
String _localizedUpdateInstallError(
  BuildContext context,
  UpdateInstallException error,
) {
  final strings = l10n(context);
  final detail = error.detail;
  final hasDetail = detail != null && detail.isNotEmpty;
  return switch (error.code) {
    UpdateInstallErrorCode.unsupportedPlatform =>
      strings.coreUpdateErrorUnsupportedPlatform,
    UpdateInstallErrorCode.updaterMissing =>
      strings.coreUpdateErrorUpdaterMissing,
    UpdateInstallErrorCode.downloadFailed =>
      hasDetail
          ? strings.coreUpdateErrorDownloadFailed(detail)
          : strings.coreUpdateErrorDownloadFailedRetry,
    UpdateInstallErrorCode.downloadTimeout =>
      strings.coreUpdateErrorDownloadTimeout,
    UpdateInstallErrorCode.networkUnavailable =>
      strings.coreUpdateErrorNetworkUnavailable,
    UpdateInstallErrorCode.downloadFailedRetry =>
      strings.coreUpdateErrorDownloadFailedRetry,
    UpdateInstallErrorCode.checksumFailed =>
      strings.coreUpdateErrorChecksumFailed,
    UpdateInstallErrorCode.checksumInfoUnreadable =>
      strings.coreUpdateErrorChecksumUnreadable,
    UpdateInstallErrorCode.checksumInfoMissing =>
      strings.coreUpdateErrorChecksumMissing,
    UpdateInstallErrorCode.macUpdateFailed =>
      hasDetail ? detail : strings.coreUpdateErrorMacFailed,
    UpdateInstallErrorCode.macUpdateNotFound =>
      hasDetail ? detail : strings.coreUpdateErrorMacNotFound,
    UpdateInstallErrorCode.macUpdateDismissed =>
      strings.coreUpdateErrorMacDismissed,
    UpdateInstallErrorCode.macUpdateInterrupted =>
      strings.coreUpdateErrorMacInterrupted,
    UpdateInstallErrorCode.macUpdateLaunchFailed =>
      hasDetail ? detail : strings.coreUpdateErrorMacLaunchFailed,
  };
}

class _UpdateInstallStatus extends StatelessWidget {
  const _UpdateInstallStatus({
    required this.progress,
    required this.errorMessage,
  });

  final UpdateInstallProgress? progress;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final error = errorMessage;
    if (error != null) {
      return _StatusBand(
        icon: Icons.error_outline_rounded,
        text: error,
        color: dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
        background: dark ? const Color(0xFF3B1119) : const Color(0xFFFEF2F2),
      );
    }

    final current = progress;
    final text = switch (current?.stage) {
      UpdateInstallStage.preparing => l10n(context).coreUpdatePreparing,
      UpdateInstallStage.downloading => _downloadText(context, current),
      UpdateInstallStage.verifying => l10n(context).coreUpdateVerifying,
      UpdateInstallStage.extracting => _extractingText(context, current),
      UpdateInstallStage.installing => l10n(context).coreUpdateInstalling,
      UpdateInstallStage.launching =>
        Platform.isWindows
            ? l10n(context).coreUpdateLaunchingWindows
            : l10n(context).coreUpdateLaunching,
      null => l10n(context).coreUpdatePreparing,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBand(
          icon: Icons.downloading_rounded,
          text: text,
          color: colors.text,
          background: colors.surfaceMuted,
        ),
        if (current?.stage == UpdateInstallStage.downloading ||
            current?.stage == UpdateInstallStage.extracting) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: current?.fraction,
            minHeight: 5,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: colors.surfacePressed,
            color: colors.text,
          ),
        ],
      ],
    );
  }

  String _downloadText(BuildContext context, UpdateInstallProgress? progress) {
    final received = _formatBytes(progress?.receivedBytes ?? 0);
    final total = progress?.totalBytes;
    if (total == null || total <= 0) {
      return l10n(context).coreUpdateDownloading(received);
    }
    return l10n(
      context,
    ).coreUpdateDownloadingProgress(received, _formatBytes(total));
  }

  String _extractingText(
    BuildContext context,
    UpdateInstallProgress? progress,
  ) {
    final fraction = progress?.fraction;
    if (fraction == null) {
      return l10n(context).coreUpdateExtracting;
    }
    final percent = (fraction * 100).clamp(0, 100).toStringAsFixed(0);
    return l10n(context).coreUpdateExtractingProgress(percent);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _StatusBand extends StatelessWidget {
  const _StatusBand({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: AppTheme.continuousBoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UpdateDownloadIcon extends StatelessWidget {
  const UpdateDownloadIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _UpdateDownloadIconPainter(color: color),
    );
  }
}

class _UpdateDownloadIconPainter extends CustomPainter {
  const _UpdateDownloadIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    canvas.drawLine(p(12, 3), p(12, 15), paint);
    canvas.drawLine(p(7, 10), p(12, 15), paint);
    canvas.drawLine(p(17, 10), p(12, 15), paint);
    canvas.drawPath(
      Path()
        ..moveTo(5 * sx, 17 * sy)
        ..lineTo(5 * sx, 19 * sy)
        ..cubicTo(5 * sx, 20.1 * sy, 5.9 * sx, 21 * sy, 7 * sx, 21 * sy)
        ..lineTo(17 * sx, 21 * sy)
        ..cubicTo(18.1 * sx, 21 * sy, 19 * sx, 20.1 * sy, 19 * sx, 19 * sy)
        ..lineTo(19 * sx, 17 * sy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _UpdateDownloadIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _UpdateMetaPill extends StatelessWidget {
  const _UpdateMetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: AppTheme.continuousBoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label ',
          style: TextStyle(color: colors.textSubtle),
          children: [
            TextSpan(
              text: value,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontSize: 12, height: 1),
      ),
    );
  }
}

class _UpdateActionButton extends StatefulWidget {
  const _UpdateActionButton({
    required this.fileName,
    required this.installing,
    required this.onTap,
  });

  final String fileName;
  final bool installing;
  final VoidCallback? onTap;

  @override
  State<_UpdateActionButton> createState() => _UpdateActionButtonState();
}

class _UpdateActionButtonState extends State<_UpdateActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final enabled = widget.onTap != null;
    final active = enabled && _hovered;
    final background = active ? colors.textMuted : colors.text;
    final foreground = colors.onAccent;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (enabled) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: AppTheme.continuousBoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (widget.installing)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                UpdateDownloadIcon(size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.installing
                      ? l10n(context).coreUpdateButtonPreparing
                      : l10n(context).coreUpdateButtonInstallNow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                widget.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.72),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
