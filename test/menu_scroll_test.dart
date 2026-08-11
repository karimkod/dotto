// The menu opens centred on the level you should play next, wherever that
// level sits on the path. Two things have broken this:
//
//  * the path is not a uniform stack — a world banner sits under the first
//    level of each world — so a position derived by counting levels drifts by
//    every banner above the target;
//  * the levels at either end have nothing past them to scroll into, so
//    centring them needs empty space beyond the ends of the path.
//
// The cases below are the bottom, the middle and the top of the path, which is
// one for each of those failures plus the ordinary case.
//
// Note the reference is the scroll viewport's centre, not the screen's: the
// path sits between the top bar and the play button, so the two are ~25px
// apart and measuring against the screen quietly loosens every assertion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/app_routes.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/progress/progress_store.dart';
import 'package:dotto/screens/menu_screen.dart';
import 'package:dotto/widgets/level_card.dart';

void main() {
  double viewportCentre(WidgetTester tester) {
    final box =
        tester.renderObject<RenderBox>(find.byType(SingleChildScrollView));
    return box.localToGlobal(Offset(0, box.size.height / 2)).dy;
  }

  /// Where the card for level [n] sits vertically, or null if it is not laid
  /// out at all (scrolled far enough off that it was never built).
  double? cardCentre(WidgetTester tester, int n) {
    final finder =
        find.byWidgetPredicate((w) => w is LevelCard && w.level.number == n);
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

  void expectCentred(WidgetTester tester, int n) {
    final centre = cardCentre(tester, n);
    expect(centre, isNotNull,
        reason: 'level $n is not on screen at all, let alone centred');
    expect((centre! - viewportCentre(tester)).abs(), lessThan(1.0),
        reason: 'level $n should sit in the middle of the path viewport');
  }

  // Ordered: ProgressStore is process-global, so each test builds on the last.
  testWidgets('a fresh player opens centred on level 1', (tester) async {
    // The bottom of the path. Nothing follows level 1 but its world banner, so
    // this is the case that needs space past the end to be centred at all.
    await pumpMenu(tester);
    expectCentred(tester, 1);
  });

  testWidgets('centres mid-path, past several world banners', (tester) async {
    // Six banners sit above the World 2 opener — the case a banner-blind
    // calculation misses by roughly 500px.
    for (var n = 1; n < kWorld2Start; n++) {
      ProgressStore.markCompleted(n);
    }
    await pumpMenu(tester);
    expectCentred(tester, kWorld2Start);
  });

  testWidgets('centres on the last level', (tester) async {
    // The top of the path — the same end-of-list problem as level 1, mirrored.
    for (var n = 1; n < kLevelCount; n++) {
      ProgressStore.markCompleted(n);
    }
    await pumpMenu(tester);
    expectCentred(tester, kLevelCount);
  });
}
