// The splash sits in front of the whole game, so the thing that matters is
// that it always gets out of the way. An animation that fails to finish, or a
// route that never replaces itself, would leave the player looking at a dot
// forever with nothing to tap.

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
