// The dot on the calendar, which is the only thing telling a player a
// challenge is waiting.
//
// It is a dot rather than a count, so the only two states it has are right and
// wrong, and both failures are silent: a dot that never appears means the
// weekly challenge goes unplayed, and one that never clears means the menu
// nags about something already beaten. Neither shows up as an error anywhere,
// which is why the condition behind it is pinned here rather than left to be
// noticed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/app_routes.dart';
import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/screens/menu_screen.dart';
import 'package:dotto/services/challenge_service.dart';
import 'package:dotto/theme/app_theme.dart';

void main() {
  /// The badge, looked for only inside the calendar's own Stack — the menu has
  /// coral elsewhere, and a finder that matched any of it would pass whatever
  /// the calendar was doing.
  Finder badge() => find.descendant(
        of: find
            .ancestor(
              of: find.byIcon(Icons.calendar_today_rounded),
              matching: find.byType(Stack),
            )
            .first,
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == AppColors.coral &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle),
      );

  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routeObserver],
      home: const MenuScreen(),
    ));
    await tester.pumpAndSettle();
  }

  tearDown(ChallengeService.resetForTest);

  testWidgets('a live challenge nobody has beaten puts a dot on the calendar',
      (tester) async {
    ChallengeService.resetForTest(challenges: [_running()]);
    await pumpMenu(tester);
    expect(badge(), findsOneWidget);
  });

  testWidgets('beating it takes the dot away', (tester) async {
    ChallengeService.resetForTest(
      challenges: [_running()],
      completed: {'week_live'},
    );
    await pumpMenu(tester);
    expect(badge(), findsNothing,
        reason: 'the menu would be nagging about a challenge already won');
  });

  testWidgets('no dot before the window opens or after it closes',
      (tester) async {
    final now = DateTime.now();
    ChallengeService.resetForTest(challenges: [
      _challenge('week_over', now.subtract(const Duration(days: 14)),
          now.subtract(const Duration(days: 7))),
      _challenge('week_soon', now.add(const Duration(days: 7)),
          now.add(const Duration(days: 14))),
    ]);
    await pumpMenu(tester);
    expect(badge(), findsNothing,
        reason: 'neither challenge is the one to beat right now');
  });

  testWidgets('an unbeaten one still showing does not mask a beaten live one',
      (tester) async {
    // The archive keeps past challenges around, and they are unbeaten more
    // often than not — the dot has to answer for the live one only.
    final now = DateTime.now();
    ChallengeService.resetForTest(
      challenges: [
        _challenge('week_over', now.subtract(const Duration(days: 14)),
            now.subtract(const Duration(days: 7))),
        _running(),
      ],
      completed: {'week_live'},
    );
    await pumpMenu(tester);
    expect(badge(), findsNothing);
  });
}

/// A challenge whose window is open right now.
Challenge _running() => _challenge(
      'week_live',
      DateTime.now().subtract(const Duration(days: 1)),
      DateTime.now().add(const Duration(days: 6)),
    );

Challenge _challenge(String id, DateTime start, DateTime end) => Challenge(
      id: id,
      title: 'Test',
      description: '',
      startDate: start,
      endDate: end,
      reward: ChallengeReward.hint,
      level: const LevelData(
        id: -1,
        size: 3,
        title: 'Challenge',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(0, 2),
        toolkit: [],
      ),
    );
