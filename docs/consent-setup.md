# Consent

## Read this first: the screen is not a certified CMP

Dotto's consent screen is hand-built. Google's EU user consent policy requires
publishers serving ads to EEA/UK users to use a **Google-certified CMP**
integrated with the IAB TCF. A custom screen is not one, however carefully it is
worded, and Dotto targets France.

What is here is mechanically correct — Consent Mode v2 signals are set, the
choice rides on every ad request, and nothing personalized is requested before
the player answers. It is not the certified consent flow AdMob asks for in
Europe. The UMP SDK bundled with `google_mobile_ads` is Google's own certified
CMP and is free; it was removed from this codebase earlier by request and is
what should front this screen before EEA traffic scales.

Treat what follows as the app's own preference UI, correctly wired.

## What the two choices mean

| Signal | Personalized | Standard |
|---|---|---|
| `analytics_storage` | granted | granted |
| `ad_storage` | granted | granted |
| `ad_user_data` | granted | **denied** |
| `ad_personalization` | granted | **denied** |
| AdMob `npa` extra | `0` | `1` |

Both choices still show ads and still let the game measure its own use.
"Standard" withholds sending the player's data to Google for targeting.

There is no "no ads" option, by design — ads are how the game stays free.
"Standard Ads" is the reject path, which is what GDPR requires exist.

## Ordering, which is the fragile part

1. `ConsentManager.init()` — load the saved choice. Blocking, because it decides
   whether the consent screen is the first thing shown.
2. `ConsentManager.applyDefaults()` — ad signals denied.
3. `Firebase.initializeApp()`, via `Analytics.init()`.
4. Consent screen, if no choice is on file.
5. ATT prompt (iOS only), after the screen.
6. `AdManager.init()` — **only** once a choice exists.

Steps 2 and 3 cannot swap: defaults set after Firebase starts arrive too late to
govern the first events. Step 6 is held back on a first launch so no ad is
requested before the player has answered.

The same defaults are declared natively as well — `AndroidManifest.xml` and
`Info.plist` — because the SDKs read them before any Dart runs, and that gap is
not reachable from `main()`. Tests pin those entries; their absence is invisible
at runtime.

## ATT

iOS only, prompted once, after the GDPR screen rather than beside it — two
system-looking dialogs at once reads as a wall of permissions.

ATT and the GDPR choice are independent, and the **stricter answer wins**: a
player who picks Standard Ads and then allows tracking still gets
non-personalized ads. Only `notDetermined` can be prompted; every other state is
already settled, and asking again just returns the same answer. That is why
Settings → Ad preferences does not re-prompt — changing it means going to iOS
Settings, which is Apple's design.

Purpose string is in `Info.plist` as `NSUserTrackingUsageDescription`. Apple
rejects builds that prompt without one.

## Storage

`consent_given`, `consent_personalized`, `consent_timestamp` (epoch ms), in
SharedPreferences. If storage fails the player is asked again — a nuisance,
where assuming consent that was never given is not an option.

## Web

No consent screen: no AdMob, no ATT. `needsConsentUi` is false there, and the
Ad preferences row is hidden.

## Not verified

None of this has run on a device. The consent screen, the ATT prompt, whether
Consent Mode signals actually reach Google, and whether `npa=1` changes what
AdMob serves all need real hardware. The tests cover the choice-to-signal
mapping, the native declarations, and that the screen cannot be escaped without
answering.
