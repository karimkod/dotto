# Cloud save

Progress syncs through the platform's own saved-games storage: **Play Games
Saved Games** on Android, **Game Center saved games** on iOS, both via
`games_services`. Code is in `lib/services/cloud_save_service.dart`.

Invisible by design. No UI, no toast, no spinner, no error the player can see. A
player who never signs in gets the game exactly as before.

## One console step is required

**Saved Games must be enabled in the Play Console** — Play Games Services →
Configuration → Saved Games. It is off by default, and until it is on,
`saveGame` fails at runtime with no build-time warning. That is the whole
Android setup: the plugin uses `PlayGames.getSnapshotsClient`, which under Play
Games v2 needs no Drive scope and no extra permission.

The request that produced this feature asked to "enable saved games scope" in
`signIn`. There is no such parameter in `games_services` 5.0.0 — `signIn()`
takes no arguments — and v2 does not use the old scope model. The console toggle
is the real equivalent.

On iOS, Game Center saved games need no extra configuration beyond the Game
Center capability already in `Runner.entitlements`.

## Format

Slot name `dotto_progress`; Play Games allows 1–100 characters of `a-zA-Z0-9-._~`
and the name is permanent once written.

```json
{ "completedLevels": [1, 2, 3], "hintsUsedTotal": 5, "version": 1 }
```

Levels are written sorted so two devices at the same progress produce identical
bytes. `version` exists for migrations; a save with a **higher** version is
ignored rather than parsed, so an old build cannot misread a newer save and
overwrite it.

## The merge only ever adds

On load: **union** the level sets, **max** the hint count, then write the result
back so both sides agree.

Nothing is ever removed. No combination of stale cloud data, offline play or two
devices can take away a level someone finished. The cost is deliberate and worth
knowing: **progress cannot be undone across devices** — Settings → Reset progress
clears the device, but the next cloud load restores it. A player who loses
finished levels is owed an apology; one who keeps a few extra is not.

Resetting for real means resetting on the device and then deleting the cloud
save from the platform's own UI.

## When it runs

| Trigger | Why |
|---|---|
| after sign-in | the earliest point an account exists to read from |
| after a level is won | the thing most worth not losing |
| after a hint is used | keeps the lifetime count honest across devices |
| on `AppLifecycleState.paused` | last certain moment before a background kill |

Saves coalesce: a call made while a write is in flight sets a flag and repeats
once afterwards, rather than queueing an upload per event.

## Failure

Everything is caught. Offline, signed out, Saved Games disabled, a corrupt
snapshot — all mean "carry on with local progress". Failures are reported to
analytics as `cloud_save_failed` with `operation` of `save` or `load`, so a
platform that quietly stops accepting saves shows up in the data. The player is
told nothing.

## Not verified

No device has run this. The merge and the format are tested; the platform calls
are not reachable from a unit test. Before trusting it: enable Saved Games in
the console, sign in on two devices, finish different levels on each, and check
both end up with the union.
