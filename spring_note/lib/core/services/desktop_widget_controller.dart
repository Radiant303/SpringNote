import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/local_data_state.dart';
import 'stats_service.dart';

class DesktopWidgetState {
  const DesktopWidgetState({
    required this.running,
    required this.workSeconds,
    required this.coins,
  });

  final bool running;
  final int workSeconds;
  final double coins;

  DesktopWidgetState copyWith({
    bool? running,
    int? workSeconds,
    double? coins,
  }) {
    return DesktopWidgetState(
      running: running ?? this.running,
      workSeconds: workSeconds ?? this.workSeconds,
      coins: coins ?? this.coins,
    );
  }
}

class DesktopWidgetController extends ChangeNotifier {
  DesktopWidgetController({
    this.statsService = const StatsService(),
    this.tickDuration = const Duration(seconds: 1),
  });

  final StatsService statsService;
  final Duration tickDuration;
  Timer? _timer;
  LocalDataState? _localDataState;
  DateTime _activeDate = DateTime.now();
  String? _activeDataDirectory;
  int _loadGeneration = 0;
  int _pendingStatsSeconds = 0;
  double _pendingStatsCoins = 0;

  DesktopWidgetState state = const DesktopWidgetState(
    running: true,
    workSeconds: 0,
    coins: 0,
  );

  double get coinRatePerSecond {
    final localDataState = _localDataState;
    if (localDataState == null) {
      return 0;
    }
    return _coinsForSeconds(localDataState, 1);
  }

  void attach(LocalDataState localDataState) {
    final dataDirectoryChanged =
        _activeDataDirectory != localDataState.dataDirectory;
    _localDataState = localDataState;
    _activeDataDirectory = localDataState.dataDirectory;
    if (dataDirectoryChanged) {
      _pendingStatsSeconds = 0;
      _pendingStatsCoins = 0;
      state = const DesktopWidgetState(running: true, workSeconds: 0, coins: 0);
      notifyListeners();
    }
    _ensureTodayDefault();
    unawaited(_loadTodayStats(localDataState, ++_loadGeneration));
    _timer ??= Timer.periodic(tickDuration, (_) => _tick());
  }

  void toggle() {
    state = state.copyWith(running: !state.running);
    notifyListeners();
  }

  Future<void> flush() async {
    final localDataState = _localDataState;
    if (localDataState == null || _pendingStatsSeconds <= 0) {
      return;
    }
    final seconds = _pendingStatsSeconds;
    final coins = _pendingStatsCoins;
    _pendingStatsSeconds = 0;
    _pendingStatsCoins = 0;
    await statsService.recordWorkTime(
      appDataDir: localDataState.dataDirectory,
      workSeconds: seconds,
      coins: coins,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_flushBestEffort());
    super.dispose();
  }

  Future<void> _flushBestEffort() async {
    try {
      await flush();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'spring_note',
          context: ErrorDescription('flushing work stats during dispose'),
        ),
      );
    }
  }

  void _tick() {
    _ensureTodayDefault();
    final localDataState = _localDataState;
    if (!state.running || localDataState == null) {
      return;
    }
    final coins = _coinsForSeconds(localDataState, tickDuration.inSeconds);
    state = state.copyWith(
      workSeconds: state.workSeconds + tickDuration.inSeconds,
      coins: state.coins + coins,
    );
    _pendingStatsSeconds += tickDuration.inSeconds;
    _pendingStatsCoins += coins;
    notifyListeners();

    if (_pendingStatsSeconds >= 60) {
      unawaited(flush());
    }
  }

  void _ensureTodayDefault() {
    final now = DateTime.now();
    if (_sameDate(now, _activeDate)) {
      return;
    }
    _activeDate = now;
    _pendingStatsSeconds = 0;
    _pendingStatsCoins = 0;
    state = const DesktopWidgetState(running: true, workSeconds: 0, coins: 0);
    notifyListeners();
    final localDataState = _localDataState;
    if (localDataState != null) {
      unawaited(_loadTodayStats(localDataState, ++_loadGeneration));
    }
  }

  Future<void> _loadTodayStats(
    LocalDataState localDataState,
    int generation,
  ) async {
    final today = DateTime.now();
    final snapshot = await statsService.readSnapshot(
      localDataState: localDataState,
      start: today,
      end: today,
    );
    if (generation != _loadGeneration ||
        _localDataState?.dataDirectory != localDataState.dataDirectory ||
        !_sameDate(today, _activeDate)) {
      return;
    }
    state = state.copyWith(
      workSeconds: snapshot.summary.workSeconds + _pendingStatsSeconds,
      coins: snapshot.summary.coins + _pendingStatsCoins,
    );
    notifyListeners();
  }

  double _coinsForSeconds(LocalDataState localDataState, int seconds) {
    final workHours = localDataState.config.dailyWorkHours;
    final secondsPerDay = (workHours <= 0 ? 8 : workHours) * 3600;
    return localDataState.config.dailySalary * seconds / secondsPerDay;
  }

  bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
