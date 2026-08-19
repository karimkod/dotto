// The profile screen's three answers to "who is this player".
//
// It used to have two, and the missing one is the bug: a platform that answered
// with nobody was drawn exactly like a platform that had not answered yet, and
// both were drawn as a loaded profile — the word "Player" over a placeholder
// avatar, with nothing to tap and no way back. On iOS that was every launch
// after the one the player signed in on, because nothing re-established the
// GameKit session, so the state the screen could not express was the state it
// was usually in.
//
// What is pinned here is that the three states are distinct and that each one
// offers what it should. The platform itself is unreachable under test —
// `GameServices.supported` is false with no plugin host — so the signed-out
// route is the one a widget test can walk end to end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/levels.dart';
import 'package:dotto/screens/profile_screen.dart';
import 'package:dotto/services/game_services.dart';

void main() {
  setUp(GameServices.resetForTest);

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('signed out, the offer stands in for the gamer tag',
      (tester) async {
    await pumpProfile(tester);

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    // Signed out is decided before the fetch state and on its own: there is
    // nobody to fetch, so neither the spinner nor the failure belongs here.
    expect(find.text('Profile unavailable'), findsNothing);
    expect(find.text('Try Again'), findsNothing);
    expect(find.text('Player'), findsNothing);
  });

  testWidgets('the stats below belong to the player either way',
      (tester) async {
    // They are read from local progress, not from the platform. A player who
    // is signed out — or whose profile would not load — has still played every
    // level they have played, and the screen must not imply otherwise.
    await pumpProfile(tester);

    expect(find.text('Levels'), findsOneWidget);
    expect(find.text('0 / $kLevelCount'), findsOneWidget);
    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
    expect(find.text('Hints used'), findsOneWidget);
    expect(find.text('0% complete'), findsOneWidget);
  });

  testWidgets('the achievement tile says why it has no count yet',
      (tester) async {
    await pumpProfile(tester);

    // Signed out the denominator is still true and still worth reading, and
    // the subtitle is what makes an unfilled tile legible rather than broken.
    expect(find.text('${GameServices.achievementCount}'), findsOneWidget);
    expect(find.text('sign in to track'), findsOneWidget);
  });

  testWidgets('leaving while the platform is still being asked is safe',
      (tester) async {
    // The fetches outlive the route whenever a player opens the profile and
    // backs straight out of it — on a real device they are platform round
    // trips, and the profile one can now sign in on its way through, which is
    // slower again. A setState landing on a disposed State is a crash on a
    // back button.
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
