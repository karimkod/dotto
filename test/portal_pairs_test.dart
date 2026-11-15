// Placed portals pair by index: i with i ^ 1, coloured by i ~/ 2. Taking one
// back used to renumber the rest to close the gap, which re-partnered every
// pair after it. With four down, removing the first turned the first pair's
// exit into the second pair's entrance and left the last portal on its own —
// and the colours, which read the index, showed exactly that mix.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/widgets/game_grid.dart';

const _portals = LevelData(
  id: 965,
  size: 5,
  title: 'portals',
  tip: '',
  start: StartSpec(0, 0, Direction.right),
  exit: Pos(4, 4),
  toolkit: [ToolkitEntry(ToolType.teleporter, 4)],
);

void main() {
  late WidgetTester t;

  Future<void> tapCell(int r, int c) async {
    final board = t.getRect(find.byKey(const ValueKey('gameBoard')));
    await t.tapAt(board.topLeft + GridGeometry(board.width, 5).center(r, c));
    await t.pump(const Duration(seconds: 1));
  }

  Map<int, PlacedElement> placed() => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<GameGridPainter>()
      .single
      .placed;

  /// Cell -> partner cell and cell -> colour pair, as the board sees them.
  Map<int, int> links() => buildTeleportLinks(_portals, placed());
  Map<int, int> colours() => buildPortalPairs(_portals, placed());

  const a1 = 2 * 5 + 0, a2 = 2 * 5 + 2, b1 = 3 * 5 + 0, b2 = 3 * 5 + 2;

  Future<void> placeFour(WidgetTester tester) async {
    t = tester;
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        level: Level(
          id: 965,
          number: 965,
          title: 'portals',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
        levelOverride: _portals,
      ),
    ));
    await tester.pump();
    // The only tool in the kit is selected already: entrance, exit, entrance,
    // exit — pair A on (2,0)/(2,2), pair B on (3,0)/(3,2).
    for (final k in [a1, a2, b1, b2]) {
      await tapCell(k ~/ 5, k % 5);
    }
    expect(links(), {a1: a2, a2: a1, b1: b2, b2: b1});
  }

  testWidgets('taking the first portal back leaves the other pairs alone',
      (tester) async {
    await placeFour(tester);
    final before = colours();

    await tapCell(a1 ~/ 5, a1 % 5); // tap a placed piece: take it back

    expect(links(), {b1: b2, b2: b1},
        reason: 'pair B is untouched, and pair A\'s exit waits for a partner '
            'instead of being handed pair B\'s entrance');
    expect(colours()[a2], before[a2], reason: 'the half-pair keeps its colour');
    expect(colours()[b1], before[b1]);
    expect(colours()[b2], before[b2]);
    expect(colours()[b1], isNot(colours()[a2]),
        reason: 'two different pairs must never share a colour');
  });

  testWidgets('the next portal fills the hole and rejoins its pair',
      (tester) async {
    await placeFour(tester);
    final before = colours();

    await tapCell(a1 ~/ 5, a1 % 5);
    const back = 1 * 5 + 1;
    await tapCell(back ~/ 5, back % 5);

    expect(links(), {back: a2, a2: back, b1: b2, b2: b1},
        reason: 'the new portal is the entrance pair A was missing');
    expect(colours()[back], before[a2]);
    expect(placed()[back]!.isPortalEntrance, isTrue);
  });

  testWidgets('a middle portal comes back as the same end of the same pair',
      (tester) async {
    await placeFour(tester);
    final before = colours();

    await tapCell(a2 ~/ 5, a2 % 5); // pair A's exit
    const back = 1 * 5 + 1;
    await tapCell(back ~/ 5, back % 5);

    expect(links(), {a1: back, back: a1, b1: b2, b2: b1});
    expect(colours()[back], before[a1]);
    expect(placed()[back]!.isPortalEntrance, isFalse,
        reason: 'it replaces an exit, so it is one');
  });

}
