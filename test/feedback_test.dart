// Verifies the feedback button + dialog: tapping it and choosing OK persists an
// entry (via the in-memory stub store on the VM).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/feedback/feedback_store.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';

void main() {
  // Use a non-tutorial level (level 2 starts a delayed hint-hand timer that
  // would be left pending in these short tests).
  const level = Level(
    id: 5,
    number: 5,
    title: 'Around the Wall',
    difficulty: Difficulty.easy,
    status: LevelStatus.unlocked,
  );

  Future<void> settle(WidgetTester tester) async {
    // GameScreen runs a continuous glow animation, so no pumpAndSettle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('tapping feedback → OK saves an entry', (tester) async {
    final before = FeedbackStore.loadAll().length;

    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await settle(tester);
    expect(find.text('Level 5 — Feedback'), findsOneWidget);

    await tester.tap(find.text('✅  OK'));
    await settle(tester);

    final after = FeedbackStore.loadAll();
    expect(after.length, before + 1);
    expect(after.last.level, 5);
    expect(after.last.status, 'ok');
  });

  testWidgets('KO reveals a comment field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await settle(tester);
    await tester.tap(find.text('❌  KO'));
    await settle(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });
}
