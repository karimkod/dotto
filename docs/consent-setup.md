# Consent

Dotto uses **UMP** — Google's User Messaging Platform, bundled with
`google_mobile_ads`. It is Google's own certified CMP, which is what AdMob's EU
user consent policy requires for EEA/UK traffic, and Dotto ships in France.

This replaced a hand-built consent screen that offered "Personalized" and
"Standard" and set Consent Mode v2 signals directly. That screen was mechanically
correct but not a certified CMP, which is the whole reason it is gone.

## What UMP owns now

Everything about the decision:

- the form, its wording, and the choices on it — configured in the **AdMob
  console** under Privacy & messaging, not in this repo;
- the consent state, stored by the SDK;
- the Consent Mode v2 signals, emitted to Firebase and AdMob directly.

Consequently there is **no `setConsent()` call** anywhere in this codebase, **no
`npa` flag** on ad requests, and **no Consent Mode defaults** in
`AndroidManifest.xml` or `Info.plist`. Each of those would be a second source of
truth for something UMP already knows, and one that could not be updated when
the player answers the form. Tests assert their absence.

## The flow

1. `ConsentManager.init()` — `requestConsentInfoUpdate()`, then read
   `isConsentFormAvailable()` and `canRequestAds()`. Capped at eight seconds,
   and run inside boot behind the splash: the splash holds its handoff until
   boot settles, so UMP's answer is in before the app decides which screen to
   open. A slow consent service costs opening time, never the ordering.
2. If a form is available and the pre-prompt has not been seen: show the
   pre-prompt.
3. **Continue** → iOS asks ATT first (UMP builds the form around that
   answer) → `loadAndShowConsentFormIfRequired()` → the real form.
4. `AdManager.init()`, once `canRequestAds` is true.
5. Only then may onboarding offer sign-in: the router holds the offer until
   `consentSettled` — UMP answered this launch, or the pre-prompt was seen on
   an earlier one — so a launch where UMP was unreachable cannot put the
   platform's account screen ahead of the consent screen.

Firebase can start at any point — UMP emits the consent signals itself, so
there is no default state for the app to set first. That is the main ordering
constraint the old design had and this one does not.

### The pre-prompt

`lib/screens/consent_screen.dart`. It decides nothing: it explains what the next
screen is, and the only way past it is Continue. It appears **only when UMP
actually has a form**, because outside the EEA there is usually nothing behind
that button and an explainer for a choice that never arrives is worse than no
screen at all.

Local storage is one flag, `consent_prompt_seen` — a UX note, not a consent
record.

### Settings → Ad preferences

`ConsentInformation.reset()`, then request and show again. The reset is the
point: without it UMP considers consent obtained and shows nothing, which is
indistinguishable from a broken button. No pre-prompt here — a player who went
looking for this screen has already been told what it is for.

## Testing the form outside the EEA

UMP reports "not required" for most of the world, so nothing will appear. To
force it, put your device id in `_testDeviceIds` in `consent_manager.dart`:

```dart
static const List<String> _testDeviceIds = <String>['33BE2250B43518CCDA7DE426D04EE231'];
```

The id is printed by the SDK on first run — look for
"Use ConsentDebugSettings.testIdentifiers" in logcat or the Xcode console. It is
specific to a device and install. Debug builds only: the settings are ignored in
release, so a stray id cannot affect players.

The form itself must also exist. If nothing appears with a valid test id, the
message has not been published in the AdMob console.

## Failure behaviour

If UMP cannot be reached, `canRequestAds` falls back to **true**. Outside the
EEA UMP reports "not required" anyway, so treating a transport error as "no form,
ads allowed" keeps the game working where consent was never needed. It does mean
an EEA user on a broken connection could see an ad before the form — Google's own
reference flow makes the same trade.

A launch where UMP never answered also withholds the sign-in offer
(`consentSettled` stays false), so the onboarding order survives the failure:
the next launch, answering from UMP's cache, runs consent first and the offer
after it.

## ATT

iOS only, once, between the pre-prompt and the UMP form — ATT decides whether
the IDFA exists, and UMP reads that answer as it builds the form, so asking
Apple second would assemble the form against a tracking state about to change.
Independent of what UMP returned: Apple
requires the prompt before the IDFA may be read at all, whatever was agreed for
GDPR. Only `notDetermined` can be prompted; every other state is settled, which
is why Ad preferences does not re-prompt — changing it means going to iOS
Settings.

The purpose string stays in `Info.plist` as `NSUserTrackingUsageDescription`.
Apple rejects builds that prompt without one.

## Web

No UMP, no AdMob, no ATT. `needsPrePrompt` is false and the Ad preferences row
is hidden.

## Not verified

None of this has run on a device. Whether the form appears, what it looks like,
whether `canRequestAds` flips correctly, and whether ATT follows cleanly all
need hardware — and in the EEA, or with a test device id. The tests cover the
gating logic, the pre-prompt's conditions, and that the manual mechanism really
is gone.
