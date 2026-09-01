// Consent is now UMP's job, which changes what is worth testing here. The
// choice itself, the consent state and the Consent Mode signals all live inside
// Google's SDK and cannot be reached from a unit test — so what is left is the
// wiring around it: whether ads are gated on UMP's answer, whether the
// pre-prompt appears only when there is a form behind it, and whether that
// screen can be escaped without continuing.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/consent/consent_manager.dart';
import 'package:dotto/screens/consent_screen.dart';

void main() {
  setUp(ConsentManager.resetForTest);

  group('ads wait for UMP', () {
    test('nothing may be requested before UMP has answered', () {
      // The default that matters. main() and the consent screen both gate
      // AdManager.init on this, so starting false is what stops an ad going
      // out ahead of the form.
      expect(ConsentManager.canRequestAds, isFalse);
    });

    test('the gate opens once UMP allows it', () {
      ConsentManager.setForTest(canRequestAds: true);
      expect(ConsentManager.canRequestAds, isTrue);
    });
  });

  group('the pre-prompt appears only when it leads somewhere', () {
    test('not on a platform with no UMP', () {
      // Web and the test runner have no consent SDK; an explainer for a form
      // that will never arrive is worse than no screen.
      ConsentManager.setForTest(formAvailable: true, attPending: true);
      expect(ConsentManager.needsPrePrompt, isFalse);
    });

    test('not once it has been seen', () {
      ConsentManager.setForTest(
          prePromptSeen: true, formAvailable: true, attPending: true);
      expect(ConsentManager.needsPrePrompt, isFalse);
    });

    test('not with neither a form nor a tracking prompt behind it', () {
      // Android outside the EEA: UMP has nothing to show, and there is no ATT
      // to ask either, so Continue would lead nowhere.
      ConsentManager.setForTest(formAvailable: false, attPending: false);
      expect(ConsentManager.needsPrePrompt, isFalse);
    });
  });

  // App Review rejected the build because a US reviewer on iPadOS never saw
  // the tracking prompt: the screen that asks it opened only when UMP had a
  // form, and UMP has one in the EEA only. The gate is a disjunction now, so
  // an iOS player anywhere is still asked.
  group('the pre-prompt is not EEA-only any more', () {
    /// Source with comments stripped, so a comment about the old rule cannot
    /// pass for the rule itself.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    // The flags cannot be exercised from here: `_supported` is false under
    // `flutter test`, so needsPrePrompt is false whatever they say. What is
    // checkable is the shape of the condition they feed.
    test('a pending tracking prompt is reason enough on its own', () {
      final src = code('lib/consent/consent_manager.dart');
      expect(src, contains('(_formAvailable || _attPending)'),
          reason: 'a form is one reason to open the screen, not the only one');
    });

    test('the tracking status is read before anything that can block', () {
      // ATT is a local question. Reading it after the connectivity wait would
      // put it behind an early return, and an iOS launch with no network would
      // owe a prompt it had no idea about.
      final src = code('lib/consent/consent_manager.dart');
      expect(src.indexOf('_refreshAttPending()'),
          lessThan(src.indexOf('await waitForInternet()')));
    });

    test('the tracking answer is not owed twice', () {
      // Cleared on request, so a launch whose UMP form never loaded does not
      // re-open the explainer next time for a prompt iOS will no longer show.
      final src = code('lib/consent/consent_manager.dart');
      expect(src, contains('_attPending = false;'));
    });
  });

  group('nothing trackable starts before Apple has been asked', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('boot gates the ad SDK on ATT as well as on UMP', () {
      // Apple's actual requirement: the request must come before any data is
      // collected that could track the player. UMP says yes to ads straight
      // away outside the EEA, so UMP on its own is not that gate.
      final src = code('lib/main.dart');
      expect(src, contains('ConsentManager.adsMayStartAtLaunch'));
    });

    test('the one UMP-only ad start left is the one after the prompt', () {
      // The consent screen may use UMP's answer alone, because ATT has just
      // been asked by the line above it. Anywhere earlier it would be the
      // rejection again.
      final src = code('lib/main.dart');
      expect(src.indexOf('if (ConsentManager.canRequestAds)'),
          greaterThan(src.indexOf('requestTrackingAuthorization()')));
    });

    test('and that gate is both halves', () {
      final src = code('lib/consent/consent_manager.dart');
      expect(src, contains('_canRequestAds && !needsPrePrompt'));
    });
  });

  group('the sign-in offer waits for the consent question', () {
    // The offer is one-shot, so the router holds it on [consentSettled]: a
    // launch where UMP was never reached must not put the platform's account
    // screen ahead of a consent screen the player is still owed.
    test('unsettled while UMP has never been reached', () {
      expect(ConsentManager.consentSettled, isFalse);
    });

    test('settled once UMP answered this launch, form or no form', () {
      ConsentManager.setForTest(answered: true);
      expect(ConsentManager.consentSettled, isTrue);
    });

    test('settled once the pre-prompt was seen on any earlier launch', () {
      ConsentManager.setForTest(prePromptSeen: true);
      expect(ConsentManager.consentSettled, isTrue);
    });
  });

  group('the consent mechanism is UMP, not ours', () {
    /// Source with comments stripped — otherwise a comment explaining that
    /// something was removed reads as the thing still being there.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('no manual Consent Mode calls remain', () {
      // Two sources of truth for consent is the failure mode this replaced:
      // UMP owns the state and emits the signals itself.
      final src = code('lib/consent/consent_manager.dart');
      expect(src, isNot(contains('setConsent(')),
          reason: 'Consent Mode is UMP\'s to emit');
      expect(src, contains('ConsentInformation.instance'),
          reason: 'consent state must come from UMP');
    });

    test('ad requests carry no consent flag of their own', () {
      final src = code('lib/ads/ad_manager.dart');
      expect(src, isNot(contains("'npa'")),
          reason: 'an npa extra would compete with what UMP already told the '
              'SDK');
    });

    test('reopening from settings resets UMP first', () {
      // Without the reset UMP considers consent obtained and shows nothing,
      // which is indistinguishable from a broken button.
      final src = code('lib/consent/consent_manager.dart');
      expect(src, contains('ConsentInformation.instance.reset()'));
    });
  });

  group('the pre-prompt screen', () {
    testWidgets('explains, offers one way on, and reports it', (tester) async {
      var continued = 0;
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onContinue: () => continued++),
      ));
      await tester.pump();

      expect(find.text('Before we start…'), findsOneWidget);
      expect(
          find.textContaining('you can choose how your data is used'),
          findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      // No choice here: the form makes that decision.
      expect(find.text('Personalized Ads'), findsNothing);
      expect(find.text('Standard Ads'), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(continued, 1);
    });

    testWidgets('names the tracking prompt where there is no form',
        (tester) async {
      // Outside the EEA the only thing behind Continue is Apple's prompt, so
      // promising a screen of choices would be promising something that never
      // arrives — and the app's own Settings cannot change the answer either.
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onContinue: () {}, hasAdChoices: false),
      ));
      await tester.pump();

      expect(find.text('Before we start…'), findsOneWidget);
      expect(find.textContaining('advertising ID'), findsOneWidget);
      expect(find.textContaining('On the next screen'), findsNothing);
      expect(find.textContaining('iOS Settings'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('cannot be dismissed instead of continued', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onContinue: () {}),
      ));
      await tester.pump();
      final scope = tester.widget(find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('PopScope'),
      )) as dynamic;
      expect(scope.canPop, isFalse,
          reason: 'there is no game behind it and nothing decided by leaving');
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });
  });

  test('the ATT purpose string is still declared', () {
    // Unchanged by the move to UMP — Apple rejects a build that prompts
    // without one, and the prompt still fires, now just before the form
    // rather than after it.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSUserTrackingUsageDescription'));
  });
}
