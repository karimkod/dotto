// Smoke + interaction test for the dev level designer screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/screens/level_designer_screen.dart';

void main() {
  testWidgets('Level designer renders palette, toolkit and buttons',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LevelDesignerScreen()));
    await tester.pump();

    expect(find.text('Level Designer'), findsOneWidget);
    // Palette chips.
    expect(find.text('Wall'), findsOneWidget);
    expect(find.text('Destroyer'), findsOneWidget);
    expect(find.text('Shield'), findsOneWidget);
    // Toolkit counters.
    expect(find.text('◯ Shield'), findsOneWidget);
    // Action buttons.
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Export JSON'), findsOneWidget);
    expect(find.text('Import JSON'), findsOneWidget);
  });

  testWidgets('painting a cell and opening the solver report works',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LevelDesignerScreen()));
    await tester.pump();

    // Paint a cell (default tool = Wall) — should not throw.
    await tester.tap(find.byKey(const ValueKey('designerBoard')));
    await tester.pump();

    // Open the solver report dialog (scroll the button into view first).
    await tester.ensureVisible(find.text('Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(find.text('Solver report'), findsOneWidget);
    expect(find.text('Solvable'), findsOneWidget);
    expect(find.text('Play it'), findsOneWidget);
  });
}
