// End-to-end tests for the game screen, using World 1 level 2 (3x3, one Up
// arrow; solution = Up at (2,2)). Level 1 has no toolkit, so the interactive
// drag/tap tests target level 2.

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
  // A continuous glow animation runs (so no pumpAndSettle), and a valid drop
  // plays a ~110ms magnet-snap before the piece commits — pump past both.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  // Level 2: 3x3, start (2,0)→right, exit (0,2), 1× Up arrow, solution Up (2,2).
  const level2 = Level(
    id: 2,
    number: 2,
    title: 'One Turn',
    difficulty: Difficulty.easy,
    status: LevelStatus.unlocked,
  );
  const gridN = 3;

  testWidgets('Level 2 is solvable end to end (tap)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    // The single Up arrow (auto-selected) goes at (2,2).
    await tester.tapAt(boardRect.topLeft + geo.center(2, 2));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('Level 2 is solvable by dragging the arrow onto the grid',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    final target = boardRect.topLeft + geo.center(2, 2);

    await _dragArrow(tester, tester.getCenter(find.text('UP')), target);

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('drag-drop registers anywhere on the grid, not just near the dot',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    // Cell (1,1): empty and not adjacent to the dot's start (2,0).
    final target = boardRect.topLeft + geo.center(1, 1);

    await _dragArrow(tester, tester.getCenter(find.text('UP')), target);

    // The single Up arrow was consumed → its count badge now reads 0.
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a placed element can be dragged to another cell', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    final wrongCell = boardRect.topLeft + geo.center(1, 1);
    final solutionCell = boardRect.topLeft + geo.center(2, 2);

    // Place on the wrong cell first, then move it to the solution cell.
    await _dragArrow(tester, tester.getCenter(find.text('UP')), wrongCell);
    await _dragArrow(tester, wrongCell, solutionCell);

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });

  testWidgets('dragging a placed element off-grid returns it to the toolkit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    final cell = boardRect.topLeft + geo.center(2, 2);

    await _dragArrow(tester, tester.getCenter(find.text('UP')), cell);
    expect(find.text('0'), findsOneWidget); // arrow consumed

    // Drag it from the grid onto the toolbar (off-grid) → removed.
    await _dragArrow(tester, cell, tester.getCenter(find.text('UP')));

    expect(find.text('1'), findsOneWidget); // refunded
  });

  testWidgets('Level 2 fails when no arrow is placed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Dot runs straight off the right edge.
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('Level 1 has no toolkit and just needs Play', (tester) async {
    const level1 = Level(
      id: 1,
      number: 1,
      title: 'First Steps',
      difficulty: Difficulty.easy,
      status: LevelStatus.completed,
    );
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level1)));
    await tester.pump();

    // No toolkit → a "Press Play!" hint instead.
    expect(find.text('Press Play!'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Level Complete!'), findsOneWidget);
  });
}
