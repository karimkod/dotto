// A hint is paid for — with the daily hint, one won from a challenge, or an
// ad — so the piece it puts down stays for the rest of the visit. Reset used
// to sweep it off with everything else, and getting it back meant buying it
// again or having remembered it.
//
// Now every way of clearing the board clears around a hinted piece, and it
// cannot be tapped or dragged off. Portals need one thing more: a hinted
// portal cannot be taken back to try again, so it has to end up with its own
// partner whatever the player's portals were doing when it arrived.

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
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/services/free_hint_service.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/widgets/game_toolbar.dart';

void main() {
  setUp(FreeHintService.resetForTest);
  tearDown(() => AdManager.stubRewardedForTest(null));

  late WidgetTester t;
  late int size;

  Future<void> open(WidgetTester tester, int n) async {
    t = tester;
    size = levelDataFor(n)!.size;
    // Every hint after the free one is bought with an ad that plays through.
    AdManager.stubRewardedForTest(() async => true);
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: n,
          number: n,
          title: 'level $n',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();
  }

  GameGridPainter grid() => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<GameGridPainter>()
      .single;
  Map<int, PlacedElement> placed() => grid().placed;
  Map<ToolType, int> kit() =>
      Map.of(t.widget<GameToolbar>(find.byType(GameToolbar)).counts);

  Future<void> frames(int ms, {int step = 30}) async {
    for (var e = 0; e < ms; e += step) {
      await t.pump(Duration(milliseconds: step));
    }
  }

  /// Ask for a hint and pay for it: the free one first, an ad after that.
  Future<void> hint() async {
    await t.tap(find.text('💡'));
    await t.pump();
    if (find.text('Watch').evaluate().isNotEmpty) {
      await t.tap(find.text('Watch'));
    }
    // Three ~220ms pulses, then the ~600ms pop-in.
    await frames(1800);
  }

  int at(HintPlacement p) => p.r * size + p.c;

  Offset centre(int key) {
    final board = t.getRect(find.byKey(const ValueKey('gameBoard')));
    return board.topLeft +
        GridGeometry(board.width, size).center(key ~/ size, key % size);
  }

  Future<void> tapCell(int key) async {
    await t.tapAt(centre(key));
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> reset() async {
    await t.tap(find.text('RESET'));
    await frames(400);
    await t.tap(find.text('Reset'));
    await frames(400);
  }

  /// A cell the player can put a piece on and the solution leaves empty.
  int spare(int n) {
    final level = levelDataFor(n)!;
    final used = {for (final p in recordedSolution(n)) at(p)};
    for (var k = 0; k < size * size; k++) {
      final r = k ~/ size, c = k % size;
      if (level.baseTypeAt(r, c) == CellType.empty &&
          !level.hasForcedPieceAt(r, c) &&
          !(r == level.start.r && c == level.start.c) &&
          !(r == level.exit.r && c == level.exit.c) &&
          !used.contains(k)) {
        return k;
      }
    }
    throw StateError('level $n has no spare cell');
  }

  testWidgets('Reset clears the board around a hint', (tester) async {
    await open(tester, 6);
    final level = levelDataFor(6)!;
    final plan = hintOrder(level, recordedSolution(6));
    await hint();
    final hinted = at(plan.first);
    expect(placed().keys, [hinted]);
    expect(grid().hinted, {hinted},
        reason: 'drawn with the dashed border of a piece that cannot move');

    // The player puts the rest down themselves.
    for (final p in plan.skip(1)) {
      await t.tap(find.text(p.element.tool.label));
      await t.pump();
      await tapCell(at(p));
    }
    expect(placed().length, plan.length);

    await t.tap(find.text('RESET'));
    await frames(400);
    expect(find.textContaining('Your hints stay where they are'),
        findsOneWidget);
    await t.tap(find.text('Reset'));
    await frames(400);

    expect(placed().keys, [hinted],
        reason: 'the piece the player paid for stays; their own go back');
    expect(placed()[hinted]!.tool, plan.first.element.tool);
    expect(
        kit(),
        {
          for (final e in level.toolkit)
            e.type:
                e.type == plan.first.element.tool ? e.count - 1 : e.count,
        },
        reason: 'the hinted piece is still spent; the rest are back in the kit');
  });

  testWidgets('a hinted piece cannot be tapped or dragged off',
      (tester) async {
    await open(tester, 6);
    final first = hintOrder(levelDataFor(6)!, recordedSolution(6)).first;
    await hint();
    final hinted = at(first);
    final before = kit();

    await tapCell(hinted);
    expect(placed().keys, [hinted],
        reason: 'a tap takes back a piece of the player\'s own, not a hint');

    // Dragged off the board onto the toolkit, which would put a piece of the
    // player's own back in the kit.
    final from = centre(hinted);
    final to = t.getCenter(find.text(first.element.tool.label));
    final gesture = await t.startGesture(from);
    for (final f in [0.33, 0.66, 1.0]) {
      await t.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(Offset.lerp(from, to, f)!);
    }
    await t.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await frames(400);

    expect(placed().keys, [hinted], reason: 'nor does a drag');
    expect(kit(), before);
  });

  testWidgets('the fail card clears around hints too', (tester) async {
    await open(tester, 6);
    final plan = hintOrder(levelDataFor(6)!, recordedSolution(6));
    await hint();

    Future<void> fail() async {
      await t.tap(find.text('Play'));
      await t.pump();
      for (var i = 0; i < 100; i++) {
        if (find.text('Try Again').evaluate().isNotEmpty) break;
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Try Again'), findsOneWidget,
          reason: 'one piece of the solution is not a solution');
    }

    await fail();
    await t.tap(find.text('Clear & Edit'));
    await frames(400);
    expect(placed().keys, [at(plan[0])],
        reason: 'Clear & Edit leaves the hint where it is');

    // The second fail offers a hint, and that one clears the board first.
    await fail();
    await t.tap(find.text('Use Hint'));
    await t.pump();
    await t.tap(find.text('Watch'));
    await frames(1800);
    expect(placed().keys.toSet(), {at(plan[0]), at(plan[1])},
        reason: 'the new hint lands beside the old one, which the clear left');
    expect(grid().hinted, {at(plan[0]), at(plan[1])});
  });

  group('hinted portals', () {
    testWidgets('the partner\'s cell joins the hint, not a lower pair',
        (tester) async {
      await open(tester, 57);
      final data = levelDataFor(57)!;
      final sol = recordedSolution(57);
      final first = hintOrder(data, sol).first;
      expect(first.element.type, PlacedType.teleporter,
          reason: 'not worth testing unless the first hint is a portal');
      final partner = sol.firstWhere((p) =>
          p.element.portalIndex == (first.element.portalIndex! ^ 1));
      Map<int, int> links() => buildTeleportLinks(data, placed());

      // A portal of the player's own, waiting on the lowest pair.
      await t.tap(find.text('WARP'));
      await t.pump();
      final mine = spare(57);
      await tapCell(mine);
      expect(placed()[mine]?.type, PlacedType.teleporter);

      await hint();
      expect(links(), isEmpty, reason: 'the hint opens a pair of its own');

      await tapCell(at(partner));
      expect(links(), {at(first): at(partner), at(partner): at(first)},
          reason: 'the lowest waiting pair is the player\'s, and the hint '
              'could only be joined by taking that portal up first');
    });

    testWidgets('a hint takes its partner back from a wrong guess',
        (tester) async {
      await open(tester, 59);
      final data = levelDataFor(59)!;
      final plan = hintOrder(data, recordedSolution(59));
      expect(plan[1].element.portalIndex, plan[0].element.portalIndex! ^ 1,
          reason: 'the test needs the first two hints to be one pair');
      Map<int, int> links() => buildTeleportLinks(data, placed());
      final a = at(plan[0]), b = at(plan[1]);

      await hint();
      // The player's next portal joins the hinted one — in the wrong place.
      final guess = spare(59);
      await tapCell(guess);
      expect(links(), {a: guess, guess: a});

      await hint();
      expect(links(), {a: b, b: a},
          reason: 'the hint is locked in, so its partner must join it; the '
              'guess is what has to give way');
      expect(placed()[guess]?.type, PlacedType.teleporter,
          reason: 'the guess moves to a pair of its own; it is not taken away');
      expect(placed()[guess]!.isPortalEntrance, isFalse,
          reason: 'and stays the end it was');

      // Reset takes the guess back and leaves the hinted pair joined.
      await reset();
      expect(placed().keys.toSet(), {a, b});
      expect(links(), {a: b, b: a});

      // The rest of the hints finish the board.
      for (var i = 2; i < plan.length; i++) {
        await hint();
      }
      expect(placed().length, plan.length);
      expect(simulate(data, placed()), SimOutcome.win);
    });
  });
}
