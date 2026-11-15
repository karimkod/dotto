// A run that cannot end: two arrows pointing at each other send the dot back
// and forth forever, and a player can build that out of their own toolkit.
//
// Every control used to go dead while the dot ran, so the only way out of a
// board like that was to leave the level. Mid-run the Reset tile — the
// circular arrow at the end of the toolkit — now reads RESTART: the run is
// called off, the dot goes home, and the pieces stay where they are.
// That covers a cycle and every other run the player has already read and does
// not want to sit through — which is why the game does not try to spot loops
// itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/widgets/game_grid.dart';

/// Row 2 is a corridor between two arrows: the dot enters heading right, the
/// arrow at (2,3) turns it left, the arrow at (2,1) turns it right, and that is
/// the rest of eternity. The exit at (0,4) is never reached.
const _pingPong = LevelData(
  id: 960,
  size: 5,
  title: 'ping pong',
  tip: '',
  start: StartSpec(2, 0, Direction.right),
  exit: Pos(0, 4),
  forcedArrows: [
    ForcedArrow(2, 3, Direction.left),
    ForcedArrow(2, 1, Direction.right),
  ],
  // One spare arrow, so the toolbar — and with it the Reset tile — is shown.
  toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
);

/// Straight into a mine on the second beat.
const _mine = LevelData(
  id: 964,
  size: 5,
  title: 'mine',
  tip: '',
  start: StartSpec(2, 0, Direction.right),
  exit: Pos(0, 4),
  destroyers: [Pos(2, 2)],
  toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
);

Widget _game(LevelData data) => MaterialApp(
      home: GameScreen(
        level: Level(
          id: data.id,
          number: data.id,
          title: data.title,
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
        levelOverride: data,
      ),
    );

GameGridPainter _grid(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<GameGridPainter>()
    .single;

/// [ms] of play in 100ms frames. One long pump is a single frame, and the blast
/// waits on glide animations that only advance frame by frame.
Future<void> _play(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _beats(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('a looping board runs until the player restarts it',
      (tester) async {
    await tester.pumpWidget(_game(_pingPong));
    await tester.pump();

    // A piece of the player's own, off the corridor, to show it survives.
    final board = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    await tester.tapAt(board.topLeft + GridGeometry(board.width, 5).center(4, 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ready! Hit Play'), findsOneWidget);
    expect(find.text('RESET'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pump();
    // Mid-run the tile offers the way out.
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.text('RESET'), findsNothing);
    expect(find.text('Go!'), findsOneWidget);

    // Long after the cycle has come round several times, nothing has ended
    // the run on the player's behalf.
    await _beats(tester, 30);
    expect(find.text('RESTART'), findsOneWidget,
        reason: 'the game does not judge loops; the player does');
    expect(find.text('Try Again'), findsNothing);

    await tester.tap(find.text('RESTART'));
    await tester.pump();

    // Back to planning, with no overlay: restarting is not losing. And no
    // "Reset all pieces?" either — mid-run the tile restarts, it does not clear.
    expect(find.text('RESET'), findsOneWidget);
    expect(find.text('Try Again'), findsNothing);
    expect(find.text('Reset all pieces?'), findsNothing);
    expect(find.text('Ready! Hit Play'), findsOneWidget,
        reason: 'the arrow the player placed is still on the board');
    // The dot is home, so the next Play starts the run over rather than
    // resuming it.
    expect(_grid(tester).trail, [2 * 5 + 0],
        reason: 'the trail should be back to the start cell alone');

    // And it really does start over.
    await tester.tap(find.text('Play'));
    await tester.pump();
    await _beats(tester, 1);
    expect(_grid(tester).trail, [2 * 5 + 0, 2 * 5 + 1]);
    await tester.tap(find.text('RESTART'));
    await tester.pump();
  });

  group('restarting while the dot is blowing up', () {
    // The dot reaches the mine on the second beat; the blast waits for the
    // glide to land, and the fail card follows 520ms after that — at ~1800ms.
    // 1500ms is inside that window: the run is lost, but not yet shown.

    testWidgets('left alone, the mine fails the run', (tester) async {
      await tester.pumpWidget(_game(_mine));
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pump();

      await _play(tester, 1500);
      expect(find.text('Try Again'), findsNothing,
          reason: 'still inside the window the next test restarts in');
      await _play(tester, 1000);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('restarted, the fail card never arrives', (tester) async {
      await tester.pumpWidget(_game(_mine));
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pump();

      await _play(tester, 1500);
      await tester.tap(find.text('RESTART'));
      await tester.pump();
      await _play(tester, 2000);

      expect(find.text('Try Again'), findsNothing,
          reason: 'the player called the run off; a card arriving over the '
              'planning board afterwards would count a fail they never had');
      expect(find.text('RESET'), findsOneWidget);
    });
  });
}
