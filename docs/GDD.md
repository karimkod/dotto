# Dotto — Game Design Document

> A minimalist, tactile dot-routing puzzle game.
> Plan a path, place your pieces, press play, and watch the dot find its way home.

---

## 1. Overview

**Dotto** is a single-player logic puzzle. Each level presents a small square
grid with a **start** cell (where a dot begins, facing a fixed direction) and an
**exit** cell. The dot moves on its own, one cell per tick, in a straight line.
The player cannot move the dot directly — instead they **place a small kit of
elements** (arrows, pauses, teleporters) on empty cells to redirect, delay, and
reroute the dot around hazards until it reaches the exit.

It's a "set it up, then watch it run" puzzle: all the thinking happens during a
calm **planning** phase; pressing **Play** runs the simulation and reveals
whether the plan works.

- **Platform:** Flutter (web first; Android/iOS ready — Android minSdk 21, iOS 14)
- **Orientation:** portrait, phone-sized (max content width ~460px)
- **Session length:** seconds-to-minutes per level, pick-up-and-play
- **Tone:** warm, calm, satisfying — soft "boardgame" tactility

---

## 2. Core Loop

1. **Read the board** — note the start, its direction, the exit, and hazards.
2. **Plan** — figure out the route.
3. **Place pieces** — drag elements from the toolkit onto empty cells.
4. **Play** — press Play; the dot moves automatically.
5. **Resolve** — win (reach the exit) or fail (run off the edge, hit a wall,
   die on a hazard). On fail, retry with pieces intact or clear and rethink.
6. **Progress** — completing a level unlocks the next on the level path.

---

## 3. Movement Rules

The dot advances one cell every tick (~400ms). Each tick, in order:

1. Moving hazards advance (if any).
2. If the dot shares a cell with a moving destroyer → **die**.
3. If the dot is paused, decrement the pause counter and skip movement.
4. Compute the next cell in the current direction:
   - Off the grid edge → **fail** ("ran off the edge").
   - A wall → **fail** ("hit a wall").
5. Move into the next cell and record the trail.
   - **Gap** → die ("fell into a hole").
   - **Destroyer** → die.
   - **Arrow** → adopt the arrow's direction.
   - **Pause** → halt for 2 ticks.
   - **Teleporter** → jump to the paired teleporter.
6. If the current cell is the **exit** → **win**.

---

## 4. Cell Types & Elements

### Fixed board cells (level-defined)
| Cell | Color | Behavior |
|------|-------|----------|
| **Start** | Green `#81C784` | Dot's origin; has a fixed launch direction (shown by a pulsing hint arrow) |
| **Exit** | Gold `#FFD54F` | Goal — reaching it wins the level |
| **Wall** | Blue-gray `#78909C` | Solid; the dot fails if it would enter |
| **Destroyer** | Red `#EF5350` | Deadly static cell |
| **Moving Destroyer** | Red (patrolling) | Deadly hazard that moves along a line each tick |
| **Gap** | Dashed outline | Hole — the dot falls in and dies |

### Player-placed elements (the toolkit / "kit")
| Element | Color | Effect |
|---------|-------|--------|
| **Arrow** (Up/Down/Left/Right) | Blue `#1E88E5` | Redirects the dot to a new heading |
| **Pause** | Purple `#BA68C8` | Holds the dot in place for 2 ticks (timing puzzles) |
| **Teleporter** | Orange `#FF8A65` | Placed in pairs; entering one exits the other |

Each level provides a limited kit (e.g. "1× Up arrow"). The puzzle is solving
the route **within** that budget. Placing a piece consumes a kit slot; removing
it returns the slot.

---

## 5. Controls & Interaction

Designed to feel like handling physical pieces on a board.

- **Drag-and-drop (primary):** drag an element from the toolkit onto a cell.
  A translucent ghost (slightly larger than a cell, with a soft drop shadow)
  follows the finger; the hovered valid cell shows a breathing preview. On
  release, the ghost **magnet-snaps** into the cell and the piece pops in.
- **Move placed pieces:** drag an already-placed piece to another empty cell.
  Drop it off-grid to remove it (returns to the kit); drop on an occupied cell
  and it returns to its origin.
- **Tap (fallback):** tap a toolkit item to select it, tap a cell to place;
  tap a placed piece to remove it.
- **Play / Reset:** Play runs the simulation; Reset clears placed pieces.

All drag math is handled manually via pan gestures (no Flutter `DragTarget`),
so drops register reliably anywhere on the grid surface across platforms.

---

## 6. Art Direction

A warm, hand-drawn **"boardgame"** aesthetic — thick dark outlines, white fills,
rounded corners, no heavy drop shadows on structural elements.

**Palette**
- Background: warm cream `#FAF8F5` with a faint square grid pattern
- Cards / cells: white with thick dark `#2D2D2D` outlines
- Accent / dot: warm orange `#FFB347`
- Coral (play button / current level): `#FF6B6B`
- Locked: blue-gray `#78909C`
- Completed star: gold `#FFD54F`
- Text/ink: `#2D2D2D`

