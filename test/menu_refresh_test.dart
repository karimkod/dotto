// The menu has to re-read progress when the player comes back to it — and the
// route future is the wrong signal for that, because winning a level advances
// with pushReplacement, which completes the replaced route's future while the
// player is still deep in the game.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/app_routes.dart';
import 'package:dotto/progress/progress_store.dart';
import 'package:dotto/screens/menu_screen.dart';
import 'package:dotto/widgets/play_button.dart';

void main() {
  /// The level the big play button offers — the menu's view of where the
  /// player is up to.
  Finder offeredLevel(int n) => find.descendant(
        of: find.byType(PlayButton),
        matching: find.text('Level $n'),
      );

  testWidgets('progress won across a level chain shows on the way back',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routeObserver],
      home: const MenuScreen(),
    ));
    expect(offeredLevel(1), findsOneWidget,
        reason: 'a fresh player is offered level 1');

    final nav = tester.state<NavigatorState>(find.byType(Navigator));

    // Open level 1, win it, and take the Next Level route — pushReplacement,
    // exactly as the game screen does.
    nav.push(MaterialPageRoute(builder: (_) => const _FakeGame(1)));
    await tester.pumpAndSettle();
    ProgressStore.markCompleted(1);
    nav.pushReplacement(MaterialPageRoute(builder: (_) => const _FakeGame(2)));
    await tester.pumpAndSettle();

    // Win the second one too, then walk back to the menu.
    ProgressStore.markCompleted(2);
    nav.pop();
    await tester.pumpAndSettle();

    expect(offeredLevel(3), findsOneWidget,
        reason: 'the menu must reflect every level won during the visit, not '
            'just those finished before the first pushReplacement');
  });
}

class _FakeGame extends StatelessWidget {
  const _FakeGame(this.n);

  final int n;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('game $n')));
}
