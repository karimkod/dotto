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

Nothing else to configure: Game Center needs no manifest entry, and the
capability is enabled per-app in App Store Connect.

## Android — one thing left

**Achievement ids: done.** All ten Play Console ids are in
`game_services.dart`, paired with their iOS counterparts. They differ only in
their last character or two, so a test checks they are all distinct — a
transposition would unlock the wrong badge rather than fail.

Still missing, and the reason Android is switched off:

1. **The application id in the manifest.** Play Games needs:

   ```xml
   <meta-data android:name="com.google.android.gms.games.APP_ID"
              android:value="@string/games_app_id"/>
   ```

   with `games_app_id` in `android/app/src/main/res/values/strings.xml`. The
   value is the numeric project id from Play Console — as a **string resource**,
   not a raw number: a bare numeric value gets parsed as an integer and the SDK
   fails at runtime.

Until then `_androidReady` is `false`, so Android never signs in. That gate is
the point: starting the Play Games SDK with no application id can bring the app
down at launch, and it is a native failure — the `try`/`catch` around `signIn`
would not contain it.

There is a second guard behind it. `Achievement.id` in the plugin returns
`androidID` on Android, so an empty id would be *sent* rather than skipped;
`_unlock` refuses to send an empty one.

### Switching Android on

Two steps now that the ids are in: add the manifest entry and string resource,
then set `_androidReady = true`. Test on a device signed into Play Games — an
emulator without Play Services will not do.

## Behaviour when signed out

Everything degrades to nothing. Sign-in is silent and never shows an error;
unlocks are dropped; the Achievements row in Settings shows a message rather
than opening an empty screen. A player who ignores Game Center should not be
able to tell the feature exists.
