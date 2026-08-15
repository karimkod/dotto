# Crashlytics setup

Crash reporting for `com.karimkod.dotto`, on the same Firebase project as
Analytics (**dotto-d817e**). No new project, no new config file — Crashlytics
reads the `google-services.json` and `GoogleService-Info.plist` that are already
in place. See [firebase-setup.md](firebase-setup.md) for those.

## What was added

| Where | What |
|---|---|
| `pubspec.yaml` | `firebase_crashlytics` |
| `android/build.gradle.kts` | `com.google.firebase.crashlytics` declared, `apply false` |
| `android/app/build.gradle.kts` | the same plugin applied, after Google Services |
| `lib/analytics/crash_reporting.dart` | the service: start, collection switch, the three handlers |
| `lib/main.dart` | handlers installed first, `CrashReporting.init()` after Firebase |
| `.github/workflows/ios-release.yml` | dSYM upload after the TestFlight delivery |

Nothing was needed in either `Info.plist` or `AndroidManifest.xml`.

## The three routes an error can take

Flutter does not have one uncaught-error path, it has three, and installing a
handler on one of them catches nothing from the other two.

| Route | Catches |
|---|---|
| `FlutterError.onError` | thrown inside the framework — build, layout, gesture, paint |
| `PlatformDispatcher.instance.onError` | reached the engine with no Dart handler left, e.g. an unawaited Future that failed |
| `runZonedGuarded` | anything else raised in the zone around `runApp` |

`main()` installs all three on the **first lines of the function**, before
`WidgetsFlutterBinding.ensureInitialized()` and long before Firebase exists. The
handlers check at call time whether Crashlytics has started, so an error thrown
during startup is still printed, and is reported too if it happens after
`CrashReporting.init()`. Wiring them up only once Crashlytics was ready would
leave the riskiest part of the launch uncovered.

`runZonedGuarded` wraps the binding as well as `runApp`, for the same reason —
and because a binding created outside the zone that guards it is a mismatch
Flutter warns about.

### One deliberate difference from the Firebase snippet

The documented snippet is:

```dart
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
```

That assignment replaces the default handler, whose job is
`FlutterError.presentError` — the console dump in debug, the red error widget in
a build. `recordFlutterFatalError` does not call it, so taking the snippet
literally means framework errors stop appearing on the console, including in
debug where that is the only copy anyone sees.

`CrashReporting.onFlutterError` presents first, then records. Same reporting,
without going quiet locally.

## Debug vs release

Collection is **off in debug, on in release**. Otherwise the dashboard fills
with a developer's own half-finished work and crash-free-users stops meaning
anything.

It is a runtime switch (`setCrashlyticsCollectionEnabled`), not a compile-time
one, so the SDK is started and fed in debug — it simply does not upload. That
keeps the code path being exercised identical in both modes.

The setting is persisted natively, which is why it is set on **every** launch
rather than once: a debug build that turned it off would otherwise leave it off
for a release installed over the top.

To verify the whole path end to end without shipping a release:

```sh
flutter run --dart-define=CRASHLYTICS=on
```

`=off` forces the other way. With neither, `kReleaseMode` decides.

## Symbols

Reports have to arrive readable, and that is a build-time job on both platforms.

**Android** — the Gradle plugin uploads the R8 mapping file and stamps each
build with an id. That is the whole reason it is applied; without it crashes
still arrive, just as unactionable obfuscated frames.

**iOS** — Crashlytics symbolicates from dSYMs and can only get them from an
upload. `DEBUG_INFORMATION_FORMAT` is already `dwarf-with-dsym` on the Release
and Profile configs, so the archive contains them; the release workflow runs
`upload-symbols` over `build/ios/archive` after the TestFlight delivery.

`uploadSymbols` in the export options is a different thing — that sends dSYMs to
**Apple**, and App Store Connect does not forward them to Firebase.

That step is `continue-on-error: true` on purpose. The build is already
delivered by the time it runs, so a Firebase outage costs readable native frames
for one release rather than turning a shipped build into a failed workflow.

Both of these only affect *native* frames. Dart errors — which is everything the
three handlers above catch — arrive readable already, because the release builds
do not pass `--obfuscate`. If that ever changes, `--split-debug-info` symbols
will need uploading too and the Dart stack traces will go opaque until they are.

## Checking it works

`CrashReporting.enabled` is true once the SDK has started; `collecting` says
whether anything is actually being sent. Both are false in tests and on web by
design, which is what `test/crash_reporting_test.dart` pins.

A forced crash is the only real end-to-end check:

```dart
FirebaseCrashlytics.instance.crash();
```

Reports appear in the console within a couple of minutes, but only after the
**next** launch — the native SDK writes the report during the crash and uploads
it on restart, so an app that is crashed and left closed reports nothing.
