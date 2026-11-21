// A hint used to need an empty square and a piece of its kind left in the kit.
// A player who had put every piece down wrongly had neither, so the bulb
// greyed out with a hint in hand: Hot Landing (level 66) with all four pieces
// on wrong squares was the report. Now the hint makes room, taking back what
// is in the way; joins up portals paired with the wrong partner; and on a
// board that is already right, vouches for one of the player's own pieces, so
// the bulb never tells a player whether a full board is right.

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
import 'package:dotto/widgets/bouncy_button.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/widgets/game_toolbar.dart';

void main() {
  setUp(FreeHintService.resetForTest);
  tearDown(() => AdManager.stubRewardedForTest(null));

  late WidgetTester t;
  late LevelData data;

  Future<void> open(WidgetTester tester, int id) async {
    t = tester;
    data = levelDataFor(id)!;
    // Every hint after the free one is bought with an ad that plays through.
    AdManager.stubRewardedForTest(() async => true);
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: id,
          number: id,
          title: data.title,
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
  VoidCallback? bulb() => t
      .widget<BouncyButton>(find.ancestor(
        of: find.text('💡'),
        matching: find.byType(BouncyButton),
      ))
      .onTap;

  int k(int r, int c) => r * data.size + c;
  int at(HintPlacement p) => k(p.r, p.c);

  /// What stands where, by kind.
  Map<int, ToolType> board() =>
      {for (final e in placed().entries) e.key: e.value.tool};
  Map<int, ToolType> solution() =>
      {for (final p in recordedSolution(data.id)) at(p): p.element.tool};

  Future<void> frames(int ms, {int step = 30}) async {
    for (var e = 0; e < ms; e += step) {
      await t.pump(Duration(milliseconds: step));
    }
  }

  /// Put down a piece of the player's own: pick it in the kit, tap the cell.
  Future<void> put(ToolType tool, int key) async {
    await t.tap(find.text(tool.label));
    await t.pump();
    final rect = t.getRect(find.byKey(const ValueKey('gameBoard')));
    await t.tapAt(rect.topLeft +
        GridGeometry(rect.width, data.size)
            .center(key ~/ data.size, key % data.size));
    await t.pump(const Duration(seconds: 1));
    expect(placed()[key]?.tool, tool, reason: 'no ${tool.name} landed on $key');
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

  /// Every piece of the kit is in exactly one place: the kit or the board.
  void expectKitAddsUp() {
    final down = <ToolType, int>{};
    for (final p in placed().values) {
      down[p.tool] = (down[p.tool] ?? 0) + 1;
    }
    for (final e in data.toolkit) {
      expect((kit()[e.type] ?? 0) + (down[e.type] ?? 0), e.count,
          reason: '${e.type.name} lost or doubled');
    }
  }

  testWidgets('a full board of wrong pieces still takes a hint',
      (tester) async {
    await open(tester, 66);
    // The board from the report: every piece down, none where it goes.
    await put(ToolType.shield, k(6, 2));
    await put(ToolType.arrowUp, k(6, 4));
    await put(ToolType.teleporter, k(5, 4));
    await put(ToolType.teleporter, k(3, 3));
    expect(kit().values.every((n) => n == 0), isTrue,
        reason: 'the whole kit is down');
    expect(find.text('×1'), findsOneWidget);
    expect(bulb(), isNotNull,
        reason: 'a hint in hand and a player stuck: the bulb has to work');

    final plan = hintOrder(data, recordedSolution(66));
    expect(at(plan.first), k(6, 5),
        reason: 'the checks below read the first hint as the UP at (6,5)');
    await hint();
    expect(placed()[k(6, 5)]?.tool, ToolType.arrowUp);
    expect(grid().hinted, {k(6, 5)});
    expect(
        board(),
        {
          k(6, 5): ToolType.arrowUp,
          k(6, 2): ToolType.shield,
          k(5, 4): ToolType.teleporter,
          k(3, 3): ToolType.teleporter,
        },
        reason: 'the only UP was the player\'s at (6,4), so that is the one '
            'that moved; nothing else is touched');
    expectKitAddsUp();

    // The rest of the hints, bought with ads, finish the board.
    for (var i = 1; i < plan.length; i++) {
      expect(bulb(), isNotNull);
      await hint();
      expectKitAddsUp();
    }
    expect(board(), solution());
    expect(grid().hinted, solution().keys.toSet());
    expect(simulate(data, placed()), SimOutcome.win);
    expect(bulb(), isNull, reason: 'every piece given, nothing left to sell');
  });

  testWidgets('on a board that is already right, a hint vouches for a piece',
      (tester) async {
    await open(tester, 66);
    for (final p in recordedSolution(66)) {
      await put(p.element.tool, at(p));
    }
    expect(board(), solution());
    expect(bulb(), isNotNull,
        reason: 'going dark here would tell the player the board is right '
            'without their running it');

    await hint();
    final first = hintOrder(data, recordedSolution(66)).first;
    expect(grid().hinted, {at(first)}, reason: 'locked in like a placed hint');
    expect(board(), solution(), reason: 'and nothing moved');
    expectKitAddsUp();
    expect(simulate(data, placed()), SimOutcome.win);
  });

  testWidgets('portals joined crosswise are taken up and joined right',
      (tester) async {
    await open(tester, 57);
    final sol = recordedSolution(57);
    final portals = [
      for (final p in sol)
        if (p.element.type == PlacedType.teleporter) p,
    ];
    HintPlacement mateOf(HintPlacement p) => portals.firstWhere(
        (q) => q.element.portalIndex == (p.element.portalIndex! ^ 1));
    final a = portals.first, b = mateOf(a);
    final c = portals.firstWhere((p) => p != a && p != b), d = mateOf(c);
    // Every piece on its own square, but the portals go down a, c, b, d and
    // each joins the one before it: a with c, b with d.
    for (final p in [a, c, b, d]) {
      await put(ToolType.teleporter, at(p));
    }
    for (final p in sol) {
      if (p.element.type != PlacedType.teleporter) {
        await put(p.element.tool, at(p));
      }
    }
    Map<int, int> links() => buildTeleportLinks(data, placed());
    expect(links()[at(a)], at(c), reason: 'the test needs the pairs crossed');
    expect(board(), solution());

    for (var i = 0; i < sol.length; i++) {
      expect(bulb(), isNotNull);
      await hint();
      expectKitAddsUp();
    }
    expect(links(),
        {at(a): at(b), at(b): at(a), at(c): at(d), at(d): at(c)});
    expect(grid().hinted, solution().keys.toSet());
    expect(simulate(data, placed()), SimOutcome.win);
    expect(bulb(), isNull);
  });
}
