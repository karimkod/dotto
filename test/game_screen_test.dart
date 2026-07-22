// End-to-end tests for the game screen, using World 1 level 2 (3x3, one Up
// arrow; solution = Up at (2,2)). Level 1 has no toolkit, so the interactive
// drag/tap tests target level 2.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/models/level_data.dart';
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
    // Enough ticks for the longest World 1 path (the 8x8 exam) plus the ~2.2s
    // celebration.
    for (var i = 0; i < 48; i++) {
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
    // The fail overlay names why the dot died.
    expect(find.text('Ran off the edge!'), findsOneWidget);
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

    // Place the arrow → the hint switches to "Ready!" (Play is now enabled),
    // keeping the same space so the button doesn't shift.
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

  // Keyed off kLevelCount rather than a hardcoded number, so adding a level
  // moves this test with it instead of quietly asserting the wrong thing.
  testWidgets('the last level shows Back to Menu, not Continue', (tester) async {
    final lastLevel = Level(
      id: kLevelCount,
      number: kLevelCount,
      title: levelDataFor(kLevelCount)!.title,
      difficulty: Difficulty.easy,
      status: LevelStatus.unlocked,
    );
    await tester
        .pumpWidget(MaterialApp(home: GameScreen(level: lastLevel)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, levelDataFor(kLevelCount)!.size);
    Offset cell(int r, int c) => boardRect.topLeft + geo.center(r, c);
    // Level 60 "Wormhole": the recorded finale solution. Portals are dropped in
    // pair order (1st pair, then 2nd) so placement-order pairing matches.
    await _dragArrow(tester, tester.getCenter(find.text('WARP')), cell(1, 5));
    await _dragArrow(tester, tester.getCenter(find.text('WARP')), cell(1, 7));
    await _dragArrow(tester, tester.getCenter(find.text('WARP')), cell(3, 2));
    await _dragArrow(tester, tester.getCenter(find.text('WARP')), cell(5, 5));
    await _dragArrow(tester, tester.getCenter(find.text('SHIELD')), cell(8, 1));
    await _dragArrow(tester, tester.getCenter(find.text('PAUSE')), cell(4, 5));
    await _dragArrow(tester, tester.getCenter(find.text('UP')), cell(8, 2));
    await _dragArrow(tester, tester.getCenter(find.text('RIGHT')), cell(0, 7));

    await runToWin(tester);

    // Last level → no Continue; the button is Back to Menu.
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Back to Menu'), findsOneWidget);
  });

  testWidgets('level 50 is no longer last, so it offers Continue',
      (tester) async {
    const level50 = Level(
      id: 50,
      number: 50,
      title: 'The Summit',
      difficulty: Difficulty.hard,
      status: LevelStatus.unlocked,
    );
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level50)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 9); // the 9x9 Summit
    Offset cell(int r, int c) => boardRect.topLeft + geo.center(r, c);
    // Turn down and back along row 4, collecting a shield, and pause so the
    // shielded hit lands on the patrol sharing the sealed box — that blast opens
    // the column-2 wall. Climb the freed left edge, then run row 0 home.
    await _dragArrow(tester, tester.getCenter(find.text('DOWN')), cell(3, 6));
    await _dragArrow(tester, tester.getCenter(find.text('LEFT')), cell(4, 6));
    await _dragArrow(tester, tester.getCenter(find.text('SHIELD')), cell(4, 4));
    await _dragArrow(tester, tester.getCenter(find.text('PAUSE')), cell(4, 3));
    await _dragArrow(tester, tester.getCenter(find.text('UP')), cell(4, 0));
    await _dragArrow(tester, tester.getCenter(find.text('RIGHT')), cell(0, 0));
    await _dragArrow(tester, tester.getCenter(find.text('SHIELD')), cell(0, 3));

    await runToWin(tester);

    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('shield + chain explosion clears the wall and wins (L24)',
      (tester) async {
    // Level 24: shielded hit on the destroyer blasts the wall to the exit.
    const level24 = Level(
      id: 24,
      number: 24,
      title: 'Break Through',
      difficulty: Difficulty.medium,
      status: LevelStatus.unlocked,
    );
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level24)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 5);
    Offset cell(int r, int c) => boardRect.topLeft + geo.center(r, c);
    // Solution: Up(2,1), Shield(1,1), Right(0,1) → the shielded hit on the
    // destroyer at (0,2) blasts the wall (0,3) blocking the exit.
    await _dragArrow(tester, tester.getCenter(find.text('UP')), cell(2, 1));
    await _dragArrow(tester, tester.getCenter(find.text('SHIELD')), cell(1, 1));
    await _dragArrow(tester, tester.getCenter(find.text('RIGHT')), cell(0, 1));

    await runToWin(tester);

    // The wall blasted open and the dot reached the exit.
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('hitting a destroyer explodes, then shows Try Again',
      (tester) async {
    // Level 16: 4x4, start (3,0)→right, exit (0,1), destroyer at (3,2), 1× Up.
    const level16 = Level(
      id: 16,
      number: 16,
      title: 'First Danger',
      difficulty: Difficulty.easy,
      status: LevelStatus.unlocked,
    );
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level16)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 4);
    // Place the Up arrow OFF the dot's path so it still runs into the destroyer.
    await _dragArrow(tester, tester.getCenter(find.text('UP')),
        boardRect.topLeft + geo.center(0, 0));

    await tester.tap(find.text('Play'));
    await tester.pump();
    // Run past the destroyer hit (~2 ticks) and the ~0.5s explosion delay.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The explosion resolved into the fail card (not a win), naming the cause.
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Destroyed!'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('Level 2 shows a tutorial hand that stops on interaction',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    // Hidden initially; appears after the ~2s delay.
    expect(find.text('👆'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('👆'), findsOneWidget);

    // Placing a piece stops the hand for good.
    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, gridN);
    await _dragArrow(tester, tester.getCenter(find.text('UP')),
        boardRect.topLeft + geo.center(2, 2));
    expect(find.text('👆'), findsNothing);
  });

  testWidgets('debug build shows the edit-in-designer pencil', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
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

  // Surviving a patrol with a shield must NOT skip what is on the floor of that
  // cell. Row 2: the dot runs right from (2,0) collecting a shield at (2,1);
  // the patrol starting at (2,4) heading left lands on (2,2) on the same beat
  // the dot does. The exit is UP at (0,2), so the ONLY way to win is for the
  // arrow at (2,2) to still turn the dot after the shield blows the patrol away.
  //
  // The game used to return early from the beat after a shielded patrol kill,
  // skipping the placed piece entirely — the dot ploughed on east and off the
  // board. The simulator always applied the arrow, so the solver was verifying
  // solutions the player could not actually execute.
  testWidgets('an arrow under a patrol still turns the dot after a shield kill',
      (tester) async {
    const level = LevelData(
      id: 905,
      size: 5,
      title: 'arrow under a patrol',
      tip: '',
      start: StartSpec(2, 0, Direction.right),
      exit: Pos(0, 2),
      movers: [MovingDestroyer(2, 4, horizontal: true, dir: -1)],
      toolkit: [
        ToolkitEntry(ToolType.shield, 1),
        ToolkitEntry(ToolType.arrowUp, 1),
      ],
    );
    const meta = Level(
      id: 905,
      number: 905,
      title: 'arrow under a patrol',
      difficulty: Difficulty.hard,
      status: LevelStatus.unlocked,
    );

    await tester.pumpWidget(const MaterialApp(
        home: GameScreen(level: meta, levelOverride: level)));
    await tester.pump();

    final boardRect = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(boardRect.width, 5);

    // Shield at (2,1), then the Up arrow at (2,2) — under the patrol's path.
    await tester.tap(find.text('SHIELD'));
    await tester.pump();
    await tester.tapAt(boardRect.topLeft + geo.center(2, 1));
    await tester.pump();
    await tester.tap(find.text('UP'));
    await tester.pump();
    await tester.tapAt(boardRect.topLeft + geo.center(2, 2));
    await tester.pump();

    await runToWin(tester);

    // Assert on the footer, not the celebration text: the win message is picked
    // at random from six, so matching it would make this test flaky. An override
    // level has no next level, so a win ends on "Back to Menu" and a loss would
    // offer "Retry".
    expect(find.text('Back to Menu'), findsOneWidget,
        reason: 'the arrow under the patrol must still redirect the dot');
    expect(find.text('Retry'), findsNothing, reason: 'the dot should not die');
  });
}
