# Firebase setup

Analytics is configured against project **dotto-d817e**. The config was written
by hand rather than generated — `flutterfire configure` needs a machine logged
into the Firebase account, which the development environment here is not.

## The three files

| File | Role |
|---|---|
| `lib/firebase_options.dart` | What actually initialises Firebase |
| `android/app/google-services.json` | Android native config |
| `ios/Runner/GoogleService-Info.plist` | iOS native config |

They all carry the same ids and **must change together**. A mismatch between the
Dart options and the native config does not raise an error — it shows up as
analytics being silent, which is a much harder thing to notice.

| | value |
|---|---|
| Project id | `dotto-d817e` |
| Project number | `593272219819` |
| Bundle / package | `com.karimkod.dotto` |
| Android app id | `1:593272219819:android:c37f7e29ba239433adafee` |
| iOS app id | `1:593272219819:ios:cdef52c41ffe61d9adafee` |

The package must stay equal to `applicationId` in
`android/app/build.gradle.kts`, which is also what the signing config, the Play
listing and the AdMob app ids are tied to.

## How initialisation actually happens

`analytics_service.dart` calls:

```dart
Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
```

Passing options explicitly means Firebase starts from the Dart values, so it
does **not** depend on the Google Services Gradle plugin having processed
`google-services.json`. That plugin is not installed, and consequently
`google-services.json` is currently inert on Android — it is kept because it is
the canonical record of the project, because `flutterfire configure` would
regenerate it, and because dropping the explicit options later would make it
load-bearing immediately.

If you do add the plugin (needed for Crashlytics, Messaging, and anything else
that reads the native config directly):

1. `android/settings.gradle.kts`, in the `plugins` block:
   `id("com.google.gms.google-services") version "4.4.2" apply false`
2. `android/app/build.gradle.kts`, in its `plugins` block:
   `id("com.google.gms.google-services")`

On iOS, `GoogleService-Info.plist` must also be a member of the Runner target in
Xcode. Being present on disk is not enough — the file has to be in "Copy Bundle
Resources", or the native SDK will not find it at runtime.

## Not secret

A Firebase API key identifies a project; it does not authorise anything by
itself, which is why these files are normally committed. What protects a project
is its security rules and App Check, not the secrecy of the key. Analytics also
has no rules to configure — it only writes.

## Web

Deliberately absent. `Analytics.supported` returns false on web, no web app is
registered, and `DefaultFirebaseOptions.currentPlatform` throws there rather
than pretending to have a configuration.

## Checking it works

`Analytics.enabled` is true once initialisation succeeds — it is false in tests
and on web by design. Events take a few hours to reach the console; DebugView is
immediate:

```sh
# Android
adb shell setprop debug.firebase.analytics.app com.karimkod.dotto
```

## What is reported

`lib/analytics/analytics_service.dart` is the complete list, with each event's
parameters. Two entries (`level_skip`, `interstitial_clicked`) are defined but
never called — the features do not exist yet.
