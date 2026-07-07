import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/models/app_config.dart';
import 'core/models/local_data_state.dart';
import 'core/router/app_shell.dart';
import 'core/services/local_data_service.dart';
import 'core/services/stats_service.dart';
import 'core/theme/app_style_palette.dart';
import 'core/theme/app_style_palette_factory.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/context_extensions.dart';
import 'core/widgets/app_window_frame.dart';

class SpringNoteApp extends StatefulWidget {
  const SpringNoteApp({
    super.key,
    this.localDataService = const LocalDataService(),
    this.statsService = const StatsService(),
  });

  final LocalDataService localDataService;
  final StatsService statsService;

  @override
  State<SpringNoteApp> createState() => _SpringNoteAppState();
}

class _SpringNoteAppState extends State<SpringNoteApp> {
  AppConfig _config = AppConfig.defaults();
  late final Future<LocalDataState> _initFuture = _initialize();

  Future<LocalDataState> _initialize() async {
    final state = await widget.localDataService.initialize();
    await widget.statsService.recordAppStartup(appDataDir: state.dataDirectory);
    if (mounted) {
      setState(() => _config = state.config);
    } else {
      _config = state.config;
    }
    return state;
  }

  void _handleConfigChanged(AppConfig config) {
    if (mounted) {
      setState(() => _config = config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = AppTheme.fontScaleFactor(_config.fontScale);
    return MaterialApp(
      title: 'SpringNote',
      debugShowCheckedModeBanner: false,
      locale: const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      ],
      theme: AppTheme.light(appFont: _config.appFont),
      darkTheme: AppTheme.dark(appFont: _config.appFont),
      themeMode: _config.appThemeMode,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final palette = AppStylePaletteFactory.fromConfig(
          _config,
          platformBrightness: mediaQuery.platformBrightness,
        );
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(extensions: <ThemeExtension<dynamic>>[palette]),
          child: MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(fontScale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: AppWindowFrame(
        child: FutureBuilder<LocalDataState>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppStartupError(error: snapshot.error.toString());
            }

            if (!snapshot.hasData) {
              return const AppStartupLoading();
            }

            return AppShell(
              localDataState: snapshot.data!,
              onConfigChanged: _handleConfigChanged,
            );
          },
        ),
      ),
    );
  }
}

class AppStartupLoading extends StatelessWidget {
  const AppStartupLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class AppStartupError extends StatelessWidget {
  const AppStartupError({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: context.appCardBg,
            border: Border.all(color: context.appBorder),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpringNote 启动失败',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appTextTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
