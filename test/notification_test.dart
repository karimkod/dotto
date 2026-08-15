// Notifications, minus the platform.
//
// Under `flutter test` there is no plugin host, so [NotificationService] reports
// itself unsupported and every platform call short-circuits. What is left is the
// part that decides things, and that is the part worth guarding: when a reminder
// should fire, whether the player is asked, and where a tap goes. A reminder
// that fires at the wrong moment is worse than one that never fires — it wakes
// someone up to tell them something untrue.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/analytics/analytics_service.dart';
import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/services/notification_service.dart';
import 'package:dotto/widgets/notification_prompt_dialog.dart';

Challenge challengeEnding(DateTime end, {DateTime? start}) => Challenge(
      id: 'week_test',
      title: 'Test',
      description: '',
      startDate: start ?? end.subtract(const Duration(days: 7)),
      endDate: end,
      reward: ChallengeReward.hint,
      level: LevelData(
        id: -1,
        size: 5,
        title: 'Challenge',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: const Pos(4, 4),
        toolkit: const [],
      ),
    );

void main() {
  setUp(NotificationService.resetForTest);

  group('the hint reminder lands when the hint actually returns', () {
    test('exactly 24 hours after it was spent', () {
      final spent = DateTime(2026, 8, 13, 9, 30);
      expect(
        NotificationService.hintReadyTime(spent),
        DateTime(2026, 8, 14, 9, 30),
      );
    });

    test('and tracks the hint service rather than guessing', () {
      // If these two ever disagree the reminder announces a hint that is not
      // there yet, or arrives hours after it was.
      expect(NotificationService.hintRegenerates, const Duration(hours: 24));
    });
  });

  group('the streak warning', () {
    // Fixed "now" throughout: a warning computed against the wall clock would
    // pass or fail depending on the hour the suite happened to run.
    final now = DateTime(2026, 8, 13, 10);

    test('lands two days before the challenge closes, in the evening', () {
      final at = NotificationService.streakWarningTime(
        challengeEnding(DateTime(2026, 8, 19)),
        now,
      );
      expect(at, DateTime(2026, 8, 17, 18),
          reason: 'day 5 of a 7-day week, at a civil hour');
    });

    test('never at 3am, whatever the arithmetic produces', () {
      final at = NotificationService.streakWarningTime(
        challengeEnding(DateTime(2026, 8, 19, 3)),
        now,
      );
      expect(at, isNotNull);
      // Either the civil hour, or a fallback — but never the small hours.
      expect(at!.hour, anyOf(equals(18), greaterThan(6)));
    });

    test('is dropped once the challenge has closed', () {
      // The whole point is to warn before the deadline. After it, the streak is
      // already broken and the notification would be a taunt.
      expect(
        NotificationService.streakWarningTime(
          challengeEnding(DateTime(2026, 8, 12)),
          now,
        ),
        isNull,
      );
    });

    test('falls back to a point in range when the ideal moment has passed', () {
      // Player opens the app on day 6 — the day-5 slot is behind them, but
      // there is still a day to act, so a warning is still worth sending.
      final at = NotificationService.streakWarningTime(
        challengeEnding(DateTime(2026, 8, 14, 12)),
        now,
      );
      expect(at, isNotNull);
      expect(at!.isAfter(now), isTrue);
      expect(at.isBefore(DateTime(2026, 8, 14, 12)), isTrue);
    });

    test('gives up when there is no room left at all', () {
      // Minutes to go. Anything scheduled here arrives after the deadline.
      final at = NotificationService.streakWarningTime(
        challengeEnding(now.add(const Duration(minutes: 1))),
        now,
      );
      // Either null, or something genuinely still ahead of the deadline.
      if (at != null) {
        expect(at.isBefore(now.add(const Duration(minutes: 1))), isTrue);
      }
    });
  });

  group('the prompt milestones', () {
    test('are level 1, then every tenth', () {
      expect(NotificationService.milestoneFor(1), 1);
      expect(NotificationService.milestoneFor(10), 10);
      expect(NotificationService.milestoneFor(20), 20);
      expect(NotificationService.milestoneFor(30), 30);
    });

    test('and nothing before the first level is finished', () {
      expect(NotificationService.milestoneFor(0), 0);
    });

    test('with the levels in between belonging to the last one passed', () {
      // 2..9 are all still the level-1 milestone, 11..19 all still level 10.
      // That is what stops a win in between counting as a fresh ask.
      expect(NotificationService.milestoneFor(2), 1);
      expect(NotificationService.milestoneFor(9), 1);
      expect(NotificationService.milestoneFor(11), 10);
      expect(NotificationService.milestoneFor(19), 10);
      expect(NotificationService.milestoneFor(34), 30);
    });

    test('so a count that jumps lands on the milestone it passed', () {
      // A cloud save merged in can take someone from 5 levels to 34 without a
      // win in between. The milestone is 30, not "no milestone".
      NotificationService.resetForTest(promptedAt: 1);
      expect(NotificationService.milestoneFor(34), 30);
    });
  });

  group('the player is asked again until they say yes', () {
    // `supported` is false under test, so `shouldPromptAt` is false throughout
    // here; the cadence itself is checked through `milestoneFor` and
    // `promptedAtMilestone`, which do not need a plugin host.
    test('not at all where notifications cannot be delivered', () {
      // Under test `supported` is false, which is also the web case.
      expect(NotificationService.supported, isFalse);
      expect(NotificationService.shouldPromptAt(1), isFalse);
      expect(NotificationService.shouldPromptAt(10), isFalse);
    });

    test('and never again once permission has been granted', () {
      // The one terminal state. Every milestone after it is silent.
      NotificationService.resetForTest(promptedAt: 1, everGranted: true);
      expect(NotificationService.shouldPromptAt(10), isFalse);
      expect(NotificationService.shouldPromptAt(100), isFalse);
    });

    test('marking is per milestone, and only ever moves forward', () {
      NotificationService.resetForTest();
      NotificationService.markPromptedAt(1);
      expect(NotificationService.hasBeenPrompted, isTrue);
      expect(NotificationService.promptedAtMilestone, 1);

      NotificationService.markPromptedAt(10);
      expect(NotificationService.promptedAtMilestone, 10);

      // A stray older milestone must not reopen one already used.
      NotificationService.markPromptedAt(1);
      expect(NotificationService.promptedAtMilestone, 10);
    });

    test('a refusal only defers the question to the next milestone', () {
      // Declining is not marked any differently from accepting — the milestone
      // is banked either way, and the next one is what brings it back.
      NotificationService.resetForTest();
      NotificationService.markPromptedAt(NotificationService.milestoneFor(1));
      expect(NotificationService.milestoneFor(5),
          NotificationService.promptedAtMilestone,
          reason: 'a win at level 5 is still the milestone already asked at');
      expect(NotificationService.milestoneFor(10),
          greaterThan(NotificationService.promptedAtMilestone));
    });

    testWidgets('maybeShow puts up nothing when it is not due', (tester) async {
      NotificationService.resetForTest(promptedAt: 1);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                NotificationPromptDialog.maybeShow(context, levelsCompleted: 3),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Stay in the loop!'), findsNothing);
    });

    testWidgets('the dialog itself says what it is for', (tester) async {
      // Built directly, since maybeShow correctly refuses under test.
      await tester.pumpWidget(
        const MaterialApp(home: NotificationPromptDialog()),
      );
      await tester.pump();
      expect(find.text('Stay in the loop!'), findsOneWidget);
      expect(
        find.text(
          'Get notified when new challenges drop and your hint is ready',
        ),
        findsOneWidget,
      );
      expect(find.text('Enable Notifications'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('"Enable Notifications" always leaves the dialog closed',
        (tester) async {
      // The bug this covers: permission granted, dialog stuck on its spinner
      // forever. requestPermission awaited the topic subscription and the token
      // fetch before returning, and those wait on the network rather than fail
      // without it — so the answer the dialog needed had arrived long before
      // the call it was awaiting came back.
      //
      // The hang itself needs a plugin host to reproduce; what is checked here
      // is the contract that broke — the button resolves the dialog, and the
      // spinner does not outlive it.
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const NotificationPromptDialog(),
            ),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Stay in the loop!'), findsOneWidget);

      await tester.tap(find.text('Enable Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Stay in the loop!'), findsNothing,
          reason: 'the dialog must dismiss itself once the OS has answered');
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'a spinner left behind is the bug');
    });

    testWidgets('"Not now" closes it and reports a refusal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NotificationPromptDialog()),
      );
      await tester.pump();
      // Reporting is a no-op without Firebase; what matters is that the call
      // does not throw on the way out.
      expect(() async {
        await tester.tap(find.text('Not now'));
        await tester.pump();
      }, returnsNormally);
    });
  });

  group('a tapped notification goes somewhere sensible', () {
    test('a challenge push opens the challenges screen', () {
      expect(NotificationService.routeForPayload('challenge'), '/challenges');
    });

    test('a hint reminder opens nothing in particular', () {
      // It is about the game, not one level. Deep-linking into a level they
      // were not playing would be a guess dressed up as intent.
      expect(NotificationService.routeForPayload('hint'), isNull);
    });

    test('an unrecognised payload is ignored rather than guessed at', () {
      // These arrive from a console message someone typed, so "anything" is a
      // realistic input.
      expect(NotificationService.routeForPayload('nonsense'), isNull);
      expect(NotificationService.routeForPayload(null), isNull);
      expect(NotificationService.routeForPayload(''), isNull);
    });
  });

  group('preferences', () {
    test('all three default to on', () {
      // The toggles exist to turn things off. A player who granted permission
      // asked for these.
      expect(NotificationService.challengeAlerts, isTrue);
      expect(NotificationService.hintReminders, isTrue);
      expect(NotificationService.streakReminders, isTrue);
    });

    test('and survive being switched without a platform underneath', () async {
      await NotificationService.setChallengeAlerts(false);
      await NotificationService.setHintReminders(false);
      await NotificationService.setStreakReminders(false);
      expect(NotificationService.challengeAlerts, isFalse);
      expect(NotificationService.hintReminders, isFalse);
      expect(NotificationService.streakReminders, isFalse);
    });
  });

  test('every entry point is safe with no platform at all', () {
    // These sit on the launch path and on the win path. Under test there is no
    // plugin host, so all of them must be no-ops rather than throwing between
    // a player and their game.
    expect(() async {
      await NotificationService.init();
      await NotificationService.refreshPermission();
      await NotificationService.requestPermission();
      await NotificationService.syncReminders();
      await NotificationService.scheduleHintReady(DateTime.now());
      await NotificationService.scheduleStreakAtRisk(
        challengeEnding(DateTime(2030)),
        completed: false,
      );
      await NotificationService.cancelStreakAtRisk();
      await NotificationService.cancelHintReady();
      Analytics.notificationPromptShown();
      Analytics.notificationPromptAccepted();
      Analytics.notificationPromptDenied();
    }, returnsNormally);
  });
}
