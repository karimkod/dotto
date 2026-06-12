// End-to-end test for Level 1: place the Up arrow, press Play, watch the dot
// drive itself to the exit, and confirm the win overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/level.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/screens/game_screen.dart';

void main() {
  const level1 = Level(
    id: 1,
    number: 1,
    title: 'Level 1',
    difficulty: Difficulty.easy,
    status: LevelStatus.completed,
  );

  testWidgets('Level 1 is solvable end to end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    // Locate the board and compute the pixel center of cell (3, 3) where the
    // single Up arrow (auto-selected) must go.
    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    final target = boardRect.topLeft + geo.center(3, 3);

    await tester.tapAt(target);
    await tester.pump();

    // Start the dot.
    await tester.tap(find.text('Play'));
    await tester.pump();

    // Advance through the movement ticks (6 steps) plus the win delay.
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('Level 1 is solvable by dragging the arrow onto the grid',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    final target = boardRect.topLeft + geo.center(3, 3);

    // Drag the UP tool from the toolbar onto cell (3, 3).
    final source = tester.getCenter(find.text('UP'));
    final gesture = await tester.startGesture(source);
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('Level 1 fails when no arrow is placed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();

    // Dot runs straight off the right edge.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Try Again'), findsOneWidget);
  });
}
