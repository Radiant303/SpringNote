part of 'settings_page.dart';

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.updateCheckService});

  final UpdateCheckService updateCheckService;

  static const _websiteUrl = 'https://radiant303.github.io/SpringNote';
  static const _githubUrl = 'https://github.com/Radiant303/SpringNote';
  static const _licenseUrl =
      'https://github.com/Radiant303/SpringNote/blob/main/LICENSE';
  static const _qqGroupUrl = 'https://qm.qq.com/q/4gWWKvwhP2';
  static const _externalLinkService = ExternalLinkService();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Image.asset(
                  'windows/runner/resources/index.png',
                  width: 30,
                  height: 30,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SpringNote',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'AI 智能便签与日报生成工具',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
        _AboutListCard(
          rows: [
            const _PubspecVersionRow(),
            const _PlatformInfoRow(),
            _AboutListRow(
              icon: _AboutRowIconType.update,
              label: '检查更新',
              onTap: () => _checkForUpdates(context),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.globe,
              label: '官网',
              onTap: () => _externalLinkService.open(_websiteUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.github,
              label: 'GitHub',
              onTap: () => _externalLinkService.open(_githubUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.license,
              label: '许可证',
              onTap: () => _externalLinkService.open(_licenseUrl),
            ),
            _AboutListRow(
              icon: _AboutRowIconType.qq,
              label: '加入QQ群',
              onTap: () => _externalLinkService.open(_qqGroupUrl),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    final result = await updateCheckService.check(
      mode: UpdateCheckMode.userInitiated,
    );
    if (!context.mounted) {
      return;
    }
    messenger?.hideCurrentSnackBar();
    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        final latest = result.latest;
        if (latest == null) {
          messenger?.showSnackBar(const SnackBar(content: Text('暂时无法读取更新内容')));
          return;
        }
        await showAppUpdateDialog(
          context: context,
          updateCheckService: updateCheckService,
          currentVersion: result.currentVersion,
          latest: latest,
        );
      case UpdateCheckStatus.idle:
        messenger?.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      case UpdateCheckStatus.failed:
        messenger?.showSnackBar(
          const SnackBar(content: Text('暂时无法检查更新，请稍后重试')),
        );
    }
  }
}

class _AboutListCard extends StatelessWidget {
  const _AboutListCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Row(
              children: [
                Text('关于', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  rows[index],
                  if (index != rows.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 34),
                      child: Divider(height: 1, color: colors.divider),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AboutRowIconType { code, system, update, globe, github, license, qq }

class _PubspecVersionRow extends StatelessWidget {
  const _PubspecVersionRow();

  static Future<String> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version.trim().isEmpty
          ? '1.0.0'
          : packageInfo.version.trim();
    } catch (_) {
      return '1.0.0';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadVersion(),
      builder: (context, snapshot) {
        return _AboutListRow(
          icon: _AboutRowIconType.code,
          label: '版本',
          value: snapshot.data ?? '1.0.0',
        );
      },
    );
  }
}

class _PlatformInfoRow extends StatelessWidget {
  const _PlatformInfoRow();

  String get _platformLabel {
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    if (Platform.isMacOS) {
      return 'Mac';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    return '未知';
  }

  @override
  Widget build(BuildContext context) {
    return _AboutListRow(
      icon: _AboutRowIconType.system,
      label: '系统',
      value: _platformLabel,
    );
  }
}

class _AboutListRow extends StatefulWidget {
  const _AboutListRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  final _AboutRowIconType icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  State<_AboutListRow> createState() => _AboutListRowState();
}

class _AboutListRowState extends State<_AboutListRow> {
  bool _hovered = false;

  bool get _clickable => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final active = _clickable && _hovered;
    final colors = AppTheme.colors(context);
    final contentColor = active ? colors.text : colors.textMuted;
    final trailingColor = active ? colors.textMuted : colors.textSubtle;

    return MouseRegion(
      cursor: _clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_clickable) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_clickable) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 50,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: active ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceHover,
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: contentColor),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) {
                  final animatedColor = color ?? contentColor;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        _AboutRowIcon(
                          type: widget.icon,
                          size: 20,
                          color: animatedColor,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: animatedColor,
                                  fontSize: 14.5,
                                  height: 1.2,
                                ),
                          ),
                        ),
                        if (widget.value != null)
                          Text(
                            widget.value!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: trailingColor,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                          )
                        else
                          _AboutLinkChevron(size: 16, color: trailingColor),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutRowIcon extends StatelessWidget {
  const _AboutRowIcon({
    required this.type,
    required this.size,
    required this.color,
  });

  final _AboutRowIconType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AboutRowIconPainter(type: type, color: color),
    );
  }
}

class _AboutRowIconPainter extends CustomPainter {
  const _AboutRowIconPainter({required this.type, required this.color});

  final _AboutRowIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final strokeScale = sx < sy ? sx : sy;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * strokeScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    Offset p(double x, double y) => Offset(x * sx, y * sy);
    RRect rr(double x, double y, double w, double h, double r) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy),
        Radius.circular(r * strokeScale),
      );
    }

    switch (type) {
      case _AboutRowIconType.code:
        canvas.drawLine(p(10, 7), p(6, 12), paint);
        canvas.drawLine(p(6, 12), p(10, 17), paint);
        canvas.drawLine(p(14, 7), p(18, 12), paint);
        canvas.drawLine(p(18, 12), p(14, 17), paint);
        break;
      case _AboutRowIconType.system:
        canvas.drawRRect(rr(5, 4, 14, 12, 2), paint);
        canvas.drawLine(p(9, 20), p(15, 20), paint);
        canvas.drawLine(p(12, 16), p(12, 20), paint);
        break;
      case _AboutRowIconType.update:
        canvas.drawArc(
          Rect.fromCenter(center: p(12, 12), width: 14 * sx, height: 14 * sy),
          -1.25,
          4.6,
          false,
          paint,
        );
        final arrow = Path()
          ..moveTo(17.4 * sx, 7.1 * sy)
          ..lineTo(19.4 * sx, 7.2 * sy)
          ..lineTo(18.6 * sx, 5.3 * sy);
        canvas.drawPath(arrow, paint);
        canvas.drawLine(p(12, 7), p(12, 14), paint);
        canvas.drawLine(p(9.2, 11.2), p(12, 14), paint);
        canvas.drawLine(p(14.8, 11.2), p(12, 14), paint);
        canvas.drawLine(p(8.5, 17.5), p(15.5, 17.5), paint);
        break;
      case _AboutRowIconType.globe:
        canvas.drawCircle(p(12, 12), 8 * strokeScale, paint);
        canvas.drawOval(
          Rect.fromCenter(center: p(12, 12), width: 8 * sx, height: 16 * sy),
          paint,
        );
        canvas.drawLine(p(4, 12), p(20, 12), paint);
        canvas.drawLine(p(6.2, 8), p(17.8, 8), paint);
        canvas.drawLine(p(6.2, 16), p(17.8, 16), paint);
        break;
      case _AboutRowIconType.github:
        final path = Path()
          ..moveTo(12 * sx, 3.8 * sy)
          ..cubicTo(7.5 * sx, 3.8 * sy, 4 * sx, 7.3 * sy, 4 * sx, 11.9 * sy)
          ..cubicTo(4 * sx, 15.5 * sy, 6.3 * sx, 18.2 * sy, 9.6 * sx, 19.2 * sy)
          ..lineTo(9.6 * sx, 16.9 * sy)
          ..cubicTo(
            8.2 * sx,
            17.2 * sy,
            7.3 * sx,
            16.7 * sy,
            6.7 * sx,
            15.4 * sy,
          )
          ..cubicTo(
            6.4 * sx,
            14.8 * sy,
            5.9 * sx,
            14.4 * sy,
            5.4 * sx,
            14.2 * sy,
          )
          ..cubicTo(6.3 * sx, 14 * sy, 7 * sx, 14.3 * sy, 7.6 * sx, 15.1 * sy)
          ..cubicTo(
            8.2 * sx,
            15.9 * sy,
            8.9 * sx,
            16.1 * sy,
            9.7 * sx,
            15.9 * sy,
          )
          ..cubicTo(
            9.9 * sx,
            15.4 * sy,
            10.2 * sx,
            15 * sy,
            10.6 * sx,
            14.7 * sy,
          )
          ..cubicTo(8 * sx, 14.3 * sy, 6.9 * sx, 13.2 * sy, 6.9 * sx, 11 * sy)
          ..cubicTo(6.9 * sx, 9.9 * sy, 7.3 * sx, 9 * sy, 8 * sx, 8.3 * sy)
          ..cubicTo(7.8 * sx, 7.8 * sy, 7.6 * sx, 6.8 * sy, 8.1 * sx, 5.5 * sy)
          ..cubicTo(8.1 * sx, 5.5 * sy, 9.2 * sx, 5.2 * sy, 10.8 * sx, 6.4 * sy)
          ..cubicTo(
            11.6 * sx,
            6.2 * sy,
            12.4 * sx,
            6.2 * sy,
            13.2 * sx,
            6.4 * sy,
          )
          ..cubicTo(
            14.8 * sx,
            5.2 * sy,
            15.9 * sx,
            5.5 * sy,
            15.9 * sx,
            5.5 * sy,
          )
          ..cubicTo(16.4 * sx, 6.8 * sy, 16.2 * sx, 7.8 * sy, 16 * sx, 8.3 * sy)
          ..cubicTo(16.7 * sx, 9 * sy, 17.1 * sx, 9.9 * sy, 17.1 * sx, 11 * sy)
          ..cubicTo(
            17.1 * sx,
            13.2 * sy,
            16 * sx,
            14.3 * sy,
            13.4 * sx,
            14.7 * sy,
          )
          ..cubicTo(
            13.9 * sx,
            15.1 * sy,
            14.2 * sx,
            15.8 * sy,
            14.2 * sx,
            16.9 * sy,
          )
          ..lineTo(14.2 * sx, 19.2 * sy)
          ..cubicTo(
            17.6 * sx,
            18.1 * sy,
            20 * sx,
            15.5 * sy,
            20 * sx,
            11.9 * sy,
          )
          ..cubicTo(20 * sx, 7.3 * sy, 16.5 * sx, 3.8 * sy, 12 * sx, 3.8 * sy)
          ..close();
        canvas.drawPath(path, fillPaint);
        break;
      case _AboutRowIconType.license:
        final docPath = Path()
          ..moveTo(7 * sx, 3.5 * sy)
          ..lineTo(14 * sx, 3.5 * sy)
          ..lineTo(18 * sx, 7.5 * sy)
          ..lineTo(18 * sx, 20.5 * sy)
          ..lineTo(7 * sx, 20.5 * sy)
          ..close();
        canvas.drawPath(docPath, paint);
        canvas.drawLine(p(14, 3.5), p(14, 7.5), paint);
        canvas.drawLine(p(14, 7.5), p(18, 7.5), paint);
        canvas.drawLine(p(9.5, 11.5), p(15.5, 11.5), paint);
        canvas.drawLine(p(9.5, 15), p(14, 15), paint);
        break;
      case _AboutRowIconType.qq:
        canvas.drawRRect(rr(4.5, 5.5, 15, 11.5, 3.4), paint);
        final tail = Path()
          ..moveTo(9.2 * sx, 16.8 * sy)
          ..lineTo(7.4 * sx, 20 * sy)
          ..lineTo(11.8 * sx, 16.8 * sy);
        canvas.drawPath(tail, paint);
        canvas.drawCircle(p(9, 11.2), 0.9 * strokeScale, fillPaint);
        canvas.drawCircle(p(12, 11.2), 0.9 * strokeScale, fillPaint);
        canvas.drawCircle(p(15, 11.2), 0.9 * strokeScale, fillPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AboutRowIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}

class _AboutLinkChevron extends StatelessWidget {
  const _AboutLinkChevron({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AboutLinkChevronPainter(color: color),
    );
  }
}

class _AboutLinkChevronPainter extends CustomPainter {
  const _AboutLinkChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.38, size.height * 0.22)
      ..lineTo(size.width * 0.66, size.height * 0.5)
      ..lineTo(size.width * 0.38, size.height * 0.78);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AboutLinkChevronPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
