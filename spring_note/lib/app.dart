import 'package:flutter/material.dart';

import 'core/models/local_data_state.dart';
import 'core/router/app_shell.dart';
import 'core/services/local_data_service.dart';
import 'core/theme/app_theme.dart';

class SpringNoteApp extends StatelessWidget {
  const SpringNoteApp({
    super.key,
    this.localDataService = const LocalDataService(),
  });

  final LocalDataService localDataService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpringNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: FutureBuilder<LocalDataState>(
        future: localDataService.initialize(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppStartupError(error: snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return const AppStartupLoading();
          }

          return AppShell(localDataState: snapshot.data!);
        },
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
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
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
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
