# Weekly challenges

Challenges are documents in the Firestore `challenges` collection of project
**dotto-d817e**. Publishing one needs no app update; the app refetches on launch
(6-hour cache) and whenever the Challenges screen opens.

## Security rules — apply these first

The collection is **read-only to clients**. Paste into Firestore → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /challenges/{challengeId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

`allow write: if false` blocks writes from every client, including a signed-in
one; challenges are authored in the console or via the Admin SDK. Without rules
Firestore is either open to the world or closed to everyone, and the default is
version-dependent — so set them before the first document, not after.

Nothing else in the app reads Firestore, so a rule that denies everything else
by default is safe.

## Document shape

Document id can be anything; `week_2026_33` is a readable convention. If the
`id` field is absent the document id is used.

```json
{
  "id": "week_2026_33",
  "title": "Teleport Maze",
  "description": "Navigate through portals to reach the goal",
  "startDate": <Timestamp>,
  "endDate": <Timestamp>,
  "reward": "hint",
  "level": {
    "rows": 5,
    "cols": 5,
    "start": [0, 0],
    "startDir": "right",
    "goal": [4, 4],
    "walls": [[1, 1], [2, 2]],
    "gaps": [],
    "destroyers": [[3, 1]],
    "teleporters": [[[0, 4], [4, 0]]],
    "pieces": [
      { "type": "arrow", "direction": "right", "count": 2 },
      { "type": "shield", "count": 1 }
    ],
    "forcedPieces": [
      { "type": "arrow", "direction": "down", "position": [0, 2] }
    ],
    "rotatingArrows": [
      { "direction": "left", "position": [2, 2] }
    ],
    "patrols": [
      { "position": [3, 1], "horizontal": true, "dir": 1 }
    ]
  }
}
```

`reward` is `"hint"` or `"none"`. Coordinates are `[row, col]`.

### A position inside a list is stored as a map

Write `[row, col]` in the JSON on disk. **What reaches Firestore is
`{"r": row, "c": col}`, and `scripts/create_challenge*.js` does the conversion
for you** — there is nothing to do by hand, but it is worth knowing why the
console shows maps where the file shows pairs.

Firestore will not store an array directly inside another array:

```
400 Nested arrays are not allowed
```

It is a data-model limit, not an API quirk — the console, the REST API and the
Admin SDK all refuse it alike. `walls`, `gaps`, `destroyers` and `teleporters`
are each a list of `[row, col]` pairs, so for a while none of them could carry a
single entry and all four had to be empty; the static terrain was simply
unavailable. This went unnoticed until the weeks 34–43 batch, because
`week_2026_33` happened to have all four lists empty anyway.

The nesting is only illegal *directly* inside an array — a map inside an array
may hold an array of its own. So the pairs are written as maps instead:

| Field | On disk | In Firestore |
| --- | --- | --- |
| `walls`, `gaps`, `destroyers` | `[[1,1], [2,2]]` | `[{"r":1,"c":1}, {"r":2,"c":2}]` |
| `teleporters` | `[[[0,4],[4,0]]]` | `[{"a":{"r":0,"c":4}, "b":{"r":4,"c":0}}]` |
| `start`, `goal`, each `position` | `[0,0]` | unchanged — a bare array inside a *map* was always fine |

`Challenge._pos` reads both shapes, and `_pos` also accepts `{"row":…,"col":…}`
for a document typed by hand in the console.

The one cost is that a **document with non-empty terrain is invisible to app
versions up to and including 1.5.0**, whose `_pos` required a two-element `List`
and dropped anything else — and a dropped document takes its whole challenge
with it. Weeks 33–43 leave all four fields empty, so they read identically on
every version; only a newly authored board with walls, gaps, static mines or
fixed teleporters is affected, and it is worth leaving those out until the
release carrying this has been out a while.

### Where this differs from the request, and why

* **`startDir`** was not in the original shape, but the dot has to leave the
  start cell heading somewhere. It is optional and defaults to `"right"` —
  worth setting explicitly, because the wrong default is a different puzzle.
* **The board is square.** `LevelData` carries one `size`, so `rows` must equal
  `cols`; a mismatch is refused rather than cropped. Between 3 and 12.
* **`teleporters`** are pairs of cells — `[[r,c],[r,c]]` — because a teleporter
  is meaningless alone. Note the solver refuses to verify more than one fixed
  pair, because it links portals by board order while the player links them by
  placement order; handing the player a pair through the toolkit instead, as
  `{ "type": "teleporter", "count": 2 }`, sidesteps that.
* **`patrols`** need more than a position: `{ "position": [r,c], "horizontal":
  true, "dir": 1 }`. `dir` is +1 or −1 along the moving axis.
* **`oneShotArrows`** from the original shape is not a separate list. One-shots
  are toolkit pieces: `{ "type": "oneShot", "direction": "up", "count": 1 }`.

### Malformed documents are dropped, not shown

Every field is validated: unknown directions, coordinates off the board, a
window that ends before it starts, a non-square board. A document that fails any
check is skipped with a log line and the others still load. **A broken challenge
is invisible rather than crashing the game** — so if a challenge does not appear,
check the log before checking the network.

Nothing validates that the board is *solvable* **at runtime**. The campaign has a
500-test suite for that; a challenge is trusted. Run
`dart run tool/verify_challenges.dart` before publishing, and play it too.

## Rewards and hint balance

`reward: "hint"` grants one bonus hint on first completion, stored locally under
`challenge_bonus_hints`. Completing again pays nothing.

Bonus hints are spent **after** the level's free hint and **before** any ad is
offered — a player who earned a hint should never be asked to watch a video to
use it. The hint button shows free and bonus hints as one number.

## Streaks

Consecutive completed challenges, counting back from the most recent one that
has **ended**. The live challenge is excluded from the count-back on purpose: a
week still in progress cannot break a streak, and counting it would show the
streak dropping to zero every week until the player got round to playing. A
completed live challenge does extend the run.

## Offline

Two layers. Firestore keeps its own cache, and the last good fetch is written to
SharedPreferences as JSON — which is what covers a cold start with no network,
where Firestore's cache may not answer before the screen draws. The cache
round-trips through the same parser as the network path, so there is one set of
rules rather than two.

## Publishing a document

The database is live (`(default)`, **nam5**, created 2026-08-13 — a location is
permanent, so it stays there) and the rules above are deployed from
`firestore.rules` in the project root:

```
npx firebase-tools deploy --only firestore:rules --project dotto-d817e
```

Documents cannot be written by any client, so authoring needs an admin
credential. There is no service account key for this project, so
`scripts/create_challenge.js` borrows the Firebase CLI's own login instead:

```
node scripts/create_challenge.js scripts/challenge_week_2026_33.json
```

It reads a plain-JSON challenge in the documented shape, converts it to
Firestore's typed representation — `startDate`/`endDate` become real timestamps
— and writes it. It needs `npx firebase-tools login` to have been run, and
nothing else.

`scripts/create_challenges.js` does the same for a batch, fetching the token once
and reusing it. With no arguments it publishes every `challenge_week_*.json`
under `scripts/`; `--dry-run` lists what it would write without writing:

```
node scripts/create_challenges.js --dry-run
node scripts/create_challenges.js scripts/challenge_week_2026_34.json ...
```

Every write is a PATCH keyed on the document id, so re-running republishes rather
than duplicating, and the whole batch is parsed before anything is sent — a typo
in the last file will not leave the first nine live.

**Put the JSON under `scripts/` and it gets checked.**
`test/challenge_document_test.dart` sweeps every `challenge_week_*.json` in the
directory and puts each through `Challenge.fromMap` and the solver, so a field
name the app does not read, or a board that cannot be beaten, fails the suite
instead of the player's week. It also checks the windows run consecutively from
`week_2026_34` on. This is the gap the section above warns about — solvability is
*not* validated anywhere at runtime.

`tool/verify_challenges.dart` is the same check with a design report attached:

```
dart run tool/verify_challenges.dart
```

For each document it prints the solution count and the fewest pieces any win
uses. **`min` equal to the kit size means TIGHT** — no piece can be left in the
tray. A board that can be beaten while holding a piece back is a board whose
spare piece was a lie, so it is worth fixing before publishing even though it
plays. Only an unparseable or unbeatable document fails the command.

## Verified

`week_2026_33` ("Arrow Maze") is published and live from 2026-08-12 to
2026-08-19. Checked from an anonymous client holding only the app's API key:
the document reads, a write to it is `PERMISSION_DENIED`, and a read of any
other collection is `PERMISSION_DENIED`.

Weeks 34–43 are published and run consecutively from 2026-08-17 to 2026-10-26,
one per Monday:

| Week | Live from | Title | Teaches |
| --- | --- | --- | --- |
| 34 | Aug 17 | Switchback | pinned arrows, breaking a loop |
| 35 | Aug 24 | Live Wire | shield against a head-on patrol |
| 36 | Aug 31 | Detour | reading a picket for its one gap |
| 37 | Sep 7 | Warp Line | placing a portal pair |
| 38 | Sep 14 | Night Patrol | choosing a crossing by its timing |
| 39 | Sep 21 | Hold Still | stacking pauses to retime |
| 40 | Sep 28 | Clockwork | a rotating arrow over four passes |
| 41 | Oct 5 | Crossfire | one shield, two guarded floors |
| 42 | Oct 12 | One and Done | a one-shot arrow and a return trip |
| 43 | Oct 19 | Grand Tour | rotor, patrol and shield together |

Every one is solvable and TIGHT under `tool/verify_challenges.dart`, and each was
read back out of Firestore and compared field by field with the JSON on disk.
`week_2026_33` overlaps week 34 by two days — it was published on a Wednesday
cadence — which is harmless: `currentAt` walks the list newest-first, so week 34
is what shows from Aug 17.

`week_2026_33` itself is **LOOSE**: 1 of its 4 pieces is enough to beat it (drop
a `down` arrow at (2,4) and the forced arrows do the rest). It is left alone
because it is live, but it is the reason the tightness report exists.

The read path has now been walked end to end on a device. An emulator on API 35
fetched all eleven documents and parsed all eleven (`Challenges: 11 fetched, 11
parsed`), the menu badge lit, and the Challenges screen opened on week 33 — and
on **nothing else**, which is what "the challenges are not showing" turned out
to mean. The screen had two sections, live and past, and ten of the eleven
documents were scheduled for a future week: published, fetched, parsed, held in
memory, and rendered nowhere. "Coming up" is that missing third section.

Two things came out of the same look:

* A successful fetch used to log nothing, so an empty screen looked identical
  whether the query returned nothing, the parser dropped everything, or the
  screen simply had no place to put what it got. `refresh` now logs how many
  documents it fetched and how many survived parsing — that one line is what
  the "check the log" advice above is worth.
* The launch fetch is unawaited, so the menu decided its badge from an empty
  list and had no reason to build again. It now waits on
  `ChallengeService.pending`, which costs one rebuild.

The offline copy works as far as it can be checked with the network up: the
second launch was inside the six-hour TTL, so it refetched nothing — no
`Challenges:` line in the log — and drew all eleven weeks out of
SharedPreferences. Still unverified is a cold start with the radio actually off.
