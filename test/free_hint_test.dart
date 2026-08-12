// The daily free hint. Two things here are worth guarding: the 24-hour window,
// because a player who is told to wait a day and waits a day expects it back,
// and the non-cumulative rule, because a hint that quietly stacked would change
// what the ads are for.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/services/free_hint_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 12);
  int ms(DateTime t) => t.millisecondsSinceEpoch;

  setUp(FreeHintService.resetForTest);

  group('availability', () {
    test('a hint is waiting for a player who has never used one', () {
      expect(FreeHintService.availableAt(now), isTrue);
      expect(FreeHintService.remainingAt(now), Duration.zero);
    });

    test('spending it takes it away', () {
      expect(FreeHintService.spendAt(now), isTrue);
      expect(FreeHintService.availableAt(now), isFalse);
    });

    test('it cannot be spent twice in the same moment', () {
      expect(FreeHintService.spendAt(now), isTrue);
      expect(FreeHintService.spendAt(now), isFalse);
    });

    test('it comes back after exactly 24 hours, not before', () {
      FreeHintService.spendAt(now);
      expect(FreeHintService.availableAt(now.add(const Duration(hours: 23))),
          isFalse);
      expect(
          FreeHintService.availableAt(
              now.add(const Duration(hours: 23, minutes: 59))),
          isFalse);
      expect(FreeHintService.availableAt(now.add(const Duration(hours: 24))),
          isTrue);
    });

    test('it does not stack, however long it is left', () {
      // The whole point of "non-cumulative": a week away earns one hint, not
      // seven. There is no counter to grow — availability is a yes or a no.
      FreeHintService.spendAt(now);
      final later = now.add(const Duration(days: 7));
      expect(FreeHintService.availableAt(later), isTrue);
      expect(FreeHintService.spendAt(later), isTrue);
      expect(FreeHintService.spendAt(later), isFalse,
          reason: 'a week of waiting still buys exactly one hint');
    });
  });

  group('a clock that moves backwards does not trap the player', () {
    test('a hint is granted rather than withheld', () {
      // A timezone change or a wound-back clock would otherwise mean waiting
      // however far back it went. Being generous about a rare edge beats
      // locking someone out for a year.
      FreeHintService.spendAt(now);
      final earlier = now.subtract(const Duration(days: 3));
      expect(FreeHintService.availableAt(earlier), isTrue);
    });
  });

  group('the countdown label', () {
    test('is empty when a hint is ready', () {
      expect(FreeHintService.remainingLabel(now), '');
    });

    test('reads hours and minutes', () {
      FreeHintService.resetForTest(
        usedAt: ms(now.subtract(const Duration(hours: 9, minutes: 28))),
      );
      expect(FreeHintService.remainingLabel(now), '14h 32m');
    });

    test('drops the hours under an hour', () {
      FreeHintService.resetForTest(
        usedAt: ms(now.subtract(const Duration(hours: 23, minutes: 20))),
      );
      expect(FreeHintService.remainingLabel(now), '40m');
    });

    test('never reads zero while still counting', () {
      // Under a minute left is still a wait; showing "0m" beside a button that
      // does nothing reads as broken.
      FreeHintService.resetForTest(
        usedAt: ms(now.subtract(
            const Duration(hours: 23, minutes: 59, seconds: 40))),
      );
      expect(FreeHintService.remainingLabel(now), '1m');
    });
  });

  test('the remaining time shrinks as the day passes', () {
    FreeHintService.spendAt(now);
    expect(FreeHintService.remainingAt(now).inHours, 24);
    expect(
        FreeHintService.remainingAt(now.add(const Duration(hours: 10))).inHours,
        14);
    expect(FreeHintService.remainingAt(now.add(const Duration(hours: 24))),
        Duration.zero);
  });
}
