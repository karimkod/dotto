// Basic smoke test for the Dotto main menu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/main.dart';

void main() {
  testWidgets('Dotto opens on the splash, then the menu', (tester) async {
    await tester.pumpWidget(const DottoApp());
    await tester.pump();

    // The app now opens on the splash rather than straight into the menu.
    expect(find.text('DOTTO'), findsOneWidget,
        reason: 'the opening mark comes first');
    expect(find.text('Level 1'), findsNothing);

    // 1800ms of opening, then a 450ms cross-fade into whatever comes next.
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    // Wordmark.
    expect(find.text('Dotto'), findsOneWidget);
    // A fresh player has no progress, so the climb starts at level 1 — the only
    // unlocked level, and what the play button points at.
    expect(find.text('Level 1'), findsOneWidget);
    // Difficulty badge for level 1 (Easy).
    expect(find.text('Easy'), findsOneWidget);
    // Dev-only "new level" button (tests run in debug mode).
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    // Everything past the frontier is drawn locked, not merely unplayable — the
    // padlock is what tells the player the climb is gated at all.
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    // The achievements shortcut on the left rail is a trophy, whatever the
    // sign-in state — it never wore a padlock over it.
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
  });
}
