// The settings screen and the two toggles behind it.
//
// The toggles matter more than they look: a player who turns sound off and
// still hears the game has been ignored, and there is no error to notice — the
// gate either works or the app quietly disobeys.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/screens/settings_screen.dart';
import 'package:dotto/settings/settings_store.dart';

void main() {
  // No plugin host under test, so SettingsStore keeps its in-memory defaults
  // and nothing is written to disk. Restore them between tests anyway, since
  // the store is process-global.
  setUp(() {
    SettingsStore.setSound(true);
    SettingsStore.setHaptics(true);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
  }

  test('both settings default to on', () {
    expect(SettingsStore.soundOn, isTrue);
    expect(SettingsStore.hapticsOn, isTrue);
  });

  test('a setting takes effect immediately, storage or not', () {
    // The write is fire-and-forget and fails silently here; the value the game
    // reads is the in-memory one, which must change on the spot.
    SettingsStore.setSound(false);
    expect(SettingsStore.soundOn, isFalse);
    SettingsStore.setSound(true);
    expect(SettingsStore.soundOn, isTrue);
  });

  testWidgets('the screen offers every setting', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);
    expect(find.text('Rate the app'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    // Reset progress is gone. Erasing a game is not something to leave one tap
    // away, and cloud save would restore it on the next sync regardless.
    expect(find.text('Reset progress'), findsNothing);

    // The About block sits past the fold on a short screen — the list has
    // grown — so scroll to it rather than asserting it is on screen at rest.
    await tester.scrollUntilVisible(
      find.text('Made by Reshaped'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Made by Reshaped'), findsOneWidget);
  });

  testWidgets('toggling sound changes the stored setting', (tester) async {
    await pumpSettings(tester);
    expect(SettingsStore.soundOn, isTrue);

    await tester.tap(find.text('Sound'));
    await tester.pump();
    expect(SettingsStore.soundOn, isFalse,
        reason: 'tapping the row must toggle, not just the switch itself');

    await tester.tap(find.text('Sound'));
    await tester.pump();
    expect(SettingsStore.soundOn, isTrue);
  });

  testWidgets('toggling haptics changes the stored setting', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Haptics'));
    await tester.pump();
    expect(SettingsStore.hapticsOn, isFalse);
  });
}
