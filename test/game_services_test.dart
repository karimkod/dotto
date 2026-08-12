// Achievements are optional decoration, so what matters is that they cannot
// break the game and that the "is this world finished" question is answered
// correctly — a world badge that fires one level early, or never, is the only
// failure a player would actually notice.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/levels.dart';
import 'package:dotto/services/game_services.dart';

void main() {
  setUp(GameServices.resetForTest);

  group('safety', () {
    test('stands down where there is no games platform', () {
      // No plugin host under test; kIsWeb is checked before dart:io so the web
      // build never calls Platform.
      expect(GameServices.supported, isFalse);
      expect(GameServices.signedIn, isFalse);
    });

    test('sign-in is a no-op rather than a crash', () async {
      // main() fires this before runApp.
      await expectLater(GameServices.signIn(), completes);
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
