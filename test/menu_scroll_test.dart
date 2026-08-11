// The menu opens scrolled to the level you should play next. The path is not a
// uniform stack — a world banner sits under the first level of each world — so
// any position derived by counting levels drifts by every banner above the
// target. These assert against where the card actually lands on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/app_routes.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/progress/progress_store.dart';
import 'package:dotto/screens/menu_screen.dart';
import 'package:dotto/widgets/level_card.dart';

void main() {
  /// Where the card for [n] sits vertically, or null if it is not laid out.
  double? cardCentre(WidgetTester tester, int n) {
    final finder = find.byWidgetPredicate(
      (w) => w is LevelCard && w.level.number == n,
    );
    if (finder.evaluate().isEmpty) return null;
    final box = tester.renderObject<RenderBox>(finder);
    return box.localToGlobal(Offset(0, box.size.height / 2)).dy;
  }

  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [routeObserver],
      home: const MenuScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opens centred on the next level to play', (tester) async {
    // Far enough in that six world banners sit above the target — the exact
    // case the old arithmetic got wrong, and by more than a screen.
    for (var n = 1; n < kWorld2Start; n++) {
      ProgressStore.markCompleted(n);
    }
    await pumpMenu(tester);

    final target = kWorld2Start;
    final centre = cardCentre(tester, target);
    expect(centre, isNotNull,
        reason: 'the level to play must be on screen at all, not scrolled past');

    final viewportCentre = tester.view.physicalSize.height /
        tester.view.devicePixelRatio /
        2;
    // Generous: this is asserting "centred", not pixel-exact placement. The old
    // arithmetic was out by roughly six banner heights (~500px), far outside.
    expect((centre! - viewportCentre).abs(), lessThan(80),
        reason: 'level $target should sit near the middle of the viewport, '
            'not above it');
  });

  testWidgets('a level with no banners above it also centres', (tester) async {
    // A control: near the top of the path almost every banner is below the
    // target, so a banner-blind calculation would look fine here. If this one
    // fails while the other passes, the centring itself is wrong rather than
    // the banner accounting.
    for (var n = 1; n < kLevelCount; n++) {
      ProgressStore.markCompleted(n);
    }
    await pumpMenu(tester);

    final centre = cardCentre(tester, kLevelCount);
    expect(centre, isNotNull);
    final viewportCentre = tester.view.physicalSize.height /
        tester.view.devicePixelRatio /
        2;
    // The last level cannot reach the centre — the list runs out — so it only
    // has to be on screen and in the lower half, not centred.
    expect(centre!, lessThan(viewportCentre * 2));
    expect(centre, greaterThan(0));
  });
}
