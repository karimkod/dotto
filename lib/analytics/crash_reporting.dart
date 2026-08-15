// Firebase Crashlytics: where an error nobody caught goes to be seen.
//
// Configured against the same project as Analytics — dotto-d817e, options from
// lib/firebase_options.dart, native config in android/app/google-services.json
// and ios/Runner/GoogleService-Info.plist. See docs/crashlytics-setup.md.
//
// Flutter can drop an uncaught error in three different places, and catching
// one of them is not catching the others:
//
//   * FlutterError.onError — anything thrown inside the framework: a build, a
//     layout, a gesture callback, a painting pass.
//   * PlatformDispatcher.instance.onError — errors that reach the engine with
//     no Dart handler left, which is where an unawaited Future's failure ends
//     up.
//   * runZonedGuarded — everything raised in the zone that neither of the above
//     claimed first.
//
// main() installs all three, pointing at [onFlutterError], [onPlatformError]
// and [onZoneError] here. They are installed before anything else runs, so an
// error thrown during startup is reported too — the handlers check at call time
// whether Crashlytics is up, rather than being wired only once it is.
//
// Reporting stays best-effort for the same reason Analytics does: a crash
// reporter that can itself break the launch is worse than no crash reporter.
// Every path through this file swallows its own failures and prints instead.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReporting {
  CrashReporting._();

  /// Where Crashlytics can run at all. Same rule as `Analytics.supported`, and
  /// for the same reasons: no web config, and no plugin host under
  /// `flutter test` to answer the platform channel.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Forces collection on or off regardless of build mode:
  /// `--dart-define=CRASHLYTICS=on` (or `=off`).
  ///
  /// The reason to have this is verification. A debug build normally reports
  /// nothing, so the only way to confirm the whole path works — plugin, native
  /// SDK, project id, symbol upload — would otherwise be to ship a release and
  /// wait for a real crash.
  static const _override = String.fromEnvironment('CRASHLYTICS');

  /// Whether reports are actually sent.
  ///
  /// Release only by default. In debug the errors are already on the console in
  /// full, and uploading them would fill the dashboard with the developer's own
  /// half-finished work — which is how a crash-free-users figure stops meaning
  /// anything.
  static bool get collecting => switch (_override) {
    'on' => true,
    'off' => false,
    _ => kReleaseMode,
  };

  static FirebaseCrashlytics? _crashlytics;

  /// True once the SDK has started and the handlers below have somewhere to
  /// send what they catch. Note this is not the same as [collecting]: in debug
  /// the SDK is started and fed, it simply does not upload.
  static bool get enabled => _crashlytics != null;

  /// Start Crashlytics. Must be called *after* `Firebase.initializeApp` — the
  /// app it attaches to is the one Analytics creates — and it checks rather
  /// than assumes, because that initialisation is allowed to fail.
  static Future<void> init() async {
    if (!supported || _crashlytics != null) return;
    // Firebase never started: a device without Play Services, a clock too far
    // out for TLS. Touching the instance here would throw `[core/no-app]`.
    if (Firebase.apps.isEmpty) return;
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      // Persisted natively, so this has to be set on every launch rather than
      // once — a build that flipped it off would otherwise leave it off for a
      // release installed over the top.
      await crashlytics.setCrashlyticsCollectionEnabled(collecting);
      _crashlytics = crashlytics;
    } catch (e) {
      debugPrint('Crashlytics init failed, crash reporting disabled: $e');
    }
  }

  /// Framework errors. Installed as `FlutterError.onError`.
  ///
  /// [FlutterError.presentError] is called first and unconditionally, because
  /// it is what the default handler does: the console dump in debug, the red
  /// screen in a widget. Assigning `recordFlutterFatalError` straight to
  /// `FlutterError.onError`, as the Firebase snippet does, silently drops all
  /// of that — including in debug, where it is the only copy anyone sees.
  static void onFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _crashlytics?.recordFlutterFatalError(details);
  }

  /// Errors that reach the engine unhandled. Installed as
  /// `PlatformDispatcher.instance.onError`.
  ///
  /// Returning true claims the error, which stops the engine printing it — so
  /// [recordError] prints it here instead. Returning false would hand it back
  /// and let it take the app down.
  static bool onPlatformError(Object error, StackTrace stack) {
    recordError(error, stack, context: 'platform');
    return true;
  }

  /// Errors raised in the zone `runZonedGuarded` wraps around `runApp`.
  static void onZoneError(Object error, StackTrace stack) =>
      recordError(error, stack, context: 'zone');

  /// The one place an error reaches the SDK.
  ///
  /// [fatal] is true by default: everything routed here arrived uncaught, which
  /// is what makes the crash-free-users figure mean what it says. Pass false
  /// for something the app caught and recovered from.
  static void recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = true,
    String? context,
  }) {
    // Printed whether or not it is uploaded. The handlers above have taken the
    // error out of the engine's hands, so if this does not print it, nothing
    // does — and an error that vanishes in debug is a worse trade than a noisy
    // console.
    debugPrint('uncaught${context == null ? '' : ' ($context)'}: $error\n$stack');
    final crashlytics = _crashlytics;
    if (crashlytics == null) return;
    unawaited(
      crashlytics
          .recordError(error, stack, fatal: fatal, reason: context)
          .catchError((Object e) {
            debugPrint('crashlytics: recording failed: $e');
          }),
    );
  }

  /// Tests only: undoes [init] so a test can assert the unstarted behaviour.
  @visibleForTesting
  static void resetForTest() => _crashlytics = null;
}
