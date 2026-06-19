import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/level_progress_controller.dart';
import 'package:spring_note/core/services/stats_service.dart';
import 'package:spring_note/src/rust/stats.dart' as rust_stats;

void main() {
  test(
    'level progress is derived from stats snapshot and caps today',
    () async {
      final service = LevelProgressService(
        statsService: const _FakeStatsService(totalSummaries: 10, today: 12),
      );
      final progress = await service.read(localDataState: _state('unused'));

      expect(progress.totalExperiencePercent, 10);
      expect(progress.todayValidSubmissions, 10);
      expect(progress.level, 1);
      expect(progress.experiencePercent, 10);
      expect(progress.remainingTodaySubmissions, 0);
    },
  );

  test('level increases after one hundred valid submissions', () async {
    final service = LevelProgressService(
      statsService: const _FakeStatsService(totalSummaries: 100, today: 10),
    );
    final progress = await service.read(localDataState: _state('unused'));

    expect(progress.totalExperiencePercent, 100);
    expect(progress.level, 2);
    expect(progress.experiencePercent, 0);
    expect(progress.todayValidSubmissions, 10);
  });
}

LocalDataState _state(String root) {
  return LocalDataState(
    dataDirectory: root,
    configPath: '$root/config.json',
    dailyNotesDirectory: '$root/notes/daily',
    weeklyNotesDirectory: '$root/notes/weekly',
    monthlyNotesDirectory: '$root/notes/monthly',
    config: AppConfig.defaults(),
  );
}

class _FakeStatsService extends StatsService {
  const _FakeStatsService({required this.totalSummaries, required this.today});

  final int totalSummaries;
  final int today;

  @override
  Future<rust_stats.StatsSnapshot> readSnapshot({
    required LocalDataState localDataState,
    required DateTime start,
    required DateTime end,
  }) async {
    return rust_stats.StatsSnapshot(
      summary: rust_stats.StatsSummary(
        summaries:
            start.year == end.year &&
                start.month == end.month &&
                start.day == end.day
            ? today
            : totalSummaries,
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
      activity: const [],
      tokenUsage: const [],
      providerUsage: const [],
    );
  }
}
