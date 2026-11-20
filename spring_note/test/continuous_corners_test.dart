import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/core/widgets/page_scaffold.dart';

void main() {
  test(
    'continuous decoration preserves colors, borders, radii, and shadows',
    () {
      const shadows = [BoxShadow(color: Color(0x10000000), blurRadius: 8)];
      final decoration =
          AppTheme.continuousBoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(18),
                boxShadow: shadows,
              )
              as ShapeDecoration;
      final shape = decoration.shape as RoundedSuperellipseBorder;

      expect(decoration.color, AppTheme.surface);
      expect(decoration.shadows, shadows);
      expect(shape.side.color, AppTheme.border);
      expect(shape.borderRadius, BorderRadius.circular(18));
    },
  );

  test('non-uniform borders keep their original box decoration', () {
    final decoration = AppTheme.continuousBoxDecoration(
      color: AppTheme.surface,
      border: const Border(bottom: BorderSide(color: AppTheme.border)),
      borderRadius: BorderRadius.circular(18),
    );

    expect(decoration, isA<BoxDecoration>());
    expect(
      (decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(18),
    );
  });

  test('themed input borders use continuous corners', () {
    final inputTheme = AppTheme.light().inputDecorationTheme;

    for (final border in [
      inputTheme.border,
      inputTheme.enabledBorder,
      inputTheme.focusedBorder,
    ]) {
      expect(border, isA<ShapedInputBorder>());
      expect(
        (border! as ShapedInputBorder).shape,
        isA<RoundedSuperellipseBorder>(),
      );
    }
  });

  testWidgets('static cards use continuous paint without adding clip layers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SoftCard(child: Text('content')),
      ),
    );

    final card = find.byType(SoftCard);
    final container = tester.widget<Container>(
      find.descendant(of: card, matching: find.byType(Container)),
    );
    final decoration = container.decoration! as ShapeDecoration;

    expect(decoration.shape, isA<RoundedSuperellipseBorder>());
    expect(container.clipBehavior, Clip.none);
    expect(
      find.descendant(of: card, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(ClipRSuperellipse)),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(ClipPath)),
      findsNothing,
    );
  });
}
