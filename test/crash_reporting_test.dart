// Crash reporting sits on the launch path and on every error path in the app,
// which makes it the last thing that may throw on its own account. main()
// installs its three handlers before anything else runs — including before
// Firebase exists — so what is pinned here is that the whole surface is inert
// and silent when the SDK never started, which is the state every test, every
// web build and every device without Play Services is in.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/analytics/crash_reporting.dart';

void main() {
  setUp(CrashReporting.resetForTest);

  test('crash reporting stands down where there is no Firebase to talk to', () {
    // kIsWeb is checked before dart:io, so the web build never calls Platform.
    expect(CrashReporting.supported, isFalse);
    expect(CrashReporting.enabled, isFalse);
  });

  test('nothing is uploaded from a debug build', () {
    // The default, and the reason a developer's own broken build does not move
    // the crash-free-users figure. --dart-define=CRASHLYTICS=on overrides it.
    expect(kReleaseMode, isFalse, reason: 'tests run in debug');
    expect(CrashReporting.collecting, isFalse);
  });

  test('init is a no-op rather than a crash when Firebase never started', () async {
    // main() awaits this between Firebase and the rest of startup; anything it
    // throws kills the launch of an app that is otherwise fine.
    await expectLater(CrashReporting.init(), completes);
    expect(CrashReporting.enabled, isFalse);
  });

  test('the framework handler still presents the error with no SDK behind it', () {
    // FlutterError.onError points here from the first line of main(), long
    // before Crashlytics could exist. Presenting is the default handler's job
    // and it has to survive being taken over — otherwise a startup error would
    // be swallowed instead of printed.
    final details = FlutterErrorDetails(
      exception: StateError('boom'),
      stack: StackTrace.current,
      library: 'crash_reporting_test',
    );
    expect(() => CrashReporting.onFlutterError(details), returnsNormally);
  });

  test('the engine handler claims the error even when it cannot report it', () {
    // False would hand the error back to the engine and take the app down. The
    // error is printed either way, so claiming it loses nothing.
    expect(
      CrashReporting.onPlatformError(StateError('boom'), StackTrace.current),
      isTrue,
    );
  });

  test('the zone handler and a direct record are safe with nothing started', () {
    expect(() {
      CrashReporting.onZoneError(StateError('boom'), StackTrace.current);
      CrashReporting.recordError(StateError('boom'), StackTrace.current);
      CrashReporting.recordError('a bare string', null, fatal: false);
    }, returnsNormally);
  });
}