**Typography:** Poppins (bold italic wordmark), Nunito (body) via Google Fonts.

---

## 7. Game Feel ("Juice")

Feedback is deliberately tactile and readable (not rushed):

- **Dot:** glides between cells with `easeInOutCubic`, does an arrival squish
  (pop to ~1.15× and settle), and carries a soft continuously-pulsing glow.
- **Trail:** the last ~6 visited cells show warm, glowing dots that fade by
  recency.
- **Cell reactions:** entering a cell briefly lights it warm; hitting an arrow
  flashes that cell in the element's color.
- **Placement:** a weighty pop-in (`0 → 1.3 → 0.95 → 1.05 → 1.0`, ~600ms), a
  lingering cell flash (~500ms), a border thicken (3→5→3px), and a gentle
  ripple pulse on neighboring cells. Medium haptic on drop.
- **Start hint:** a small, semi-transparent orange arrow just outside the start
  cell with a gentle breathing scale pulse, plus a couple of faint lead dots —
  a hint, not a focal point.

---

## 8. Audio

Lightweight, file-free sound synthesized with the Web Audio API
(oscillators + noise buffers); a no-op stub on non-web platforms.

| Event | Sound |
|-------|-------|
| Place element | Deep, chunky "thock" (400Hz + 180Hz body, sharp attack) |
| Remove element | Soft filtered-noise whoosh |
| Dot moves | Very subtle tick |
| Dot hits arrow | Two-note ping (880→1200Hz) |
| Dot hits pause | Low hum (200Hz) |
| Dot teleports | Frequency sweep (400→1600Hz) "zzip" |
| Dot dies | Noise-burst "poof" |
| Dot reaches exit | Rising chime (C5→E5→G5) |
| Level complete | Major chord ding |
| Play button | Subtle click |

Audio unlocks on first user interaction (browser autoplay policy).

---

## 9. Levels & Progression

### Main menu — level path
A vertical, scrollable "winding climb" path (level 1 at the bottom, higher
levels above). Cards are centered on a thick dashed line:
- **Locked:** lock icon, grayed.
- **Unlocked (current):** coral outline + glow, slightly larger.
- **Completed:** number with a gold star badge.

Top bar: profile, crown hint-counter, settings (thick-bordered tiles). A fixed
bottom coral play button shows the current level + difficulty badge. Side
shortcuts: daily challenge (locked) and calendar. Smooth edge-fade and
auto-scroll to the current level.

### Tutorial levels (ported from the prototype)
1. **First Steps** — teach arrows. 4×4. Start (3,0)→right, exit (0,3). Kit: 1 Up
   arrow. *Solution: Up at (3,3).*
2. **Around the Wall** — teach walls. Route around a blocker with Up + Right.
3. **Danger Zone** — teach destroyers. Avoid the deadly cell.
4. **Perfect Timing** — teach pause. Time a patrolling destroyer.
5. **Through the Void** — teach teleporters. Cross a wall split via a warp pair.

Levels 6–20 are placeholders on the path (currently show a "coming soon" screen)
to be designed next. Difficulty ramps Easy → Medium → Hard.

---

## 10. Technical Architecture

Flutter app (`com.dotto/dotto`). Key structure:

```
lib/
  main.dart                  # app entry → MenuScreen
  theme/app_theme.dart       # palette, text styles
  models/
    level.dart               # menu Level model (status, difficulty)
    grid_cell.dart           # Direction, CellType, PlacedType, ToolType
    level_data.dart          # LevelData (grid, start, exit, hazards, toolkit)
    game_state.dart          # GameStatus, PlacedElement, DotState
  data/
    levels.dart              # 20 menu levels
    level_definitions.dart   # playable level specs
  screens/
    menu_screen.dart         # winding level path
    game_screen.dart         # the puzzle: planning, run loop, effects
  widgets/
    top_bar.dart, level_card.dart, play_button.dart
    game_grid.dart           # board CustomPainter + GridGeometry + DragGhost
    game_toolbar.dart        # selectable toolkit tiles
  audio/
    sfx.dart                 # facade (conditional import)
    sfx_web.dart             # Web Audio implementation
    sfx_stub.dart            # no-op (VM/tests)
```

- **State:** lightweight `StatefulWidget` (no external state lib yet).
- **Rendering:** the board is a single `CustomPainter` for cells/hazards/trail/
  glows/pieces; the dot and drag ghost are overlay widgets. A continuous
  controller drives per-frame effect decay.
- **Tests:** widget tests cover the end-to-end solve, drag placement across the
  whole grid, moving pieces, and failure cases.

---

## 11. Roadmap

- [ ] Design and build levels 6–20 (introduce moving destroyers, gaps, multi-kit
      puzzles).
- [ ] Persist progress (SharedPreferences) and unlock flow.
- [ ] Star ratings (e.g. solve with minimum pieces).
- [ ] Daily puzzle.
- [ ] Level editor / sharing.
- [ ] Settings (sound/haptics toggles), accessibility pass.
- [ ] App-store polish: icons, splash, store listing.

---

*This document reflects the game as currently implemented and is a living
reference — update it as mechanics and content evolve.*
