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

  Future<void> runToWin(WidgetTester tester) async {
    await tester.tap(find.text('Play'));
    await tester.pump();
    // Enough ticks for the longest World 1 path plus the ~2.2s celebration.
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('Level 2 is solvable end to end (tap)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    // The single Up arrow (auto-selected) goes at (2,2).
    await tester.tapAt(boardRect.topLeft + geo.center(2, 2));
    await tester.pump();

    await runToWin(tester);

    // Win → the celebration plays and the Continue button appears.
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Level 2 is solvable by dragging the arrow onto the grid',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    final target = boardRect.topLeft + geo.center(2, 2);

    await _dragArrow(tester, tester.getCenter(find.text('UP')), target);

    await runToWin(tester);

    // Win → the celebration plays and the Continue button appears.
    expect(find.text('Continue'), findsOneWidget);
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

    await runToWin(tester);

    // Win → the celebration plays and the Continue button appears.
    expect(find.text('Continue'), findsOneWidget);
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

  testWidgets('Reset asks for confirmation before clearing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    await _dragArrow(tester, tester.getCenter(find.text('UP')),
        boardRect.topLeft + geo.center(2, 2));
    expect(find.text('0'), findsOneWidget); // arrow placed

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Tap RESET → confirmation dialog; Cancel keeps the piece.
    await tester.tap(find.text('RESET'));
    await settle();
    expect(find.text('Reset all pieces?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(find.text('0'), findsOneWidget);

    // Tap RESET → confirm Reset clears the board (arrow refunded → 1).
    await tester.tap(find.text('RESET'));
    await settle();
    await tester.tap(find.text('Reset'));
    await settle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('Level 2 fails when the arrow is placed wrong', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    // Place the arrow off the dot's path so it never turns and runs off-edge.
    await _dragArrow(tester, tester.getCenter(find.text('UP')),
        boardRect.topLeft + geo.center(1, 1));

    await tester.tap(find.text('Play'));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('Play is disabled until every piece is placed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    // Hint shown; tapping Play does nothing (still planning, no overlay).
    expect(find.textContaining('Place all elements'), findsOneWidget);
    await tester.tap(find.text('Play'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('Try Again'), findsNothing);
    expect(find.text('Continue'), findsNothing);

    // Place the arrow → the hint disappears (Play is now enabled).
    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    await _dragArrow(tester, tester.getCenter(find.text('UP')),
        boardRect.topLeft + geo.center(2, 2));
    expect(find.textContaining('Place all elements'), findsNothing);
  });

  testWidgets('Next Level button loads the next level', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    await tester.tapAt(boardRect.topLeft + geo.center(2, 2));
    await tester.pump();
    await runToWin(tester);

    // Win → the Continue button appears after the celebration.
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Now on level 3 (its header title).
    expect(find.text('Level 3'), findsOneWidget);
  });

  testWidgets('last level shows World Complete and no Next Level',
      (tester) async {
    const level10 = Level(
      id: 10,
      number: 10,
      title: 'Grand Tour',
      difficulty: Difficulty.hard,
      status: LevelStatus.unlocked,
    );
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level10)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 6);
    // Solution: Down (2,3), Right (4,3), Down (4,5).
    await _dragArrow(tester, tester.getCenter(find.text('DOWN')),
        boardRect.topLeft + geo.center(2, 3));
    await _dragArrow(tester, tester.getCenter(find.text('DOWN')),
        boardRect.topLeft + geo.center(4, 5));
    await _dragArrow(tester, tester.getCenter(find.text('RIGHT')),
        boardRect.topLeft + geo.center(4, 3));

    await runToWin(tester);

    // Last level → no Continue; the button is Back to Menu.
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Back to Menu'), findsOneWidget);
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

    await runToWin(tester);

    // Win → Continue appears.
    expect(find.text('Continue'), findsOneWidget);
  });
}
