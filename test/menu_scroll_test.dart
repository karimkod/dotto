// The menu opens on the level you should play next, wherever that level sits
// on the path. Three things have broken this:
//
//  * the path is not a uniform stack — a world banner sits under the first
//    level of each world — so a position derived by counting levels drifts by
//    every banner above the target;
//  * the top of the path has nothing past it to scroll into, so centring the
//    final level needs empty space above it;
//  * the bottom is the opposite case, and was mistakenly given the same
//    treatment: space below the path let a fresh player's level 1 settle in
//    the middle of the screen with nothing under it. The start of the climb
//    belongs at the bottom, so that end gets no padding.
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
  testWidgets('a fresh player opens with level 1 near the bottom',
      (tester) async {
    // The start of a climb belongs at the bottom of it, not floating in the
    // middle of the screen with dead space underneath. Level 1 is the last
    // level in the column and only the World 1 banner sits below it, so the
    // scroll runs out with both near the bottom edge — deliberately NOT
    // centred, which is what the padding under the path used to force.
    await pumpMenu(tester);

    final centre = cardCentre(tester, 1);
    expect(centre, isNotNull);

    final box =
        tester.renderObject<RenderBox>(find.byType(SingleChildScrollView));
    final top = box.localToGlobal(Offset.zero).dy;
    final fraction = (centre! - top) / box.size.height;

    expect(fraction, greaterThan(0.5),
        reason: 'level 1 must sit below the middle, not on it');
    // The banner is the only thing under it, so it cannot be flush either.
    expect(fraction, lessThan(0.95),
        reason: 'the World 1 banner still needs room beneath level 1');
  });

  testWidgets('nothing is stranded below the start of the path',
      (tester) async {
    // The gap this fixes: padding under the last item let the scroll stop with
    // empty space below the banner. At the end of the scroll the banner should
    // be the bottom of the content.
    await pumpMenu(tester);

    final position = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!
        .position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 1),
        reason: 'a fresh open sits at the very bottom of the path');
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
