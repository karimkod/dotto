# Firebase setup — required before analytics reports anything

The code is wired up. The **configuration is not**, and cannot be generated
from this repo — `flutterfire configure` has to run on a machine logged into
the Firebase account. Until it does, `Firebase.initializeApp()` throws,
`Analytics.enabled` stays false, and every event call returns silently.

Nothing is broken in that state. The game runs normally and reports nothing.

## What is missing

Three generated files, none of which are in the repo:

| File | Purpose |
|---|---|
| `lib/firebase_options.dart` | Dart-side config (currently unused — see below) |
| `android/app/google-services.json` | Android native config |
| `ios/Runner/GoogleService-Info.plist` | iOS native config |

## Generating them

```sh
dart pub global activate flutterfire_cli
flutterfire configure --project=dotto-d817e
```

Select **Android** and **iOS** when prompted. Web is deliberately excluded:
`Analytics.supported` returns false on web, so a web config would go unused.

### The bundle ID must match

`flutterfire configure` asks for the application id, and it has to be the one
this app actually ships with:

```
com.karimkod.dotto
```

That is the `applicationId` in `android/app/build.gradle.kts` and the iOS bundle
id, and it is also what the AdMob app ids and the signing setup are tied to.

**A `com.reshaped.dotto` package was mentioned when this work was requested —
that is not this app's id.** A `google-services.json` generated for it would be
rejected at build time by the Google Services Gradle plugin, which checks the
package name in the JSON against the module's applicationId. If Firebase was
already registered under that name, the Android app needs re-registering under
`com.karimkod.dotto` in the Firebase console before configure will produce a
usable file.

## After generating

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
are enough on their own — `Firebase.initializeApp()` reads the native config
with no `options:` argument, which is how `analytics_service.dart` calls it.

Two build-side steps Firebase needs on Android, which `flutterfire configure`
does **not** add for you:

1. In `android/settings.gradle.kts`, add the Google Services plugin to the
   `plugins` block:
   `id("com.google.gms.google-services") version "4.4.2" apply false`
2. In `android/app/build.gradle.kts`, apply it:
   `id("com.google.gms.google-services")`

Without these the JSON is ignored and Firebase fails to initialise at runtime —
with no build error, which makes it an easy one to lose an afternoon to.

If you would rather pass options explicitly, import the generated
`firebase_options.dart` and change the call in `analytics_service.dart` to
`Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.

## Checking it worked

`Analytics.enabled` is true once initialisation succeeds. Events take a few
hours to appear in the Firebase console; for immediate feedback use DebugView:

```sh
# Android
adb shell setprop debug.firebase.analytics.app com.karimkod.dotto
```

## What is reported

See `lib/analytics/analytics_service.dart` — it is the whole list, with each
event's parameters. Two of them (`level_skip`, `interstitial_clicked`) are
defined but never called: the features do not exist yet.
