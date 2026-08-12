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
    "pieces": [
      { "type": "arrow", "direction": "right", "count": 2 },
      { "type": "shield", "count": 1 }
    ],
    "forcedPieces": [
      { "type": "arrow", "direction": "down", "position": [0, 2] }
    ],
    "rotatingArrows": [],
    "teleporters": [],
    "patrols": []
  }
}
```

`reward` is `"hint"` or `"none"`. Coordinates are `[row, col]`.

### Where this differs from the request, and why

* **`startDir`** was not in the original shape, but the dot has to leave the
  start cell heading somewhere. It is optional and defaults to `"right"` —
  worth setting explicitly, because the wrong default is a different puzzle.
* **The board is square.** `LevelData` carries one `size`, so `rows` must equal
  `cols`; a mismatch is refused rather than cropped. Between 3 and 12.
* **`teleporters`** are pairs of cells — `[[r,c],[r,c]]` — because a teleporter
  is meaningless alone.
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

Nothing validates that the board is *solvable*. The campaign has a 500-test
suite for that; a challenge is trusted. Play it before publishing.

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

## Not verified

No device has run this, and no document exists yet. The parser and streak logic
are tested; the Firestore read, the offline cache and the rules are not. Before
trusting it: apply the rules, publish one document, and check it appears — then
turn off the network and check it still does.
