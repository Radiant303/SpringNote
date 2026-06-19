import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_data_state.dart';
import 'stats_service.dart';

class LevelProgressState {
  const LevelProgressState({
    required this.totalExperiencePercent,
    required this.todayValidSubmissions,
  });

  final int totalExperiencePercent;
  final int todayValidSubmissions;

  int get level => (totalExperiencePercent ~/ 100) + 1;
  int get experiencePercent => totalExperiencePercent % 100;
  int get remainingTodaySubmissions =>
      (10 - todayValidSubmissions).clamp(0, 10);

  LevelProgressState recordOneSubmission() {
    if (todayValidSubmissions >= 10) {
      return this;
    }
    return LevelProgressState(
      totalExperiencePercent: totalExperiencePercent + 1,
      todayValidSubmissions: todayValidSubmissions + 1,
    );
  }

  static const empty = LevelProgressState(
    totalExperiencePercent: 0,
    todayValidSubmissions: 0,
  );
}

class LevelProgressService {
  const LevelProgressService({
    this.statsService = const StatsService(),
    this.historyStart,
  });

  final StatsService statsService;
  final DateTime? historyStart;

  Future<LevelProgressState> read({
    required LocalDataState localDataState,
    DateTime? date,
  }) async {
    final targetDate = date ?? DateTime.now();
    final snapshots = await Future.wait([
      statsService.readSnapshot(
        localDataState: localDataState,
        start: historyStart ?? DateTime(2000),
        end: targetDate,
      ),
      statsService.readSnapshot(
        localDataState: localDataState,
        start: targetDate,
        end: targetDate,
      ),
    ]);
    return LevelProgressState(
      totalExperiencePercent: snapshots[0].summary.summaries,
      todayValidSubmissions: snapshots[1].summary.summaries.clamp(0, 10),
    );
  }
}

class LevelProgressController extends ChangeNotifier {
  LevelProgressController({this.service = const LevelProgressService()});

  final LevelProgressService service;
  LocalDataState? _localDataState;
  int _loadGeneration = 0;

  LevelProgressState state = LevelProgressState.empty;

  void attach(LocalDataState localDataState) {
    _localDataState = localDataState;
    unawaited(_load(localDataState, ++_loadGeneration));
  }

  Future<void> recordValidSubmission() async {
    final localDataState = _localDataState;
    if (localDataState == null) {
      return;
    }
    final optimisticState = state.recordOneSubmission();
    if (!identical(optimisticState, state)) {
      state = optimisticState;
      notifyListeners();
    }
    try {
      final persistedState = await service.read(localDataState: localDataState);
      if (persistedState.totalExperiencePercent !=
              state.totalExperiencePercent ||
          persistedState.todayValidSubmissions != state.todayValidSubmissions) {
        state = persistedState;
        notifyListeners();
      }
    } catch (_) {
      // Level progress should never block daily note submission.
    }
  }

  Future<void> _load(LocalDataState localDataState, int generation) async {
    final loaded = await service.read(localDataState: localDataState);
    if (generation != _loadGeneration ||
        _localDataState?.dataDirectory != localDataState.dataDirectory) {
      return;
    }
    state = loaded;
    notifyListeners();
  }
}
