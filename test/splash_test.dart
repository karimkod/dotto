// The splash sits in front of the whole game, so the thing that matters is
// that it always gets out of the way. An animation that fails to finish, or a
// route that never replaces itself, would leave the player looking at a dot
// forever with nothing to tap.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/screens/splash_screen.dart';
import 'package:dotto/theme/app_theme.dart';

void main() {
  testWidgets('it shows the mark, then hands over', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(
        next: (_) => const Scaffold(body: Center(child: Text('after'))),
      ),
    ));
    await tester.pump();

    expect(find.text('DOTTO'), findsOneWidget);
    expect(find.text('after'), findsNothing);

    // The opening runs 1800ms, then a 450ms cross-fade.
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(find.text('after'), findsOneWidget);
    expect(find.text('DOTTO'), findsNothing,
        reason: 'the splash replaces itself rather than stacking');
  });

  testWidgets('the handoff waits for the work it covers', (tester) async {
    // Boot runs behind the opening, and the next screen reads its stores
    // synchronously — so an animation that finishes first must hold rather
    // than hand over to a screen whose data is not there yet.
    final boot = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(
        holdFor: boot.future,
        next: (_) => const Scaffold(body: Center(child: Text('after'))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('after'), findsNothing,
        reason: 'boot has not settled, so there is nothing safe to build yet');
    expect(find.text('DOTTO'), findsOneWidget,
        reason: 'the opening keeps the screen rather than going blank');

    boot.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('after'), findsOneWidget);
  });

  testWidgets('a failed boot still hands over', (tester) async {
    // The splash's one job is to get out of the way. Boot reports its own
    // errors; the opening must not turn one into a screen nobody can leave.
    final boot = Completer<void>();
    // Swallowed here as well as in the splash: whether the error lands before
    // or after the handoff starts listening depends on frame timing, and an
    // error the splash has not subscribed to yet would fail the test as
    // unhandled instead of exercising the catch.
    unawaited(boot.future.catchError((_) {}));
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(
        holdFor: boot.future,
        next: (_) => const Scaffold(body: Center(child: Text('after'))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1800));

    boot.completeError(StateError('boot died'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('after'), findsOneWidget);
  });

  testWidgets('there is no way back to it', (tester) async {
    // pushReplacement, not push: a player who hits back from the menu should
    // leave the app, not return to a splash that would fire again.
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(
        next: (_) => const Scaffold(body: Center(child: Text('after'))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    final popped = await tester.binding.handlePopRoute();
    expect(popped, isFalse,
        reason: 'nothing is left underneath to pop back to');
  });

  testWidgets('it paints the game background from the first frame',
      (tester) async {
    // A splash in a different colour from the launch theme flashes on the way
    // in; one in a different colour from the menu flashes on the way out.
    await tester.pumpWidget(MaterialApp(
      home: SplashScreen(next: (_) => const SizedBox.shrink()),
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AppColors.background);

    // Let it finish rather than leaving a controller running.
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();
  });

  group('the native launch colour matches the app background', () {
    // Declared in three places that cannot import each other — Dart, the
    // Android resources and the iOS storyboard — so these are the only thing
    // keeping them in step. A mismatch is a flash at launch: easy to ship, and
    // hard to notice on a fast device.
    const cream = 0xFFFAF8F5;

    test('Dart', () {
      expect(AppColors.background.toARGB32(), cream);
    });

    test('Android', () {
      final colors =
          File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colors, contains('name="launch_background">#FAF8F5'));

      // Both the pre-Flutter drawable and the window behind Flutter, in light
      // and dark — Dotto is light-only, so following the OS here would flash
      // black into a cream game.
      for (final f in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        expect(File(f).readAsStringSync(), contains('@color/launch_background'),
            reason: '$f still paints something else');
      }
      for (final f in [
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-night/styles.xml',
      ]) {
        expect(File(f).readAsStringSync(),
            isNot(contains('?android:colorBackground')),
            reason: '$f follows the system theme, so dark mode flashes black');
      }
    });

    test('iOS', () {
      final storyboard =
          File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
              .readAsStringSync();
      expect(storyboard, isNot(contains('red="1" green="1" blue="1"')),
          reason: 'the storyboard is still white');
      expect(storyboard, contains('0.98039215686274506'),
          reason: 'the storyboard should carry cream as sRGB components');
    });
  });
}
