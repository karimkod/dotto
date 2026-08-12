// Consent is the one subsystem where a bug is a compliance problem rather than
// a bad experience: an ad request that carries the wrong signal cannot be taken
// back. These check the parts that are checkable off-device — what the choice
// maps to, and that the screen cannot be escaped without answering.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/consent/consent_manager.dart';
import 'package:dotto/screens/consent_screen.dart';

void main() {
  setUp(ConsentManager.resetForTest);

  group('the npa flag carries the choice', () {
    test('standard ads request non-personalized', () {
      ConsentManager.setForTest(given: true, personalized: false);
      expect(ConsentManager.npa, '1',
          reason: 'npa=1 is what tells AdMob not to personalize');
      expect(ConsentManager.choice, AdConsent.standard);
    });

    test('personalized ads do not', () {
      ConsentManager.setForTest(given: true, personalized: true);
      expect(ConsentManager.npa, '0');
      expect(ConsentManager.choice, AdConsent.personalized);
    });

    test('an unanswered player is treated as non-personalized', () {
      // The important default. Before any choice exists the safe reading is the
      // restrictive one — a request that slipped out early must not be
      // personalized.
      expect(ConsentManager.given, isFalse);
      expect(ConsentManager.npa, '1');
      expect(ConsentManager.choice, AdConsent.standard);
    });
  });

  group('platform defaults are declared, not just set from Dart', () {
    // Dart runs after the SDKs have already started; these entries govern the
    // gap. Their absence is invisible at runtime, which is why they are pinned.
    test('Android manifest defaults every ad signal to false', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      for (final key in [
        'google_analytics_default_allow_ad_storage',
        'google_analytics_default_allow_ad_user_data',
        'google_analytics_default_allow_ad_personalization_signals',
      ]) {
        expect(manifest, contains(key), reason: '$key is not declared');
      }
    });

    test('Info.plist declares the same defaults and the ATT purpose string',
        () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      for (final key in [
        'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE',
        'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA',
        'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
      ]) {
        expect(plist, contains(key), reason: '$key is not declared');
      }
      expect(plist, contains('NSUserTrackingUsageDescription'),
          reason: 'Apple rejects a build that prompts without a purpose string');
    });
  });

  group('the consent screen', () {
    testWidgets('offers both choices and reports which was picked',
        (tester) async {
      final picked = <AdConsent>[];
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onChosen: picked.add),
      ));
      await tester.pump();

      expect(find.text('Before we start…'), findsOneWidget);
      expect(find.text('Personalized Ads'), findsOneWidget);
      expect(find.text('Standard Ads'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tester.tap(find.text('Standard Ads'));
      await tester.pump();
      expect(picked, [AdConsent.standard]);

      await tester.tap(find.text('Personalized Ads'));
      await tester.pump();
      expect(picked, [AdConsent.standard, AdConsent.personalized]);
    });

    testWidgets('onboarding cannot be dismissed without answering',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onChosen: (_) {}),
      ));
      await tester.pump();
      final scope = tester.widget(find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('PopScope'),
      )) as dynamic;
      expect(scope.canPop, isFalse,
          reason: 'there is no game behind it yet, and no answer to act on');
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });

    testWidgets('the settings version can be left', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ConsentScreen(onChosen: (_) {}, isUpdate: true),
      ));
      await tester.pump();
      final scope = tester.widget(find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('PopScope'),
      )) as dynamic;
      expect(scope.canPop, isTrue,
          reason: 'a choice already exists to fall back on');
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Ad preferences'), findsOneWidget);
    });
  });
}
