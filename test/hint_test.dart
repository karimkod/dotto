// Hints hand the player a placement from the recorded solution, so the data
// behind them has to line up with the toolkit the level actually gives out. A
// hint naming a piece that is not in the kit, or a cell that already holds
// something, would either do nothing or quietly desync the counts.
//
// That the placements WIN is not asserted here — levels_solvable_test simulates
// exactly this data and is the proof. What is asserted here is the join between
// the solution data and the levels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/ads/ad_manager.dart';
import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/services/free_hint_service.dart';
import 'package:dotto/widgets/bouncy_button.dart';
import 'package:dotto/widgets/game_grid.dart';

void main() {
  // The free hint is a daily allowance held in a process-global service now,
  // so one test spending it would otherwise starve the next.
  setUp(FreeHintService.resetForTest);

  // Same for the ad stub: a test that leaves one standing would hand the next
  // one an ad that cannot exist under `flutter test`.
  tearDown(() => AdManager.stubRewardedForTest(null));

  final allLevels = [for (var n = 1; n <= kLevelCount; n++) n];

  test('every level with a toolkit has a hint to give', () {
    for (final n in allLevels) {
      // Level 1 hands out no pieces at all — its button correctly stays dead.
      if (levelDataFor(n)!.toolkit.isEmpty) continue;
      expect(recordedSolution(n), isNotEmpty,
          reason: 'level $n has pieces to place but no hint to offer');
    }
  });

  test('a level has a recorded placement for every piece in its kit', () {
    for (final n in allLevels) {
      final level = levelDataFor(n)!;
      final kit = <ToolType, int>{
        for (final e in level.toolkit) e.type: e.count,
      };
      final hinted = <ToolType, int>{};
      for (final p in recordedSolution(n)) {
        hinted[p.element.tool] = (hinted[p.element.tool] ?? 0) + 1;
      }
      // Every level is tight — no solution leaves a piece unused — so the
      // recorded solution must account for the whole kit, exactly.
      expect(hinted, equals(kit),
          reason: 'level $n: the recorded solution and the toolkit disagree, '
              'so hints would run out early or name a piece the player has '
              'not got');
    }
  });

  test('no recorded placement lands on an occupied cell', () {
    for (final n in allLevels) {
      final level = levelDataFor(n)!;
      for (final p in recordedSolution(n)) {
        expect(level.hasForcedPieceAt(p.r, p.c), isFalse,
            reason: 'level $n: hint targets (${p.r},${p.c}), which already '
                'holds a fixed piece');
        expect(p.r, inInclusiveRange(0, level.size - 1),
            reason: 'level $n: hint row off the board');
        expect(p.c, inInclusiveRange(0, level.size - 1),
            reason: 'level $n: hint column off the board');
      }
    }
  });

  testWidgets('the hint button places a piece and spends the free hint',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: 2,
          number: 2,
          title: 'Turn',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    // A continuous glow animation runs, so there is no settling to wait for.
    await tester.pump();

    // Level 2's kit is a single arrow, and the badge shows the one free hint.
    expect(find.text('💡'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);

    await tester.tap(find.text('💡'));
    // Three ~220ms pulses, then the piece commits with a ~600ms pop-in.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // Free hint spent — and level 2's kit is that one arrow, so the recorded
    // solution is now complete. With nothing left to reveal the button goes
    // quiet: no count, and no offer of an ad that could not buy anything.
    expect(find.text('×1'), findsNothing, reason: 'the daily hint is gone');
    expect(find.text('Ad'), findsNothing,
        reason: 'nothing left to reveal, so there is nothing to sell');
    expect(find.text('24h 0m'), findsNothing,
        reason: 'a bare countdown here reads as "locked until tomorrow" — it '
            'belongs in the ad dialog, as the other half of a choice');
    final hintButton = tester.widget<BouncyButton>(find.ancestor(
      of: find.text('💡'),
      matching: find.byType(BouncyButton),
    ));
    expect(hintButton.onTap, isNull,
        reason: 'the bulb stays put but disabled — a control that vanishes '
            'mid-level reads as a bug');
  });

  testWidgets('the first hint is the piece the board does not show you',
      (tester) async {
    // Level 22, "Trapdoor": shield through the mine, drop, climb back up
    // through the hole it left, turn for the exit. The hints used to open with
    // that last turn at (0,3) — the one you read straight off the exit. The
    // climb at (4,3) is the move nothing on the board points at: without it the
    // dot runs on along the bottom row and crashes three cells away.
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(
        level: Level(
          id: 22,
          number: 22,
          title: 'Trapdoor',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('💡'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    final placed = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<GameGridPainter>()
        .single
        .placed;
    expect(placed.keys, [4 * 5 + 3]);
    expect(placed[4 * 5 + 3]!.direction, Direction.up);
  });

  testWidgets('a second hint costs an ad, and declining costs nothing',
      (tester) async {
    // An ad that plays through to the reward.
    AdManager.stubRewardedForTest(() async => true);
    // Level 4's kit is two arrows, so there is still something to reveal after
    // the free hint is spent.
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: 4,
          number: 4,
          title: 'Two turns',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();

    Future<void> settleReveal() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await tester.tap(find.text('💡'));
    await settleReveal();
    expect(find.text('Ad'), findsOneWidget,
        reason: 'the free hint is gone, so the button offers the ad instead');

    // Decline: no ad watched, so no piece revealed.
    await tester.tap(find.text('💡'));
    await tester.pump();
    expect(find.text('Not now'), findsOneWidget);
    // The countdown lives here now: what waiting would cost, shown at the
    // moment the player is actually choosing between waiting and watching.
    expect(find.textContaining('back in 24h 0m'), findsOneWidget,
        reason: 'the dialog should say when the free hint returns');
    await tester.tap(find.text('Not now'));
    await settleReveal();

    // Accept: the second piece lands and the kit empties.
    await tester.tap(find.text('💡'));
    await tester.pump();
    await tester.tap(find.text('Watch'));
    await settleReveal();

    expect(find.text('Ready! Hit Play'), findsOneWidget,
        reason: 'the ad played through, so the second piece is on the board');
  });

  // The reward is the whole price of the hint. Both ways of not paying it —
  // closing the video early, and there being no video to close — have to leave
  // the player exactly where they were, with a word about why.
  testWidgets('an ad that does not pay out buys no hint', (tester) async {
    // Shown, then closed before the reward: what AdMob reports as not earned.
    AdManager.stubRewardedForTest(() async => false);
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: 4,
          number: 4,
          title: 'Two turns',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();

    Future<void> settleReveal() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    // Spend the free hint first, to get to the state where an ad is the offer.
    await tester.tap(find.text('💡'));
    await settleReveal();
    expect(find.text('Ad'), findsOneWidget);

    await tester.tap(find.text('💡'));
    await tester.pump();
    await tester.tap(find.text('Watch'));
    await settleReveal();

    expect(find.textContaining('did not finish'), findsOneWidget,
        reason: 'a tap that yields neither a hint nor a word reads as the game '
            'having taken something');
    expect(find.textContaining('1 left'), findsOneWidget,
        reason: 'the second piece is still in the kit — the reward was never '
            'earned, so no hint was given');
    // The offer stands: the ad is still there to be watched properly.
    expect(find.text('Ad'), findsOneWidget);
  });

  testWidgets('with no ad to serve, the button says when the free hint is back',
      (tester) async {
    // No stub, so AdManager cannot serve anything — the web build, an offline
    // player, or a unit with no fill.
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: 4,
          number: 4,
          title: 'Two turns',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('💡'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // There is a second arrow to reveal, but nothing to buy it with. The
    // countdown is the truth here, where on a button that COULD sell an ad it
    // was a lie.
    expect(find.text('Ad'), findsNothing,
        reason: 'no ad can be served, so the button must not offer one');
    expect(find.text('24h 0m'), findsOneWidget,
        reason: 'the wait is all that is actually on offer');
    final hintButton = tester.widget<BouncyButton>(find.ancestor(
      of: find.text('💡'),
      matching: find.byType(BouncyButton),
    ));
    expect(hintButton.onTap, isNull,
        reason: 'tapping could not produce a hint, so it does not take taps');
  });

  testWidgets('the button starts wiggling once the player goes quiet',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        level: Level(
          id: 2,
          number: 2,
          title: 'Turn',
          difficulty: Difficulty.easy,
          status: LevelStatus.unlocked,
        ),
      ),
    ));
    await tester.pump();

    double tilt() {
      // By key: the button also sits inside the bounce widget's own Transform.
      final t = tester
          .widget<Transform>(find.byKey(const ValueKey('hint-wiggle')));
      // Rotation shows up as the off-diagonal term of the 4x4.
      return t.transform.storage[1].abs();
    }

    expect(tilt(), lessThan(0.001), reason: 'it should sit still at first');

    // Past the idle threshold, with no placement in between.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tilt(), greaterThan(0.001),
        reason: 'a stuck player should get a nudge');

    // Any activity calls it off. Tapping the button itself counts.
    await tester.tap(find.text('💡'));
    await tester.pump();
    expect(tilt(), lessThan(0.001),
        reason: 'the nudge must stop the moment the player engages');

    // Let the reveal finish rather than leaving a timer pending.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  });
}
