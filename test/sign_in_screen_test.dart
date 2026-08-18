// The sign-in offer is the last thing between a new player and the game, so
// the property that matters is that both answers lead out of it. A screen that
// could be entered and not left would be worse than not asking at all.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/screens/sign_in_screen.dart';
import 'package:dotto/services/game_services.dart';

void main() {
  setUp(GameServices.resetForTest);

  Future<int> pumpScreen(WidgetTester tester, {required List<int> done}) async {
    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(onDone: () => done.add(1)),
    ));
    await tester.pump();
    return done.length;
  }

  testWidgets('it explains what signing in buys', (tester) async {
    final done = <int>[];
    await pumpScreen(tester, done: done);

    expect(find.text('Save your progress'), findsOneWidget);
    expect(find.textContaining('across devices'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Maybe later'), findsOneWidget);
    expect(done, isEmpty, reason: 'nothing happens until they answer');
  });

  testWidgets('skipping leaves immediately and answers the question',
      (tester) async {
    final done = <int>[];
    await pumpScreen(tester, done: done);

    await tester.tap(find.text('Maybe later'));
    await tester.pump();

    expect(done, hasLength(1), reason: 'skip goes straight on');
    expect(GameServices.needsSignInPrompt, isFalse,
        reason: 'declining is an answer — it must not be asked again');
  });

  testWidgets('a failed sign-in leaves without comment', (tester) async {
    // Under test there is no games platform, so ensureSignedIn returns false —
    // the same path as a player who cancels the platform dialog. It must move
    // on silently rather than reporting a failure they did not cause.
    final done = <int>[];
    await pumpScreen(tester, done: done);

    await tester.tap(find.text('Sign In'));
    // Not pumpAndSettle: the busy spinner animates forever, and in the app the
    // screen is navigated away from rather than settling.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(done, hasLength(1));
    expect(find.textContaining('failed'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
    expect(GameServices.needsSignInPrompt, isFalse,
        reason: 'being asked counts, whatever the platform answered');
  });

  testWidgets('an attempt that never answers can still be left',
      (tester) async {
    // The dead end this covers: "Maybe later" was disabled for the duration of
    // an attempt, and GamesServices.signIn is not guaranteed to answer. GameKit
    // calls its authenticate handler with neither a view controller nor an error
    // where there is no account to authenticate against, so the future stays
    // pending for the life of the process. With the screen unpoppable and both
    // buttons dead, force-quitting was the only way out of onboarding.
    final done = <int>[];
    final attempt = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(
        onDone: () => done.add(1),
        signIn: () => attempt.future,
      ),
    ));

    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the attempt is in flight');
    expect(done, isEmpty);

    await tester.tap(find.text('Maybe later'));
    await tester.pump();
    expect(done, hasLength(1), reason: 'the only exit has to stay open');

    // And the abandoned attempt must not then act on a screen already left.
    // onDone replaces the route, so this widget outlives the skip by a
    // transition, and a second call would push the menu twice.
    attempt.complete(true);
    await tester.pump(const Duration(seconds: 1));
    expect(done, hasLength(1),
        reason: 'answered once, whatever the platform says afterwards');
  });

  testWidgets('it cannot be dismissed without answering', (tester) async {
    final done = <int>[];
    await pumpScreen(tester, done: done);

    final scope = tester.widget(find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('PopScope'),
    )) as dynamic;
    expect(scope.canPop, isFalse);
  });

  group('when the offer is made at all', () {
    test('not once it has been made', () {
      GameServices.resetForTest(prompted: true);
      expect(GameServices.needsSignInPrompt, isFalse);
    });

    test('not where there is no games platform', () {
      // Web and the test runner. supported is false here, which is what makes
      // this assertion hold — on a device the other two conditions decide.
      GameServices.resetForTest();
      expect(GameServices.supported, isFalse);
      expect(GameServices.needsSignInPrompt, isFalse);
    });
  });
}
