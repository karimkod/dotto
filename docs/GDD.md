# Dotto — Game Design Document

> A minimalist, tactile dot-routing puzzle game.
> Plan a path, place your pieces, press play, and watch the dot find its way home.

**Version:** living document · **Engine:** Flutter · **Package:** `com.dotto/dotto`

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Core Mechanics](#2-core-mechanics)
3. [Grid Elements](#3-grid-elements)
4. [World Progression (30 Worlds)](#4-world-progression-30-worlds)
5. [Difficulty Design](#5-difficulty-design)
6. [Level Generation](#6-level-generation)
7. [Art Direction](#7-art-direction)
8. [Sound Design](#8-sound-design)
9. [UI / UX](#9-ui--ux)
10. [Features](#10-features)
11. [Tech Stack & Architecture](#11-tech-stack--architecture)
12. [Roadmap](#12-roadmap)

---

## 1. Game Overview

**Dotto** is a single-player logic puzzle. Each level is a small square grid with
a **start** cell (where a dot begins, facing a fixed direction) and an **exit**
cell. The dot moves on its own — one cell per tick, in a straight line. The
player never controls the dot directly. Instead they **place a limited kit of
elements** (arrows, pauses, teleporters, …) on empty cells to redirect, delay,
and reroute the dot around hazards until it reaches the exit.

It is a "set it up, then watch it run" puzzle. All the thinking happens during a
calm **planning** phase; pressing **Play** runs the simulation and reveals
whether the plan works — a small, repeatable hit of "I solved it."

| | |
|---|---|
| **Genre** | Logic / routing puzzle |
| **Players** | Single-player |
| **Content** | 750 levels across 50 worlds (15 levels each) |
| **Platforms** | Flutter — web first; Android (minSdk 21) & iOS (14) ready |
| **Orientation** | Portrait, phone-sized (max content width ~460px) |
| **Session** | Seconds-to-minutes per level; pick-up-and-play |
| **Monetization (proposed)** | Free with optional hint packs / cosmetic themes; no forced ads |
| **Tone** | Warm, calm, satisfying; soft "boardgame" tactility |

### Design pillars
1. **Readable** — the whole puzzle state is visible at a glance; no hidden info.
2. **Tactile** — placing a piece feels like setting a chess piece on a board.
3. **Forgiving** — instant retry, no penalties, no timers in core play.
4. **Bite-sized** — every level is a small, complete thought.

---

## 2. Core Mechanics

### 2.1 The core loop
1. **Read the board** — note start + direction, exit, and hazards.
2. **Plan** — work out the route.
3. **Place pieces** — drag elements from the toolkit onto empty cells.
4. **Play** — press Play; the dot moves automatically.
5. **Resolve** — win (reach exit) or fail (edge / wall / hazard).
6. **Iterate or progress** — retry with pieces intact, or move to the next level.

### 2.2 Movement rules (one tick ≈ 400ms)
Each tick, resolved in order:

1. Moving hazards advance.
2. If the dot now shares a cell with a moving destroyer → **die**.
3. If paused, decrement the pause counter and skip movement this tick.
4. Compute the next cell in the current heading:
   - Off the grid edge → **fail** ("ran off the edge").
   - Into a wall → **fail** ("hit a wall").
5. Move into the next cell; record the trail; then apply the cell:
   - **Gap** → die ("fell into a hole").
   - **Destroyer** → if the dot is **shielded**, the destroyer is destroyed, the
     shield is spent, every **wall orthogonally adjacent** to that destroyer is
     **chain-exploded** (removed, opening a path), and the dot survives and
     continues; otherwise **die** (with an explosion).
   - **Arrow** → adopt its direction.
   - **Pause** → halt for 2 ticks.
   - **Shield** → gain a one-use protective aura (only one at a time).
   - **Teleporter** → jump to its pair (instant).
6. If the current cell is the **exit** → **win**.

### 2.3 The kit (economy of pieces)
Every level grants a fixed **toolkit** (e.g. `1× Up arrow`, `2× Teleporter`).
The challenge is solving the route **within budget**. Placing consumes a slot;
removing returns it. Optional star goals reward solving with fewer pieces.

### 2.4 Win / fail
- **Win:** dot enters the exit. Plays a chime, marks the level complete.
- **Fail:** edge / wall / hazard. Shows the reason; **Retry** keeps placed
  pieces, **Clear & Edit** resets the kit. No lives, no penalty.

---

## 3. Grid Elements

### 3.1 Pre-placed (level-defined) cells
| Element | Color | Behavior |
|---|---|---|
| **Start** | Green `#81C784` | Dot origin; fixed launch direction (shown by a subtle pulsing hint arrow + lead dots) |
| **Exit** | Gold `#FFD54F` | The goal — reaching it wins |
| **Wall** | Blue-gray `#78909C` | Solid; the dot fails if it would enter |
| **Destroyer** | Red `#EF5350` | Deadly static cell — drawn as a spiky sea-mine that pulses subtly; blows up on contact |
| **Moving Destroyer** | Red (patrolling) | Deadly hazard sliding along a line each tick (timing puzzles) |
| **Gap / Hole** | Dashed outline | The dot falls in and dies |

### 3.2 Player-placeable elements (the toolkit)
| Element | Color | Effect |
|---|---|---|
| **Arrow** (Up/Down/Left/Right) | Blue `#1E88E5` | Redirect the dot to a new heading |
| **Pause** | Purple `#BA68C8` | Hold the dot in place for 2 ticks |
| **Teleporter** | Orange `#FF8A65` | Placed in pairs; enter one, exit the other |
| **Shield** | Cyan `#38BDF8` | A bubble that gives the dot a one-use protective aura. The next destroyer it touches is **destroyed** and the dot **survives** (the aura is then spent), and every **wall adjacent** to that destroyer is **chain-exploded** away — turning a destroyer-next-to-a-wall into a *door*. Only one shield at a time; an unshielded dot dies normally. |

### 3.3 Proposed elements (roadmap — not yet implemented)
| Element | Concept |
|---|---|
| **Splitter** | Spawns a second dot; both must reach exits |
| **One-shot arrow** | Redirects once, then disappears |
| **Rotator** | Turns the dot 90° (CW or CCW) regardless of incoming heading |
| **Speed pad** | Dot moves 2 cells next tick |
| **Toggle wall** | Alternates solid/open on a timer |
| **Button + gate** | Dot crossing a button opens a remote gate |
| **Color keys / doors** | Dot must collect a key cell before a matching door |
| **Bouncer** | Reflects the dot like a wall at 45° |
| **Sticky pause** | Holds until a moving hazard passes, then releases |
| **Portal exit** | Multiple exits; any one completes (or a specific colored one) |

Each new element is introduced in its own tutorial level, then combined.

---

## 4. World Progression

The game is structured into 50 worlds with 15 levels each (750 levels). Each world introduces or combines elements, with difficulty ramping within each world and across the game. Every world's Level 1 teaches the new mechanic in isolation.

### Level structure (per world, 15 levels)
- **Levels 1–3 — Learn:** the world's new mechanic in isolation (easy).
- **Levels 4–7 — Combine:** the new mechanic with elements from this world.
- **Levels 8–10 — Challenge:** harder puzzles using this world's mechanics.
- **Levels 11–15 — Exam:** combine the current world with everything from all
  previous worlds (hardest of the world).

### Phase 1: Foundations (Worlds 1-3, 45 levels)
- **World 1:** Arrows + walls + forced arrows (tutorial world, done)
- **World 2:** Static destroyers intro (10 levels, 16–25, done)
- **World 3:** Shields + chain explosions — shielded hits blast adjacent walls
  into doors (15 levels, 26–40, done)

### Phase 2: Timing (Worlds 4-6, 45 levels)
- **World 4:** Pause blocks intro
- **World 5:** Moving destroyers intro
- **World 6:** Pause + moving destroyers (timing mastery)

### Phase 3: Spatial (Worlds 7-10, 60 levels)
- **World 7:** Teleporters intro
- **World 8:** Forced teleporters
- **World 9:** One-time destroyers intro
- **World 10:** Teleporters + one-time destroyers + everything so far

### Phase 4: Objectives (Worlds 11-14, 60 levels)
- **World 11:** Key/lock exit intro
- **World 12:** Multi-pass exit intro
- **World 13:** Mixed objectives
- **World 14:** All previous elements + objectives

### Phase 5: Multi-dot (Worlds 15-18, 60 levels)
- **World 15:** Splitter intro
- **World 16:** Splitter + destroyers/teleporters
- **World 17:** Double exit intro
- **World 18:** Double exit mastery

### Phase 6: Advanced Mechanics (Worlds 19-30, 180 levels)
- **Worlds 19-20:** Teleporting destroyers
- **Worlds 21-22:** One-way gates
- **Worlds 23-24:** Toggle switches
- **Worlds 25-26:** Ice tiles + bounce walls
- **Worlds 27-28:** Speed boost + slow zones
- **Worlds 29-30:** Color gates + changers

### Phase 7: Expert (Worlds 31-40, 150 levels)
- **Worlds 31-34:** Wrap edges, timer bombs, pressure plates
- **Worlds 35-40:** All elements mixed, large grids, minimal toolkits

### Phase 8: Mastery (Worlds 41-50, 150 levels)
- Everything combined, 8x8-9x9 grids, ultimate challenges

---

## 5. Difficulty Design

Difficulty is shaped along independent axes so levels can be tuned precisely:

- **Grid size:** 3×3 → 8×8 (more space = more possibilities).
- **Kit size & variety:** from a single arrow to mixed multi-element kits.
- **Hazard density & motion:** static → patrolling → multiple synchronized.
- **Solution length & uniqueness:** short/obvious → long/spiral → single unique.
- **Timing tightness:** how exact pause/teleport timing must be.
- **Red herrings:** decoy pieces or routes that look right but fail.

**Per-level rating (proposed):** `Easy / Medium / Hard` badge (already on the
play button), backed by an internal score combining the axes above. Optional
**star goals**: ⭐ solve, ⭐⭐ solve under a piece budget, ⭐⭐⭐ solve with no wasted
pieces / shortest path.

**Pacing within a world:** teach → practice → twist → combine → "boss" level.
Difficulty curves up inside a world and resets slightly at each new world so a
new mechanic never lands on an already-hard board.

---

## 6. Level Generation

A **hybrid** approach:

1. **Hand-authored** tutorial and "boss" levels for guaranteed quality and
   teaching beats (worlds' first and last levels especially).
2. **Procedural generation + solver-verification** for the bulk:
   - **Generate:** place start/exit/hazards on a grid by parameterized rules
     (size, hazard density, kit composition for the target difficulty).
   - **Solve:** a deterministic search (BFS/DFS over placements + simulation)
     finds all minimal solutions.
   - **Filter:** keep levels that are **solvable**, **non-trivial** (require the
     full kit), and ideally **uniquely** solvable; reject the rest.
   - **Score:** rate by solution length, branching, and timing tightness; bucket
     into Easy/Medium/Hard.
   - **Curate:** humans review a generated batch before shipping.

The simulation is the single source of truth — the same `_beat()` rules that run
in-game verify generated levels, so a level is "valid" iff the engine can solve
it. Daily puzzles use a seeded generator for a shared puzzle-of-the-day.

---

## 7. Art Direction

A warm, hand-drawn **"boardgame"** aesthetic: thick dark outlines, white fills,
rounded corners, minimal structural shadows.

**Palette**
- Background: warm cream `#FAF8F5` with a faint square grid
- Cells / cards: white with thick dark `#2D2D2D` outlines
- Accent / dot: warm orange `#FFB347`
- Coral (play / current level): `#FF6B6B`
- Locked: blue-gray `#78909C`
- Completed star: gold `#FFD54F`
- Ink / text: `#2D2D2D`

**Element colors** as in §3 (arrows blue, pause purple, teleporter orange,
hazards red, start green, exit gold).

**Typography:** Poppins (bold-italic wordmark), Nunito (body), via Google Fonts.

**Game feel ("juice")** — tactile and readable, never rushed:
- **Dot:** `easeInOutCubic` glide, arrival squish (~1.15×), continuous soft glow.
- **Trail:** last ~6 cells fade by recency with a warm glow.
- **Cell reactions:** warm flash on entry; element-colored flash when an arrow/
  pause/teleporter activates.
- **Placement:** weighty pop-in (`0→1.3→0.95→1.05→1.0`, ~600ms), lingering cell
  flash (~500ms), border thicken (3→5→3px), neighbor ripple, medium haptic, and
  a magnet-snap of the dropped ghost into the cell.
- **Start hint:** small semi-transparent orange arrow with a gentle breathing
  pulse + faint lead dots — a hint, not a focal point.
- **Destroyer hit:** a ~0.5s explosion — white-hot flash, expanding shock ring,
  and red/orange/yellow fragments that fly out, decelerate, fall and fade — then
  the fail card (or, if shielded, the dot survives and the destroyer is cleared).
- **Chain explosion:** each demolished wall shatters with its own gray fragment
  burst, and the cleared cells render as open floor for the rest of the run.
- **Shield aura:** a glowing cyan bubble around the dot while it is shielded.

---

## 8. Sound Design

Lightweight, **file-free** audio synthesized with the Web Audio API
(oscillators + noise buffers); a no-op stub on non-web platforms. Audio unlocks
on the first user interaction (browser autoplay policy).

| Event | Sound |
|---|---|
| Place element | Deep, chunky "thock" (400Hz + 180Hz body, sharp attack/fast decay) |
| Remove element | Soft filtered-noise whoosh |
| Dot moves one cell | Very subtle tick (~1000Hz, barely audible) |
| Dot hits arrow | Satisfying two-note ping (880→1200Hz) |
| Dot hits pause | Low hum (200Hz) |
| Dot enters teleporter | Frequency sweep (400→1600Hz) "zzip" |
| Dot dies (edge / wall / gap) | Noise-burst "poof" with decay |
| Dot hits destroyer | Explosion "boom" (low-pass noise blast + descending sub + square crack) |
| Dot gains a shield | Soft rising cyan shimmer |
| Dot reaches exit | Rising chime (C5→E5→G5 arpeggio) |
| Level complete | Celebratory major chord |
| Play button | Subtle click |

**Proposed:** soft ambient music per world (toggleable), a global mute, and
separate SFX / music / haptics settings.

---

## 9. UI / UX

### Main menu — level path
A vertical, scrollable "winding climb" (level 1 at the bottom). Cards centered on
a thick dashed line:
- **Locked:** lock icon, grayed.
- **Current:** coral outline + glow, slightly larger.
- **Completed:** number + gold star badge.

Top bar (thick-bordered tiles): profile, crown hint-counter, settings. Fixed
bottom coral **Play** button with the current level + difficulty badge. Left-rail
shortcuts: daily challenge (locked) and calendar. Edge fade + auto-scroll to the
current level; scrollbar hidden.

### Game screen
Top: back, "Level N", crown. Center: the square board (a `CustomPainter`). Below:
the toolkit row (selectable, count badges). Bottom: **Reset** + **Play** pills.
Overlays for **win** ("Level Complete!" → Next/Replay) and **fail** ("Try Again"
→ Retry/Clear).

### Interaction
- **Drag-and-drop (primary):** drag from toolkit → ghost (≈1.2× cell, soft
  shadow) follows the finger → hovered valid cell breathes → release magnet-snaps
  and pops in. Drag placed pieces to move; drop off-grid to remove.
- **Tap (fallback):** tap to select then tap a cell; tap a placed piece to remove.

All drag math is manual (pan gestures, no `DragTarget`) so drops register
anywhere on the grid across platforms.

---

## 10. Features

**Implemented**
- Core puzzle engine (arrows, walls, edges, destroyers, gaps, pause, teleporter,
  shield).
- **Shield** element: a one-use protective aura that destroys the next destroyer
  the dot touches, lets it survive, and **chain-explodes the adjacent walls**
  (destroyer-doors). Single source of truth in the simulator + path solver.
- Destroyer explosion FX (flash + fragments + boom) on a fatal or shielded hit,
  plus gray wall-shatter bursts for chain explosions; spiky sea-mine icon.
- 40 levels across 3 worlds (World 3 = Shields & Explosions, levels 26–40).
- Drag-and-drop placement, move, and removal; tap fallback.
- Full juice pass (animations) and Web Audio SFX.
- Boardgame art style across menu and game; winding level path; start-direction
  hint.

**Planned**
- Progress persistence (SharedPreferences) and unlock flow.
- Star ratings & piece-budget goals.
- Daily puzzle (seeded generation).
- 50 worlds of content + procedural generation pipeline.
- Settings: sound / music / haptics toggles; colorblind-friendly palette option.
- Hint system (spend crowns to reveal a next piece).
- Cosmetic themes (dot skins, board styles).
- Level editor & sharing (share codes).
- Localization.

---

## 11. Tech Stack & Architecture

**Stack:** Flutter / Dart, Material 3, `google_fonts`, `package:web` (Web Audio
via `dart:js_interop`). Targets web, Android, iOS from one codebase.

```
lib/
  main.dart                  # app entry → MenuScreen
  theme/app_theme.dart       # palette, text styles, shadows
  models/
    level.dart               # menu Level (status, difficulty)
    grid_cell.dart           # Direction, CellType, PlacedType, ToolType
    level_data.dart          # LevelData (size, start, exit, hazards, toolkit)
    game_state.dart          # GameStatus, PlacedElement, DotState
  data/
    levels.dart              # menu levels (20+)
    level_definitions.dart   # playable level specs
  screens/
    menu_screen.dart         # winding level path
    game_screen.dart         # planning, run loop, effects, gestures
  widgets/
    top_bar.dart, level_card.dart, play_button.dart
    game_grid.dart           # board CustomPainter + GridGeometry + DragGhost
    game_toolbar.dart        # selectable toolkit tiles
  audio/
    sfx.dart                 # facade (conditional import)
    sfx_web.dart             # Web Audio implementation
    sfx_stub.dart            # no-op (VM / tests)
```

- **State:** lightweight `StatefulWidget` (no external state lib yet; a provider
  or Riverpod layer can be added for persistence/progression).
- **Rendering:** one `CustomPainter` draws cells, hazards, trail, glows, and
  scaled pieces; the dot and drag ghost are overlay widgets. A continuously-
  running controller drives per-frame effect decay.
- **Simulation:** authoritative `_beat()` tick logic — reused to verify
  generated levels.
- **Testing:** widget tests cover end-to-end solve, drag placement across the
  whole grid, moving pieces, and failure cases. `flutter analyze` clean.
- **CI/CD (proposed):** GitHub Actions for analyze + test on PRs; web deploy to
  GitHub Pages / Firebase Hosting; store builds for Android/iOS.

---

## 12. Roadmap

**Now → next**
- [ ] Persist progress + real unlock flow.
- [ ] Build worlds 6–10 (gaps, larger grids, pause/timing combos).
- [ ] Star goals & piece budgets.

**Mid**
- [ ] Procedural generation + solver verification pipeline.
- [ ] Daily puzzle.
- [ ] Settings (audio/haptics), hint system, colorblind palette.
- [ ] Proposed elements: bouncer, toggle wall, splitter, keys/doors.

**Later**
- [ ] Full 50 worlds.
- [ ] Cosmetic themes & dot skins.
- [ ] Level editor + sharing.
- [ ] Localization, store launch, marketing pass.

---

*This document reflects the game as currently implemented plus the agreed design
direction, and is a living reference — update it as mechanics and content evolve.*
