// The onboarding funnel. Its whole value is being comparable between steps, so
// the property worth guarding is that the last step cannot fire without the
// earlier ones — a completion count that included every returning player would
// read as ~100% forever and hide whatever the funnel was built to find.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/analytics/analytics_service.dart';
import 'package:dotto/screens/consent_screen.dart';
import 'package:dotto/screens/sign_in_screen.dart';
import 'package:dotto/services/game_services.dart';

void main() {
  setUp(() {
    Analytics.resetOnboardingForTest();
    GameServices.resetForTest();
  });

  group('the funnel only closes if it opened', () {
    test('a returning player reports nothing', () {
      // The menu is reached on every launch; onboarding is not. Without this
      // guard the two would be indistinguishable in the data.
      expect(Analytics.onboardingRan, isFalse);
      Analytics.onboardingCompleted();
      expect(Analytics.onboardingRan, isFalse,
          reason: 'nothing to close, so nothing was reported');
    });

    test('a step marks the funnel as running', () {
      Analytics.onboardingConsentShown();
      expect(Analytics.onboardingRan, isTrue);
    });

    test('completion fires once, not once per rebuild', () {
      // _menu() is called from a builder, which can run many times.
      Analytics.onboardingSignInShown();
      expect(Analytics.onboardingRan, isTrue);

      Analytics.onboardingCompleted();
      expect(Analytics.onboardingRan, isFalse);

      // A second pass through the builder must not report a second completion.
      Analytics.onboardingCompleted();
      expect(Analytics.onboardingRan, isFalse);
    });

    test('any step is enough to open it', () {
      // A player outside the EEA sees no consent screen at all, but still goes
      // through the sign-in offer — their completion has to count.
      Analytics.onboardingSignInSkipped();
      expect(Analytics.onboardingRan, isTrue);
    });
  });

  group('screens report themselves', () {
    testWidgets('the consent pre-prompt, on mount and on continue',
        (tester) async {
      var continued = 0;
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onContinue: () => continued++),
      ));
      await tester.pump();
      expect(Analytics.onboardingRan, isTrue,
          reason: 'showing the screen is the first funnel step');

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(continued, 1, reason: 'the event must not swallow the callback');
    });

    testWidgets('the sign-in offer, on mount', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(onDone: () {}),
      ));
      await tester.pump();
      expect(Analytics.onboardingRan, isTrue);
    });

    testWidgets('skipping still reports, and still leaves', (tester) async {
      var done = 0;
      await tester.pumpWidget(MaterialApp(
        home: SignInScreen(onDone: () => done++),
      ));
      await tester.pump();
      await tester.tap(find.text('Maybe later'));
      await tester.pump();
      expect(done, 1);
    });
  });

  test('every event is safe with analytics switched off', () {
    // These sit on the launch path. Under test Firebase is not running, so all
    // twelve must be no-ops rather than throwing before the game can start.
    expect(() {
      Analytics.onboardingConsentShown();
      Analytics.onboardingConsentCompleted();
      Analytics.onboardingUmpShown();
      Analytics.onboardingUmpCompleted();
      Analytics.onboardingAttShown();
      Analytics.onboardingAttAccepted();
      Analytics.onboardingAttDenied();
      Analytics.onboardingSignInShown();
      Analytics.onboardingSignInAccepted();
      Analytics.onboardingSignInSkipped();
      Analytics.onboardingSignInFailed();
      Analytics.onboardingCompleted();
    }, returnsNormally);
  });
}
