import '../../src/rust/api/stats_api.dart' as rust_stats_api;
import '../../src/rust/stats.dart' as rust_stats;
import '../models/local_data_state.dart';

class StatsService {
  const StatsService();

  Future<void> recordAppStartup({required String appDataDir}) async {
    try {
      await rust_stats_api.recordAppStartup(appDataDir: appDataDir);
    } catch (_) {
      // Statistics must never block app startup.
    }
  }

  Future<void> recordHomeGeneration({required String appDataDir}) async {
    try {
      await rust_stats_api.recordHomeGeneration(appDataDir: appDataDir);
    } catch (_) {
      // Statistics are best effort.
    }
  }

  Future<void> recordWorkTime({
    required String appDataDir,
    required int workSeconds,
    required double coins,
  }) async {
    try {
      await rust_stats_api.recordWorkTime(
        appDataDir: appDataDir,
        workSeconds: workSeconds,
        coins: coins,
      );
    } catch (_) {
      // Statistics are best effort.
    }
  }

  Future<rust_stats.StatsSnapshot> readSnapshot({
    required LocalDataState localDataState,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      return await rust_stats_api.getStatsSnapshot(
        appDataDir: localDataState.dataDirectory,
        dailyNotesDir: localDataState.dailyNotesDirectory,
        weeklyNotesDir: localDataState.weeklyNotesDirectory,
        monthlyNotesDir: localDataState.monthlyNotesDirectory,
        startDate: formatDate(start),
        endDate: formatDate(end),
      );
    } catch (_) {
      return emptySnapshot;
    }
  }

  static String formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static const emptySnapshot = rust_stats.StatsSnapshot(
    summary: rust_stats.StatsSummary(
      summaries: 0,
      fimCompletions: 0,
      totalRecords: 0,
      dailyNotes: 0,
      weeklyNotes: 0,
      monthlyNotes: 0,
      inputTokens: 0,
      outputTokens: 0,
      cachedTokens: 0,
      appLaunches: 0,
      workSeconds: 0,
      coins: 0,
    ),
    activity: [],
    tokenUsage: [],
    providerUsage: [],
  );
}
