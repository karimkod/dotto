// Verifies the feedback button + dialog: tapping it and choosing OK persists an
// entry (via the in-memory stub store on the VM).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/feedback/feedback_store.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/screens/game_screen.dart';

void main() {
  const level2 = Level(
    id: 2,
    number: 2,
    title: 'One Turn',
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

    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await settle(tester);
    expect(find.text('Level 2 — Feedback'), findsOneWidget);

    await tester.tap(find.text('✅  OK'));
    await settle(tester);

    final after = FeedbackStore.loadAll();
    expect(after.length, before + 1);
    expect(after.last.level, 2);
    expect(after.last.status, 'ok');
  });

  testWidgets('KO reveals a comment field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen(level: level2)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await settle(tester);
    await tester.tap(find.text('❌  KO'));
    await settle(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });
}
