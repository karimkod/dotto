# Analytics setup

Firebase Analytics (GA4) is the only analytics stack in the app. There is no
GameAnalytics, Amplitude, Mixpanel or Adjust, and nothing here needs one — see
"Why not a third-party SDK" at the bottom.

Events are defined in `lib/analytics/analytics_service.dart`, one method per
event, against project **dotto-d817e** (`docs/firebase-setup.md` covers the
project config). Crash reporting is separate: `lib/analytics/crash_reporting.dart`
and `docs/crashlytics-setup.md`.

## The dashboard

```bash
node scripts/analytics_dashboard.js --dataset analytics_549434438 --days 30
```

The GA4 property behind `dotto-d817e` is **549434438** (account 155121983), so
`analytics_549434438` is the dataset name the export will create. The property
is reachable directly at
`https://analytics.google.com/analytics/web/#/a155121983p549434438/`.

Runs every query in `analytics/queries/` against the GA4 BigQuery export and
writes `analytics/out/dashboard.html` — a single self-contained file with no
server and nothing to deploy. Output is gitignored; regenerate it rather than
committing it.

Credentials are borrowed from the Firebase CLI exactly as
`scripts/create_challenge.js` does, so `npx firebase-tools login` is the only
setup. No service account key is needed and none exists.

**One query failing does not fail the dashboard.** The panel renders its own
error and every other panel still fills in, so a schema change breaks one metric
rather than the page.

### It needs the BigQuery export, which is currently OFF

As of 2026-11-16 the project still has **zero BigQuery datasets**, as it did on
2026-09-08: the GA4 → BigQuery link has never been enabled, so the dashboard
renders eight "dataset not found" panels and nothing else. Turn it on at:

> Firebase console → Project settings → **Integrations** → BigQuery → Link

Three things to know before enabling it:

1. **It is not retroactive.** The first daily table lands the day *after* the
   link is made. Every day of history before that is unrecoverable — the raw
   events were never stored anywhere that can be queried. This is the one item
   on this page worth doing today rather than when the dashboard is next wanted.
2. **It needs the Blaze plan.** BigQuery export is not available on Spark.
   Query cost for a game this size is negligible (the free tier is 1 TB/month
   scanned, and a 30-day run here scans a tiny fraction of that), but the plan
   upgrade is a real prerequisite.
3. **The dataset is named after the GA4 property, not the Firebase project** —
   `analytics_123456789`. That id is what `--dataset` takes.

Until then, the Firebase console's own reports still answer four of the seven
metrics on their own, with no setup: DAU (Analytics → Realtime/Engagement),
session length (Engagement → average engagement time), retention (Retention
card, D1–D30 cohorts), and the event counts behind level completion. What the
console cannot do is per-level funnels and drop-off curves across 103 levels —
that is what the BigQuery queries are for.

## GA4 explorations (built 2026-09-09)

Four saved explorations live in the property, under Explore. They read GA4's
own processed data, so they work today without the BigQuery export — and they
are capped by GA4's sampling and its 28-day-by-default window, which is exactly
what the BigQuery pack exists to escape. Treat these as the day-to-day view and
the dashboard as the one that answers precisely.

| Exploration | Type | Answers |
|---|---|---|
| 1. Install to first win funnel | Funnel | `first_open` → `onboarding_completed` → `level_start` → `level_complete` |
| 2. Level completion and drop-off | Free form | Level ID × event name, active users + event count |
| 3. Retention by daily cohort (D1 / D7 / D30) | Cohort | Daily cohorts, day-0 to day-N return |
| 4. Gaming overview | GA4 Gaming template | DAU/WAU/MAU stickiness, ARPPU, total revenue |

Number 2 has stayed empty: it is built on Level ID, which has never collected
anything (see "Level ID and World ID were never filled" below). Numbers 1, 3
and 4 read full history, because they are built on event names and GA4
automatic collection rather than on custom dimensions.

## What each metric comes from

| Metric | Source | Query |
|---|---|---|
| Level completion rate | `level_start` / `level_complete` | `01_level_funnel.sql` |
| Drop-off (survival curve) | `level_complete` | `02_dropoff.sql` |
| Drop-off (per level, with intent) | `level_abandon` | `03_abandon_detail.sql` |
| DAU, session length | GA4 automatic collection | `04_dau_sessions.sql` |
| Ad revenue per user | `ad_impression` | `05_ad_revenue.sql` |
| Retention D1/D7/D30 | `user_first_touch_timestamp` | `06_retention.sql` |
| Onboarding funnel | `onboarding_*` | `07_onboarding_funnel.sql` |
| IAP conversion | *nothing — no IAP exists* | `08_iap_conversion.sql` |

Each query carries its own definition and caveats as a comment block at the top
of the file, and the dashboard renders that block above the table. The
definition of a metric belongs next to the SQL that computes it, not in this
table, so that the two cannot drift apart.

## Ad revenue needs the paid-event callback enabled

