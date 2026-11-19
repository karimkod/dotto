// The run speed button. Players found the dot slow to reach the exit, so a
// button beside Play runs it at two or three times the game's own pace. Tested
// as a player meets it: the button says the speed, a faster run really gets
// there sooner, it can be changed in the middle of a run, and the choice is
// still there in the next level.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/settings/settings_store.dart';
import 'package:dotto/widgets/bouncy_button.dart';
import 'package:dotto/widgets/game_grid.dart';

// 3x3, start (2,0) heading right, exit (0,2), and one Up arrow, which wins at
// (2,2): four steps from start to exit, 1.6 s at the game's own pace.
const _level2 = Level(
  id: 2,
  number: 2,
  title: 'One Turn',
  difficulty: Difficulty.easy,
  status: LevelStatus.unlocked,
);

void main() {
  // Process-global, so put it back for whichever test runs next.
  tearDown(() => SettingsStore.setRunSpeed(1));

  final speedButton = find.byIcon(Icons.fast_forward_rounded);

  Future<void> openLevel(WidgetTester tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: GameScreen(level: _level2)));
    await tester.pump();
  }

  Future<void> placeArrow(WidgetTester tester) async {
    final board = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    final geo = GridGeometry(board.width, 3);
    await tester.tapAt(board.topLeft + geo.center(2, 2));
    await tester.pump();
  }

  Future<void> play(WidgetTester tester) async {
    await tester.tap(find.text('Play'));
    await tester.pump();
  }

  Future<void> wait(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// "Go!" is the line over Play for exactly as long as the dot is moving.
  bool running() => find.text('Go!').evaluate().isNotEmpty;

  /// Past the celebration, so that no timer of the win is left running.
  Future<void> finishWin(WidgetTester tester) async {
    expect(find.text('Try Again'), findsNothing, reason: 'the dot got there');
    await wait(tester, 3000);
    expect(find.text('Continue'), findsOneWidget);
  }

  testWidgets('the button shows the speed and steps 1×, 2×, 3× and back',
      (tester) async {
    await openLevel(tester);
    expect(find.text('1×'), findsOneWidget, reason: "the game's own pace");
    for (final (shown, stored) in [('2×', 2), ('3×', 3), ('1×', 1)]) {
      await tester.tap(speedButton);
      await tester.pump();
      expect(find.text(shown), findsOneWidget);
      expect(SettingsStore.runSpeed, stored);
    }
  });

  testWidgets('at 1× the run takes the 1.6 s it always has', (tester) async {
    // The control for the tests below: without it, a run that happened to be
    // over by 0.85 s would pass them at any speed.
    await openLevel(tester);
    await placeArrow(tester);
    await play(tester);
    await wait(tester, 850);
    expect(running(), isTrue);
    await wait(tester, 800);
    expect(running(), isFalse);
    await finishWin(tester);
  });

  testWidgets('at 2× the dot reaches the exit in half the time',
      (tester) async {
    await openLevel(tester);
    await placeArrow(tester);
    await tester.tap(speedButton);
    await tester.pump();
    await play(tester);
    await wait(tester, 850);
    expect(running(), isFalse);
    await finishWin(tester);
  });

  testWidgets('it changes the speed in the middle of a run', (tester) async {
    await openLevel(tester);
    await placeArrow(tester);
    await play(tester);
    await wait(tester, 450); // one step in, at the game's own pace
    expect(running(), isTrue);
    final button = tester.widget<BouncyButton>(
        find.ancestor(of: speedButton, matching: find.byType(BouncyButton)));
    expect(button.onTap, isNotNull,
        reason: 'Play is off while the dot runs, and this must not be');

    await tester.tap(speedButton);
    await tester.pump();
    expect(find.text('2×'), findsOneWidget);
    // Steps two to four come at 0.8, 1.0 and 1.2 s. At the game's own pace the
    // dot would still be a step short of the exit at 1.25 s.
    await wait(tester, 800);
    expect(running(), isFalse);
    await finishWin(tester);
  });

  testWidgets('the speed chosen is kept for the next level', (tester) async {
    await openLevel(tester);
    await tester.tap(speedButton);
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // out of the level
    await openLevel(tester);
    expect(find.text('2×'), findsOneWidget);
  });
}
