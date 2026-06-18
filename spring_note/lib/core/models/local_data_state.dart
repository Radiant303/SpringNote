import 'app_config.dart';

class LocalDataState {
  const LocalDataState({
    required this.dataDirectory,
    required this.configPath,
    required this.dailyNotesDirectory,
    required this.weeklyNotesDirectory,
    required this.monthlyNotesDirectory,
    required this.config,
  });

  final String dataDirectory;
  final String configPath;
  final String dailyNotesDirectory;
  final String weeklyNotesDirectory;
  final String monthlyNotesDirectory;
  final AppConfig config;
}
