import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/desktop_widget_position.dart';
import 'package:spring_note/core/services/desktop_widget_window_bridge.dart';

void main() {
  test('desktop widget snapshot serializes saved position', () {
    const snapshot = DesktopWidgetWindowSnapshot(
      running: true,
      workSeconds: 3600,
      coins: 12.5,
      coinRatePerSecond: 0.25,
      level: 3,
      experiencePercent: 42,
      progress: 0.42,
      appFont: 'system',
      fontScaleFactor: 1.0,
      position: DesktopWidgetPosition(screenId: 'display-1', x: 10, y: 20),
      orbMode: true,
      darkMode: true,
    );

    expect(snapshot.toJson()['position'], {
      'screenId': 'display-1',
      'x': 10.0,
      'y': 20.0,
    });
    expect(snapshot.toJson()['orbMode'], isTrue);
    expect(snapshot.toJson()['darkMode'], isTrue);
  });

  test('desktop widget position ignores malformed json', () {
    expect(DesktopWidgetPosition.fromJson(null), isNull);
    expect(DesktopWidgetPosition.fromJson({'x': 10}), isNull);
    expect(
      DesktopWidgetPosition.fromJson({'x': 10, 'y': double.infinity}),
      isNull,
    );
    expect(
      DesktopWidgetPosition.fromJson({'screenId': ' ', 'x': 10, 'y': 20}),
      const DesktopWidgetPosition(x: 10, y: 20),
    );
  });
}
