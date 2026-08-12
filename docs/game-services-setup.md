# Game Center / Play Games setup

The code is in `lib/services/game_services.dart`. **iOS is ready; Android is
switched off in code** until the Play Console work is done.

## Achievements

Ten, all unlocked automatically on the win path.

| Achievement | Unlocks when | iOS id |
|---|---|---|
| World 1–7 Complete | every level of that world is finished | `com.karimkod.dotto.world1` … `world7` |
| Dotto Master | all 110 levels finished | `com.karimkod.dotto.master` |
| Hint Seeker | 10 hints taken, lifetime | `com.karimkod.dotto.hint_seeker` |
| Speed Runner | 5 levels finished in one session | `com.karimkod.dotto.speed_runner` |

"No Help Needed" was dropped, as requested — tracking hint-free worlds
retroactively needs per-world hint history that is not recorded.

Note the count: seven worlds plus three others is **ten**, not the nine in the
brief's tally. The list is what got built.

Lifetime hints come from `ProgressStore.hintsUsed()`, so Hint Seeker survives
restarts. Speed Runner is a session counter and deliberately does not.

## iOS

Create each achievement in App Store Connect with the id above, exactly. Ids are
fixed once players have earned them.

The Game Center capability is declared in `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.game-center</key>
<true/>
```

and `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` is set on all three
Runner build configurations. Both halves are needed — an entitlements file that
no build configuration points at is inert.

**This changes what signing requires.** An entitlement must be backed by the App
ID in the Apple Developer portal: `com.karimkod.dotto` needs Game Center enabled
there, and the App Store provisioning profile regenerated to include it. If it
is not, `flutter build ipa` fails at the export step — *after* a successful
archive, which is a confusing place to land. The CI workflow fetches the profile
through the App Store Connect API on every run, so once the portal is right, the
next run picks it up with no further change here.

## Android — configured

All three pieces are in place:

1. **Achievement ids** — all ten in `game_services.dart`, paired with their iOS
   counterparts. They differ only in their last character or two, so a test
   checks they are all distinct; a transposition would unlock the wrong badge
   rather than fail.
2. **The application id**, `593272219819`, in
   `android/app/src/main/res/values/games-ids.xml` as `@string/app_id`. It must
   stay a string resource: the value is all digits, and a raw numeric
   `android:value` is parsed as an integer, overflows, and leaves the SDK with
   the wrong id at runtime. (It is the same number as the Firebase project
   number — both are the underlying Google Cloud project — but they are separate
   settings.)
3. **The manifest entry** pointing at it:

   ```xml
   <meta-data android:name="com.google.android.gms.games.APP_ID"
              android:value="@string/app_id"/>
   ```

`_androidReady` is now `true`, so Android signs in. A test asserts that when
that flag is on, the manifest entry and the string resource both exist — the
gate and the native config have to move together, because signing in without
the id fails natively at launch where no Dart `try`/`catch` can help.

If Android sign-in ever needs killing quickly, `_androidReady = false` is the
switch and costs nothing but the achievements.

A second guard sits behind it: `Achievement.id` in the plugin returns
`androidID` on Android, so an empty id would be *sent* rather than skipped;
`_unlock` refuses to send an empty one.

### Still to verify on a device

None of this has run on hardware. Test on a real device signed into Play
Games — an emulator without Play Services will not do — and check that sign-in
succeeds and one achievement actually registers.

## Behaviour when signed out

Everything degrades to nothing. Sign-in is silent and never shows an error;
unlocks are dropped; the Achievements row in Settings shows a message rather
than opening an empty screen. A player who ignores Game Center should not be
able to tell the feature exists.
