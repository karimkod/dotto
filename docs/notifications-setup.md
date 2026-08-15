# Notifications

Two mechanisms, deliberately not one.

* **Pushed (FCM)** — a new weekly challenge. Only we know it exists, so it has
  to come from a server. Sent to a **topic**, not to a device list.
* **Scheduled locally** — "your hint is ready", "your streak is about to
  lapse". The phone can already work these out, so it does. They arrive with no
  network, cost nothing to deliver, and cannot be sent to someone they are not
  true for.

Code: `lib/services/notification_service.dart`. Web and `flutter test` report
`supported == false` and every platform call short-circuits.

## When the player is asked

**Not at launch.** The system permission dialog can be shown once, and on both
platforms a refusal is close to permanent — the only way back is the OS settings
app, which almost nobody visits. So the real decision is made by
`NotificationPromptDialog`, shown **after the first level is won**, when the
player has just been given something and knows what the app is.

It comes back at **level 10, 20, 30, …** for anyone who has not granted
permission yet — "not now" at level 1 is usually about that moment rather than
about notifications, and by level 20 the player can actually answer "what would
I be notified about". The moment permission is granted the prompt is retired for
good, including across a later revoke in the OS settings: that is a decision to
respect, not an invitation to start asking again.

Each milestone is asked at once. `markPromptedAt(milestone)` is called *before*
the system dialog, not after: anything can interrupt a dialog, and none of it
should turn one ask into an ask on every win until the next milestone. The
milestone is derived from the completed-level *count*
(`NotificationService.milestoneFor`), so a count that jumps — a cloud save
merged in, a reinstall — lands on the milestone it passed rather than skipping
the question entirely. Pre-existing installs carry the old `notification_prompted`
bool forward as "asked at milestone 1".

Analytics: `notification_prompt_shown`, `notification_prompt_accepted`,
`notification_prompt_denied`. Accepted/denied are reported against **the OS
answer**, not which button was tapped — someone can accept the pre-prompt and
then decline the system dialog behind it.

## Topics

| Topic | Carries |
| --- | --- |
| `challenges` | The weekly challenge drop |
| `all` | General announcements |

Both ride the single "Challenge alerts" switch. Subscription happens only once
permission is granted, and is re-applied on every launch that has it.

Sending, from the Firebase console (Cloud Messaging → New campaign) or the Admin
SDK. Include a `route` (or `type`) data field so the tap lands somewhere:

```json
{ "topic": "challenges", "data": { "route": "challenge" } }
```

`route: "challenge"` opens the Challenges screen. Anything unrecognised opens
the app and nothing else — deliberately, rather than guessing.

## Local reminders

| Reminder | Fires | Cancelled when |
| --- | --- | --- |
| Hint ready | 24h after a hint is spent — exactly when it returns | The hint is available and unspent |
| Streak at risk | 2 days before the challenge closes, at 18:00 local | The challenge is completed, or has ended |

Two days rather than the last day: a warning that arrives on the deadline mostly
arrives too late to act on. The 18:00 clamp exists because a time derived purely
from the deadline lands at whatever hour the deadline is — a streak warning at
03:00 is a notification that wakes someone up to talk about a puzzle.

`syncReminders()` reconciles both against reality at launch and whenever
permission changes. It cancels as readily as it schedules, which is what stops a
stale reminder — a hint spent on another device and long since regenerated, a
challenge completed after the warning was queued — from firing.

**Nothing here survives the player turning the toggle off**: the setter cancels
what is already queued, because a reminder scheduled yesterday would otherwise
still arrive tomorrow.

## Android

Channels are created at startup, not on first send: a channel's importance is
fixed at creation and any change the player makes to it is respected forever
after, so creating one late or with the wrong importance is not something a
later release can correct.

| Channel | Importance |
| --- | --- |
| `challenges` | default |
| `hints` | low — a hint coming back is not worth a sound |
| `streaks` | default |

`POST_NOTIFICATIONS` and `VIBRATE` arrive by manifest merge from
`flutter_local_notifications`. `RECEIVE_BOOT_COMPLETED` and the two
`ScheduledNotification*Receiver` entries **do not** — they are declared in
`android/app/src/main/AndroidManifest.xml` by hand. Without them Android clears
the alarm table on restart and every pending reminder is silently lost, which
for a 24-hour reminder is a real fraction of them.

`default_notification_channel_id` is set to `challenges` so a pushed message
that names no channel is not dropped on Android 8+.

## iOS — what has to be done by hand

Push does not work on iOS until all of this is done. None of it is in the repo.

1. **Enable the capability.** Apple Developer portal → Identifiers →
   `com.karimkod.dotto` → tick **Push Notifications**.
2. **Regenerate the provisioning profiles** afterwards and update the CI
   secrets. A profile issued before the capability was enabled does not carry
   it, and `codesign` rejects the build against the `aps-environment`
   entitlement — the same dance Game Center needed.
3. **Create an APNs key.** Portal → Keys → new key with **Apple Push
   Notifications service (APNs)** enabled. Download the `.p8` **once** — Apple
   does not offer it again. Note the **Key ID** and the **Team ID**.
4. **Upload it to Firebase.** Console → Project settings → Cloud Messaging →
   iOS app configuration → **APNs Authentication Key** → upload the `.p8` with
   its Key ID and Team ID.

A key is preferred over a certificate: one key covers both sandbox and
production and every app under the team, and it does not expire annually.

In the repo already: `aps-environment` in `Runner.entitlements` (set to
`production`, which is what an App Store profile carries — the actual APNs
environment is chosen by the profile, so a development profile still reaches the
sandbox), `UIBackgroundModes: remote-notification` in `Info.plist`, and the
`UNUserNotificationCenter` delegate claimed in `AppDelegate.swift`. That last
one is easy to miss: without it a scheduled reminder still fires, but tapping it
reaches nothing, so the deep link silently does nothing.

## Settings

Settings → Notifications, between Ad preferences and Rate the app. Three
switches, because they are three different bargains and someone can reasonably
want the first without the third.

If the OS is refusing notifications the switches are **dimmed rather than
hidden**, above a row that says so and opens the system settings. Hiding them
would make the screen look broken; leaving a switch reading "on" while it can
post nothing is a lie the player cannot see through.

## Not verified

No device has received anything. The scheduling arithmetic, the prompt gating
and the tap routing are tested (`test/notification_test.dart`); the FCM
delivery, the APNs handshake, channel behaviour and the reboot receivers are
not. Before trusting it: send a topic message from the console, confirm the tap
opens Challenges, spend a hint and check the reminder arrives 24h later, and
reboot the phone with one pending.
