// The sound switches, reachable from inside a level.
//
// Players asked to be able to mute the game without leaving the board, so what
// is tested is what a player would do: open a level, turn the sound off from
// there, and still be in the level afterwards — in the middle of a run too,
// which is when the game makes its noise.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/screens/settings_screen.dart';
import 'package:dotto/services/free_hint_service.dart';
import 'package:dotto/services/music_service.dart';
import 'package:dotto/settings/settings_store.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/widgets/settings_tiles.dart';

Level _level(int n) => Level(
      id: n,
      number: n,
      title: 'level $n',
      difficulty: Difficulty.easy,
      status: LevelStatus.unlocked,
    );

void main() {
  setUp(FreeHintService.resetForTest);

  // Process-global, so put them back for whichever test runs next.
  tearDown(() {
    SettingsStore.setSound(true);
    SettingsStore.setHaptics(true);
    MusicService.setEnabled(true);
  });

  Future<void> openLevel(WidgetTester tester, int n) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(level: _level(n))));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
  }

  /// The header, above the sheet: a tap there lands on the barrier and closes
  /// it. (Were the barrier missing, it would hit the title, not the back
  /// button — so a failure here shows up as the sheet staying open.)
  Future<void> closeSettings(WidgetTester tester) async {
    await tester.tapAt(tester.getCenter(find.text('Level 2')));
    await settle(tester);
  }

  bool switchFor(WidgetTester tester, String label) => tester
      .widget<Switch>(find.descendant(
        of: find.ancestor(
            of: find.text(label), matching: find.byType(SettingsToggleRow)),
        matching: find.byType(Switch),
      ))
      .value;

  testWidgets('a level opens the sound switches over the board',
      (tester) async {
    // Set before the level opens, to show the sheet reads the live setting.
    SettingsStore.setHaptics(false);
    await openLevel(tester, 2);
    expect(find.text('Sound'), findsNothing);

    await openSettings(tester);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);
    expect(switchFor(tester, 'Sound'), isTrue);
    expect(switchFor(tester, 'Haptics'), isFalse);

    await tester.tap(find.text('Sound'));
    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(SettingsStore.soundOn, isFalse);
    expect(MusicService.isEnabled, isFalse);
    expect(switchFor(tester, 'Sound'), isFalse);

    await closeSettings(tester);
    expect(find.text('Sound'), findsNothing);
    expect(find.text('Level 2'), findsOneWidget,
        reason: 'closing settings leaves the player in the level');
    expect(SettingsStore.soundOn, isFalse, reason: 'and it stays muted');
  });

  testWidgets('the switches work in the middle of a run', (tester) async {
    await openLevel(tester, 2);
    // Nothing placed, so the dot runs straight off the board.
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(find.text('RESTART'), findsOneWidget, reason: 'the run is on');

    await openSettings(tester);
    await tester.tap(find.text('Sound'));
    await tester.pump();
    expect(SettingsStore.soundOn, isFalse);

    await closeSettings(tester);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Try Again'), findsOneWidget,
        reason: 'the run carried on under the sheet and played out');
  });

  testWidgets('the settings screen has the same three switches',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    for (final label in ['Sound', 'Music', 'Haptics']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(MusicService.isEnabled, isFalse);
  });

  testWidgets('the header fits a 320-wide phone', (tester) async {
    await openLevel(tester, 2);
    // Solved first, at the default size, so the footer is down to its short
    // line. Its long one ("1 left — or Play…") wraps at this width in the test
    // font, which draws every glyph a full em wide — though not in a real one.
    final board = tester.getRect(find.byKey(const ValueKey('gameBoard')));
    await tester
        .tapAt(board.topLeft + GridGeometry(board.width, 3).center(2, 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ready! Hit Play'), findsOneWidget);

    // What is left to fit is the header: three tiles and the title, and in
    // that font "Level 2" alone takes half the row. The title has to give way
    // rather than push the gear off the edge.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    // An overflow is reported as an error, which takeException hands back.
    expect(tester.takeException(), isNull);
  });
}
