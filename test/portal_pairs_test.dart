// Placed portals pair by index: i with i ^ 1, coloured by i ~/ 2. Taking one
// back used to renumber the rest to close the gap, which re-partnered every
// pair after it. With four down, removing the first turned the first pair's
// exit into the second pair's entrance and left the last portal on its own —
// and the colours, which read the index, showed exactly that mix.
//
// Hints had the same problem from the other side: they put a portal down with
// the index it had in the recorded solution, which could already be in use.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/ads/ad_manager.dart';
import 'package:dotto/data/hint_order.dart';
import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/services/free_hint_service.dart';
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

  testWidgets('a waiting portal gets the next one, even with a lower pair empty',
      (tester) async {
    await placeFour(tester);
    // Leave pair B's entrance on its own, with all of pair A gone.
    await tapCell(a1 ~/ 5, a1 % 5);
    await tapCell(a2 ~/ 5, a2 % 5);
    await tapCell(b2 ~/ 5, b2 % 5);
    expect(links(), isEmpty);

    const back = 1 * 5 + 1;
    await tapCell(back ~/ 5, back % 5);
    expect(links(), {b1: back, back: b1},
        reason: 'filling the lowest free number would have opened pair A '
            'again and left (3,0) waiting');
  });

  group('portals a hint puts down', () {
    setUp(FreeHintService.resetForTest);
    tearDown(() => AdManager.stubRewardedForTest(null));

    Widget level(int n) => MaterialApp(
          home: GameScreen(
            level: Level(
              id: n,
              number: n,
              title: 'level $n',
              difficulty: Difficulty.easy,
              status: LevelStatus.unlocked,
            ),
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      // Three ~220ms pulses, then the ~600ms pop-in.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    /// Recorded partners, as cell -> cell.
    Map<int, int> recordedPairs(int n) {
      final size = levelDataFor(n)!.size;
      final sol = recordedSolution(n);
      return {
        for (final p in sol)
          for (final q in sol)
            if (p.element.portalIndex != null &&
                q.element.portalIndex == (p.element.portalIndex! ^ 1))
              p.r * size + p.c: q.r * size + q.c,
      };
    }

    testWidgets('never share a number with yours', (tester) async {
      t = tester;
      final data = levelDataFor(51)!;
      final sol = recordedSolution(51);
      final hinted = hintOrder(data, sol).first;
      final partner = sol.firstWhere((p) => p != hinted);
      Map<int, int> boardLinks() => buildTeleportLinks(data, placed());

      await tester.pumpWidget(level(51));
      await tester.pump();

      // A portal of the player's own, somewhere the solution does not use.
      const mine = 1 * 5 + 1;
      expect(sol.any((p) => p.r * 5 + p.c == mine), isFalse);
      await tapCell(mine ~/ 5, mine % 5);
      expect(placed()[mine]?.type, PlacedType.teleporter);

      await tester.tap(find.text('💡'));
      await settle(tester);

      final at = hinted.r * 5 + hinted.c;
      expect(placed()[at]?.type, PlacedType.teleporter,
          reason: 'the hint put its portal down');
      expect(placed()[at]!.portalIndex, isNot(placed()[mine]!.portalIndex),
          reason: 'two portals on one number leave one of them unpaired');
      expect(boardLinks(), isEmpty,
          reason: 'the hint must not wire its portal to the player\'s guess');

      // The player takes their guess back and puts it where the hint's partner
      // goes. It joins the hinted portal, and the board is the solution.
      await tapCell(mine ~/ 5, mine % 5);
      await tapCell(partner.r, partner.c);
      expect(boardLinks(), recordedPairs(51));
      expect(simulate(data, placed()), SimOutcome.win);
    });

    testWidgets('pair up as recorded, in whatever order they come',
        (tester) async {
      t = tester;
      AdManager.stubRewardedForTest(() async => true);
      // Three pairs, including a crossing wiring board order cannot express —
      // and the hint order splits the pairs up and reverses some of them.
      final data = levelDataFor(59)!;
      final sol = recordedSolution(59);
      expect(hintOrder(data, sol).map((p) => p.element.portalIndex),
          isNot([0, 1, 2, 3, 4, 5]),
          reason: 'not worth testing if the hints come in recorded order');

      await tester.pumpWidget(level(59));
      await tester.pump();

      await tester.tap(find.text('💡')); // the free one
      await settle(tester);
      for (var i = 1; i < sol.length; i++) {
        await tester.tap(find.text('💡'));
        await tester.pump();
        await tester.tap(find.text('Watch'));
        await settle(tester);
      }

      expect(placed().length, sol.length);
      expect(buildTeleportLinks(data, placed()), recordedPairs(59));
      expect(simulate(data, placed()), SimOutcome.win);
    });
  });
}