`AdManager._reportPaid` attaches AdMob's `onPaidEvent` to every rewarded and
interstitial ad as it loads, converts micros to whole currency units, and sends
GA4's reserved `ad_impression` event. That event is the *only* thing in the app
that carries money — `rewarded_ad_shown` and `interstitial_shown` count
impressions and no amount of counting them adds up to revenue.

The Flutter plugin documents `onPaidEvent` as "available for allowlisted
accounts only". Where an account does not have it, the callback never fires,
`ad_impression` is never sent, and revenue reads as zero — which looks exactly
like no ads having served. **Check impressions before concluding anything about
revenue:** `05_ad_revenue.sql` reports impressions and revenue side by side for
precisely this reason. If impressions are healthy and revenue is zero, the
problem is the callback, not the ads.

Cross-check the total against the AdMob console, not against Play Console
earnings — AdMob's own numbers are the ones this is estimating.

## Drop-off: three numbers, not one

`03_abandon_detail.sql` splits every level's starts into three:

- **completes** — finished it.
- **abandons** — left the level deliberately. `level_abandon` fires from the
  game screen's `dispose`, so this is backing out to the menu.
- **unexplained_exits** — starts minus the other two. Nothing disposes when the
  OS kills the app or the player swipes it out of the task switcher, so this is
  the "walked away with the app still on this level" bucket.

A level with a large *unexplained* count and few deliberate abandons is one
people put the phone down on, which is a different problem from one they
actively retreat from. Neither is visible if you only subtract completes from
starts.

`level_abandon` is campaign-only, gated the same way `level_start` is: designer
previews and weekly challenges are excluded, so a board that never reported
starting can never report being abandoned.

## The custom dimensions — registered 2026-09-09

GA4's own UI (not BigQuery) will not group by a custom parameter until it is
registered. These are now live under Analytics → Admin → **Custom definitions**:

| Dimension name | Parameter | Scope |
|---|---|---|
| Level ID | `level_id` | Event |
| World ID | `world_id` | Event |
| Ad Format | `ad_format` | Event |
| Hint Type | `hint_type` | Event |
| Interstitial Trigger | `trigger` | Event |
| Levels Completed | `levels_completed` | User |
| Current World | `current_world` | User |

**Registration is not retroactive in the console.** They collect from
2026-09-09 forward and show `(not set)` for everything before it, so any
console report broken down by level is empty until roughly a day of data has
accrued. Nothing recovers the earlier breakdowns in the UI.

**Level ID and World ID were never filled.** GA4 fills an event-scoped custom
dimension from a text parameter only, and the app sent `level_id` and
`world_id` as numbers. Checked on 2026-11-16: both read `(not set)` on every
`level_start`, `level_complete` and `level_fail`, while Hint Type, a text
parameter registered the same day, filled normally. The app now sends both as
text, level ids zero-padded to three digits (`011`) so that a text sort, which
is what GA4 uses, keeps them in level order. The two dimensions fill from the
first release that carries the change; the registrations themselves are
correct and need no edit. The months before it cannot be recovered in the
console, and the queries in `analytics/queries/` read either form.

**A level id is not the number a player sees.** Ids are permanent, and the
retired levels (3, 9, 10, 12, 13, 18 and 19) left gaps, so the game numbers
its levels 1–103 while their ids run from 1 to 110: id 11 is the eighth level
a player meets. `levelIds` in `lib/data/levels.dart` is the mapping.

BigQuery is unaffected either way: the raw export carries every parameter
whether or not it was ever registered, which is a further reason the dashboard
reads from BigQuery rather than the Data API.

`Ad Format` was registered ahead of the event that fills it — `ad_impression`
ships in the next release — so GA4 offered no autocomplete for it and it was
entered by hand. That is expected and not a mistake to correct.

The caps are 50 event-scoped and 25 user-scoped definitions; this uses 5 and 2.

## IAP conversion: there is nothing to measure

Dotto has no in-app purchases. There is no `in_app_purchase` dependency in
`pubspec.yaml`, no product ids anywhere in `lib/`, and no code path that could
log a purchase. The app monetises through AdMob alone, which is also what the
Play listing says.

`08_iap_conversion.sql` is kept and wired into the dashboard as a deliberately
empty panel so that "0% conversion" is never read as a measurement of a failing
storefront. It returns zero rows against a correct dataset and will keep doing
so until products ship — at which point `purchase` is the reserved GA4 event
name to send, and the query starts working with no edit.

## Why not a third-party SDK

GameAnalytics, Adjust and friends earn their place through attribution,
LiveOps-style remote config, and cross-network mediation reporting. Dotto has a
single ad network, no paid UA, and no live economy to tune. Adding a second SDK
would double the consent surface (the UMP flow in `lib/consent/` was already
what App Review rejected a build over), add a second definition of "session"
that disagrees with GA4's, and buy nothing the BigQuery export does not already
give. Revisit if paid acquisition starts, where attribution genuinely cannot be
done from first-party data.
