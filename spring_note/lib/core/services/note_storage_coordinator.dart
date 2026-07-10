import 'dart:async';

class NoteStorageCoordinator {
  NoteStorageCoordinator._();

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};

  static Future<T> runForDataDirectory<T>(
    String dataDirectory,
    Future<T> Function() operation,
  ) {
    return _runExclusive(_queueKey(dataDirectory), operation);
  }

  static Future<T> runForManagedNotePath<T>(
    String notePath,
    Future<T> Function() operation,
  ) {
    final dataDirectory = _dataDirectoryFromManagedNotePath(notePath);
    if (dataDirectory == null) {
      return operation();
    }
    return runForDataDirectory(dataDirectory, operation);
  }

  static Future<T> _runExclusive<T>(
    String key,
    Future<T> Function() operation,
  ) async {
    final previous = _queues[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final current = gate.future;
    _queues[key] = current;

    try {
      await previous.catchError((_) {});
      return await operation();
    } finally {
      gate.complete();
      if (identical(_queues[key], current)) {
        _queues.remove(key);
      }
    }
  }

  static String? _dataDirectoryFromManagedNotePath(String notePath) {
    final normalized = _normalizePath(notePath);
    final lower = normalized.toLowerCase();
    for (final directory in const ['daily', 'weekly', 'monthly']) {
      final marker = '/notes/$directory/';
      final index = lower.lastIndexOf(marker);
      if (index < 0 || index + marker.length >= normalized.length) {
        continue;
      }
      final dataDirectory = normalized.substring(0, index);
      return dataDirectory.isEmpty ? '/' : dataDirectory;
    }
    return null;
  }

  static String _queueKey(String path) {
    final normalized = _normalizePath(path);
    final caseInsensitive =
        RegExp(r'^[A-Za-z]:($|/)').hasMatch(normalized) ||
        normalized.startsWith('//');
    return caseInsensitive ? normalized.toLowerCase() : normalized;
  }

  static String _normalizePath(String path) {
    var normalized = path.trim().replaceAll(r'\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
