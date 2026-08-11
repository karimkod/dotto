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

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/widgets/bouncy_button.dart';

void main() {
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

    // Free hint spent: the count is replaced by the watch-an-ad icon.
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
  });

  testWidgets('a second hint costs an ad, and declining costs nothing',
      (tester) async {
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
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget,
        reason: 'the free hint is gone, so the button now offers an ad');

    // Decline: no ad watched, so no piece revealed.
    await tester.tap(find.text('💡'));
    await tester.pump();
    expect(find.text('Not now'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await settleReveal();

    // Accept: the second piece lands and the kit empties, which is what the
    // Play button waits for.
    await tester.tap(find.text('💡'));
    await tester.pump();
    await tester.tap(find.text('Watch'));
    await settleReveal();

    final play = tester.widget<BouncyButton>(find.ancestor(
      of: find.text('Play'),
      matching: find.byType(BouncyButton),
    ));
    expect(play.onTap, isNotNull,
        reason: 'both pieces are placed, so Play should be live');
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
    await tester.pump(const Duration(seconds: 31));
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
