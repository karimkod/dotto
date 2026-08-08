// Basic smoke test for the Dotto main menu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/main.dart';

void main() {
  testWidgets('Dotto menu renders title and play button', (tester) async {
    await tester.pumpWidget(const DottoApp());
    await tester.pump();

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
  });
}
