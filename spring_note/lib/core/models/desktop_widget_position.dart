class DesktopWidgetPosition {
  const DesktopWidgetPosition({
    required this.x,
    required this.y,
    this.screenId,
  });

  final double x;
  final double y;
  final String? screenId;

  static DesktopWidgetPosition? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x = _readFiniteDouble(value['x']);
    final y = _readFiniteDouble(value['y']);
    if (x == null || y == null) {
      return null;
    }
    final screenId = _readOptionalString(value['screenId']);
    return DesktopWidgetPosition(x: x, y: y, screenId: screenId);
  }

  Map<String, Object?> toJson() {
    return {'screenId': screenId, 'x': x, 'y': y};
  }

  static double? _readFiniteDouble(Object? value) {
    final number = value is num ? value.toDouble() : null;
    return number == null || !number.isFinite ? null : number;
  }

  static String? _readOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is DesktopWidgetPosition &&
        other.x == x &&
        other.y == y &&
        other.screenId == screenId;
  }

  @override
  int get hashCode => Object.hash(x, y, screenId);
}
