// Achievements are optional decoration, so what matters is that they cannot
// break the game and that the "is this world finished" question is answered
// correctly — a world badge that fires one level early, or never, is the only
// failure a player would actually notice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dotto/data/levels.dart';
import 'package:dotto/services/game_services.dart';

void main() {
  setUp(GameServices.resetForTest);

  group('signing in', () {
    test('the service is named for the platform the player would use', () {
      // "Sign in to game services" meant nothing on either platform. Under
      // test there is no Platform to ask, so the neutral fallback is what
      // shows here; on a device it reads Play Games or Game Center.
      expect(GameServices.platformName, isNotEmpty);
    });

    test('asking to sign in without a platform fails rather than throws', () {
      // The Achievements row calls this on tap; a throw would be a crash on a
      // button press.
      expect(GameServices.ensureSignedIn(), completion(isFalse));
    });

    test('a sign-in cannot wait forever', () async {
      // GamesServices.signIn hands its result to GameKit's authenticate handler
      // and answers nothing until that handler fires. Where there is no account
      // to authenticate against it is not called at all, so the future stays
      // pending for the life of the process: seen on a simulator with no Apple
      // Account, and reachable on a device with Game Center off under Screen
      // Time. It was the one platform call in this file with no deadline, and
      // the onboarding spinner was what waited on it.
      //
      // The wait itself cannot be exercised here: `supported` is false under
      // test, so ensureSignedIn returns before reaching the platform. The
      // deadline's existence and its bounds are what can be pinned.
      expect(GameServices.signInDeadline, lessThan(const Duration(minutes: 5)),
          reason: 'a deadline that long is not a deadline');
      expect(
          GameServices.signInDeadline, greaterThan(const Duration(seconds: 30)),
          reason: "the player may be typing a password into Game Center's own "
              'sheet, and cutting that short fails a sign-in that was working');

      // The constant existing says nothing about it being applied, and applying
      // it is the whole fix.
      final src = File('lib/services/game_services.dart').readAsStringSync();
      expect(src, contains('GamesServices.signIn().timeout('),
          reason: 'an unbounded signIn is the hang this guards against');
    });

    test('a sign-in is remembered across launches', () async {
      // The bug this covers: sign in, come back, tap Achievements, get asked to
      // sign in again. Nothing was written down, so every launch re-derived the
      // answer from a platform probe that is allowed to say "no" for a slow
      // network — and a "no" sent the player back to the prompt.
      SharedPreferences.setMockInitialValues({
        'sign_in_prompted': true,
        'signed_in': true,
      });
      await GameServices.init();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('signed_in'), isTrue,
          reason: 'init must not clear what a real sign-in wrote');
      // Reading it back is all that can be checked here: `supported` is false
      // under test, so the flag is deliberately not honoured — a remembered
      // sign-in from another install must not claim an account that this
      // platform has no way to reach.
      expect(GameServices.signedIn, isFalse);
    });

    test('restoring state cannot undo a remembered sign-in', () async {
      // restoreSignInState runs on the launch path and may only ever turn
      // sign-in on. It used to assign the probe's answer straight onto the
      // flag, so a cold start before Play Games had finished its own automatic
      // sign-in silently signed the player out.
      SharedPreferences.setMockInitialValues({'signed_in': true});
      await GameServices.init();
      await expectLater(GameServices.restoreSignInState(), completes);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('signed_in'), isTrue);
    });

    test('a remembered sign-in is re-established, not just believed', () async {
      // The bug: on iOS, GamesServices.signIn is the only thing that installs
      // GameKit's authenticate handler. restoreSignInState used to return early
      // whenever the remembered flag was set, so every launch after the one the
      // player signed in on left GKLocalPlayer unauthenticated for the life of
      // the process — the player stream answered nil, and the profile screen,
      // reported achievements and saved games all failed silently behind it.
      //
      // Unreachable from a test: `supported` is false here, so the branch
      // returns before touching the platform. What can be pinned is that the
      // remembered-sign-in path leads to a real platform call rather than an
      // early return.
      final src = File('lib/services/game_services.dart').readAsStringSync();
      final restore = src.substring(src.indexOf('static Future<void> '
          'restoreSignInState()'));
      expect(restore.substring(0, restore.indexOf('static Future<Player')),
          contains('_signInNow('),
          reason: 'a launch that only reads the flag never authenticates, and '
              'everything behind the platform session stays dark');
    });

    test('the launch re-authentication is bounded, and tighter than a sign-in',
        () {
      // What waits on this one is the cloud pull and the last step of
      // onboarding, and there is no dialog and no password behind it — so the
      // 90 seconds that make sense for a player typing into Game Center's sheet
      // would be a minute and a half of opening time here.
      expect(GameServices.reauthDeadline, lessThan(GameServices.signInDeadline),
          reason: 'a silent re-auth must not cost what an interactive one may');
      expect(GameServices.reauthDeadline, greaterThan(const Duration(seconds: 5)),
          reason: 'too short and it fails a session that was coming back');
    });

    test('a remembered sign-in survives a re-authentication that fails',
        () async {
      // The never-demote rule, at the one new place that could break it. A
      // launch that could not reach the platform is not a player who signed
      // out, and dropping the flag would put the one-shot onboarding offer back
      // in front of someone who has already answered it.
      SharedPreferences.setMockInitialValues({'signed_in': true});
      await GameServices.init();
      await expectLater(GameServices.restoreSignInState(), completes);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('signed_in'), isTrue);
    });

    test('an unanswered profile is retried rather than given up on', () async {
      // The remembered sign-in can outlive the platform session behind it — an
      // account signed out from the Play Games app, a Game Center session this
      // process never authenticated, an Android cold start that has not
      // finished. playerProfile used to return the first null straight to the
      // screen, which drew a nameless "Player" and stayed that way.
      //
      // showAchievements has recovered from the same thing for a while; this
      // asserts the profile path now does too.
      final src = File('lib/services/game_services.dart').readAsStringSync();
      final profile = src.substring(
          src.indexOf('static Future<PlayerProfile?> playerProfile()'));
      final body = profile.substring(0, profile.indexOf('static Future<Player'
          'Profile?> _readPlayer()'));
      expect(body, contains('_signInNow('),
          reason: 'a null profile for a signed-in player is a stale session, '
              'and asking the same dead session again would answer the same');
      expect('_readPlayer('.allMatches(body).length, greaterThanOrEqualTo(2),
          reason: 'signing in again is only worth it if the answer is re-read');
    });

    test('showing achievements now signs in first, and still reports back',
        () async {
      // showAchievements no longer needs the caller to have signed in — it
      // does it — but must still answer false when it could not, so the
      // caller can say something useful.
      expect(GameServices.signedIn, isFalse);
      await expectLater(GameServices.showAchievements(), completion(isFalse));
    });

    test('a failed showAchievements leaves the reason readable', () async {
      // The snackbar is chosen from `signedIn` after the call: no account means
      // "sign in", an account means "could not open". Getting this wrong is the
      // bug it exists for — a player who had just completed the Play Games
      // account picker was told to sign in, as if it had failed.
      await expectLater(GameServices.showAchievements(), completion(isFalse));
      expect(GameServices.signedIn, isFalse,
          reason: 'nothing signed in, so the sign-in message is the right one');
    });
  });

  group('safety', () {
    test('stands down where there is no games platform', () {
      // No plugin host under test; kIsWeb is checked before dart:io so the web
      // build never calls Platform.
      expect(GameServices.supported, isFalse);
      expect(GameServices.signedIn, isFalse);
    });

    test('restoring sign-in state is a no-op rather than a crash', () async {
      // main() fires this before runApp. With nothing remembered it reads the
      // state and never signs in: a player who has not chosen this may not meet
      // the platform's account picker on the launch path.
      await expectLater(GameServices.restoreSignInState(), completes);
      expect(GameServices.signedIn, isFalse);
    });

    test('showing achievements reports failure instead of throwing', () async {
      await expectLater(GameServices.showAchievements(), completion(isFalse));
    });

    test('reporting a completion while unsupported does nothing', () {
      // Sits on the win path, so a throw here would break finishing a level.
      expect(() {
        GameServices.onLevelCompleted(
          world: 7,
          worldFinished: true,
          totalCompleted: kLevelCount,
          levelCount: kLevelCount,
          lifetimeHints: 50,
        );
        GameServices.onHintUsed(99);
      }, returnsNormally);
    });
  });

  group('achievement ids', () {
    test('there are ten, and none is blank', () {
      expect(GameServices.allIds, hasLength(10));
      for (final (ios, android) in GameServices.allIds) {
        expect(ios, isNotEmpty);
        expect(android, isNotEmpty,
            reason: 'a blank Android id would be sent as an empty string');
      }
    });

    test('every id is distinct', () {
      // The Play ids differ only in their last character or two
      // (…EAIQAA, …EAIQAQ, …EAIQAg). A transposition would unlock the wrong
      // badge silently — the platform has no idea which one was meant.
      final ios = GameServices.allIds.map((p) => p.$1).toList();
      final android = GameServices.allIds.map((p) => p.$2).toList();
      expect(ios.toSet(), hasLength(ios.length), reason: 'duplicate iOS id');
      expect(android.toSet(), hasLength(android.length),
          reason: 'duplicate Android id — two achievements point at one badge');
    });

    test('the id shapes match their platforms', () {
      for (final (ios, android) in GameServices.allIds) {
        expect(ios, startsWith('com.karimkod.dotto.'),
            reason: 'Game Center ids are reverse-domain');
        expect(android, startsWith('CgkI'),
            reason: 'Play ids are generated and all share this prefix');
      }
    });

    test('Android is only switched on when the manifest backs it', () {
      // The gate and the native config have to move together. Signing in
      // without the application id declared can take the app down at launch,
      // and it is a native failure that no Dart try/catch contains — so this
      // asserts the wiring exists rather than pinning the flag to a value.
      if (!GameServices.androidReady) return;

      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('com.google.android.gms.games.APP_ID'),
          reason: 'Play Games sign-in is on but the manifest declares no '
              'application id — the SDK fails as it starts');
      expect(manifest, contains('android:value="@string/app_id"'),
          reason: 'the id must be a @string reference: an all-digits literal '
              'is parsed as an integer and overflows');

      final res = File('android/app/src/main/res/values/games-ids.xml')
          .readAsStringSync();
      expect(res, contains('name="app_id"'),
          reason: 'the manifest points at @string/app_id, which must exist');
    });
  });

  group('world membership', () {
    test('every level belongs to exactly one world', () {
      final seen = <int>{};
      for (var w = 1; w <= 7; w++) {
        for (final n in levelsInWorld(w)) {
          expect(seen.add(n), isTrue, reason: 'level $n counted twice');
        }
      }
      expect(seen.length, kLevelCount,
          reason: 'every level must belong to some world');
    });

    test('no world is empty', () {
      // An empty world would be "complete" from the first level won, firing its
      // badge immediately.
      for (var w = 1; w <= 7; w++) {
        expect(levelsInWorld(w), isNotEmpty, reason: 'world $w has no levels');
      }
    });
  });

  group('world completion', () {
    test('is false until the very last level of the world is in', () {
      final levels = levelsInWorld(3).toList();
      final allButLast = levels.take(levels.length - 1).toSet();
      expect(isWorldComplete(3, allButLast), isFalse,
          reason: 'one level short is not a completed world');
      expect(isWorldComplete(3, {...allButLast, levels.last}), isTrue);
    });

    test('is not fooled by a count from another world', () {
      // Finishing all of World 1 must not complete World 2, however many
      // levels are in the set.
      final world1 = levelsInWorld(1).toSet();
      expect(isWorldComplete(1, world1), isTrue);
      expect(isWorldComplete(2, world1), isFalse);
    });

    test('finishing everything completes every world', () {
      final all = {for (var n = 1; n <= kLevelCount; n++) n};
      for (var w = 1; w <= 7; w++) {
        expect(isWorldComplete(w, all), isTrue, reason: 'world $w');
      }
    });

    test('an empty save completes nothing', () {
      for (var w = 1; w <= 7; w++) {
        expect(isWorldComplete(w, const <int>{}), isFalse, reason: 'world $w');
      }
    });
  });
}
