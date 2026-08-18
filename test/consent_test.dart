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
      ConsentManager.setForTest(formAvailable: true);
      expect(ConsentManager.needsPrePrompt, isFalse);
    });

    test('not once it has been seen', () {
      ConsentManager.setForTest(prePromptSeen: true, formAvailable: true);
      expect(ConsentManager.needsPrePrompt, isFalse);
    });

    test('not where UMP has no form to show', () {
      // Outside the EEA there is usually nothing behind Continue.
      ConsentManager.setForTest(formAvailable: false);
      expect(ConsentManager.needsPrePrompt, isFalse);
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
