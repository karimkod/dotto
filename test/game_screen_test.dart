// End-to-end test for Level 1: place the Up arrow, press Play, watch the dot
// drive itself to the exit, and confirm the win overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/level.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/screens/game_screen.dart';

/// Drags from [source] to [target] in several steps so onPanStart/Update/End
/// all fire, mimicking a real finger drag.
Future<void> _dragArrow(
    WidgetTester tester, Offset source, Offset target) async {
  final gesture = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(Offset.lerp(source, target, 0.33)!);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(Offset.lerp(source, target, 0.66)!);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

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
    await _dragArrow(tester, source, target);

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('drag-drop registers anywhere on the grid, not just near the dot',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    // Cell (1, 1): empty, and far from the dot/start (3, 0) — this drop only
    // works if the DragTarget covers the whole grid surface.
    final target = boardRect.topLeft + geo.center(1, 1);

    final source = tester.getCenter(find.text('UP'));
    await _dragArrow(tester, source, target);

    // The single UP arrow was consumed → its count badge now reads 0.
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a placed element can be dragged to another cell', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    final wrongCell = boardRect.topLeft + geo.center(3, 2);
    final solutionCell = boardRect.topLeft + geo.center(3, 3);

    // Place the arrow on the wrong cell (3, 2) first...
    await _dragArrow(tester, tester.getCenter(find.text('UP')), wrongCell);
    // ...then move it from (3, 2) to the solution cell (3, 3).
    await _dragArrow(tester, wrongCell, solutionCell);

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The move worked → the level is solved.
    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('dragging a placed element off-grid returns it to the toolkit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    final cell = boardRect.topLeft + geo.center(3, 3);

    await _dragArrow(tester, tester.getCenter(find.text('UP')), cell);
    expect(find.text('0'), findsOneWidget); // arrow consumed

    // Drag it from the grid down onto the toolbar (off-grid) → removed.
    final offGrid = tester.getCenter(find.text('UP'));
    await _dragArrow(tester, cell, offGrid);

    // Arrow refunded → count badge back to 1.
    expect(find.text('1'), findsOneWidget);
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
