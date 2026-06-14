import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Playable level definitions, keyed by level number — World 1 (levels 1–10).
/// Each teaches one idea, building from "press Play" to multi-turn routing
/// around walls and fixed (forced) arrows.
const Map<int, LevelData> levelDefinitions = {
  // 1 — no toolkit. The dot just walks straight to the exit on Play.
  1: LevelData(
    id: 1,
    size: 3,
    title: 'First Steps',
    tip: 'Press Play and watch the dot reach the goal.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(0, 2),
    toolkit: [],
  ),

  // 2 — teach arrows: one turn.
  2: LevelData(
    id: 2,
    size: 3,
    title: 'One Turn',
    tip: 'Place the Up arrow so the dot turns toward the goal.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 2),
    toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
  ),

  // 3 — a different heading.
  3: LevelData(
    id: 3,
    size: 3,
    title: 'New Heading',
    tip: 'The dot heads down. Use the Right arrow to steer it home.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(2, 2),
    toolkit: [ToolkitEntry(ToolType.arrowRight, 1)],
  ),

  // 4 — two turns, starting top-right heading down to the top-left exit.
  4: LevelData(
    id: 4,
    size: 3,
    title: 'Two Turns',
    tip: 'Two arrows, two turns. Plan the whole path first.',
    start: StartSpec(0, 2, Direction.down),
    exit: Pos(0, 0),
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 5 — teach walls. Start bottom-right heading left to the top-left exit.
  5: LevelData(
    id: 5,
    size: 4,
    title: 'Around the Wall',
    tip: 'A wall blocks the way. Route the dot around it.',
    start: StartSpec(3, 3, Direction.left),
    exit: Pos(0, 0),
    walls: [Pos(3, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 6 — longer route. Start top-left heading down to the bottom-right exit.
  6: LevelData(
    id: 6,
    size: 5,
    title: 'The Long Way',
    tip: 'Both walls are in the way. Take the long way round.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(4, 4),
    walls: [Pos(2, 0), Pos(3, 4)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 7 — teach forced arrows. Start right heading left; the fixed arrow turns
  // the dot down, then the player steers it to the left-edge exit.
  7: LevelData(
    id: 7,
    size: 4,
    title: 'Pinned Arrow',
    tip: 'The dark arrow is fixed. Work with it to reach the goal.',
    start: StartSpec(0, 3, Direction.left),
    exit: Pos(3, 0),
    forcedArrows: [ForcedArrow(0, 1, Direction.down)],
    toolkit: [ToolkitEntry(ToolType.arrowLeft, 1)],
  ),

  // 8 — the forced arrow is on the only path. Start bottom-right heading left;
  // ride the fixed Up arrow, then steer right and down to the goal.
  8: LevelData(
    id: 8,
    size: 5,
    title: 'Detour',
    tip: 'The fixed arrow sends the dot up. Use it, then guide it down to the goal.',
    start: StartSpec(4, 4, Direction.left),
    exit: Pos(2, 4),
    walls: [Pos(2, 2)],
    forcedArrows: [ForcedArrow(4, 0, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 9 — two walls force a zig-zag. Start top-right heading down.
  9: LevelData(
    id: 9,
    size: 5,
    title: 'Zig Zag',
    tip: 'The edges are blocked. Weave between the walls.',
    start: StartSpec(0, 4, Direction.down),
    exit: Pos(4, 0),
    walls: [Pos(2, 4), Pos(2, 0)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 10 — the grand tour. Start centre-left heading right to the far corner.
  10: LevelData(
    id: 10,
    size: 6,
    title: 'Grand Tour',
    tip: 'A big board and a long path. Take your time.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(5, 5),
    walls: [Pos(2, 4), Pos(5, 3)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // ----- World 1 exam levels (11–15): combine arrows + walls + forced arrows
  // at higher difficulty. Each has a distinct layout/shape. Solver-verified
  // tight (every piece required) with the forced arrows on the path. -----

  // 11 — a spiral that winds in toward a centre exit; two fixed arrows on the
  // outer ring, three turns are yours.
  11: LevelData(
    id: 11,
    size: 6,
    title: 'Crossroads',
    tip: 'The path spirals inward — guide it to the centre.',
    start: StartSpec(0, 5, Direction.down),
    exit: Pos(3, 2),
    walls: [
      Pos(0, 0), Pos(0, 1), Pos(0, 2), Pos(0, 3), Pos(0, 4),
      Pos(1, 4),
      Pos(2, 1), Pos(2, 2), Pos(2, 4),
      Pos(3, 1), Pos(3, 4),
      Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4),
    ],
    forcedArrows: [
      ForcedArrow(5, 5, Direction.left),
      ForcedArrow(5, 0, Direction.up),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 12 — a vertical snake (columns instead of rows); fixed arrows turn the
  // bottom corners, you handle the rest.
  12: LevelData(
    id: 12,
    size: 7,
    title: 'The Maze',
    tip: 'A tall maze — the fixed arrows turn the corners for you.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(0, 6),
    walls: [
      Pos(0, 1), Pos(1, 1), Pos(2, 1), Pos(3, 1), Pos(4, 1), Pos(5, 1),
      Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3), Pos(6, 3),
      Pos(0, 5), Pos(1, 5), Pos(2, 5), Pos(3, 5), Pos(4, 5), Pos(5, 5),
    ],
    forcedArrows: [
      ForcedArrow(6, 0, Direction.right),
      ForcedArrow(0, 2, Direction.right),
      ForcedArrow(6, 4, Direction.right),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 13 — a diagonal staircase from corner to corner; most steps are fixed,
  // you fill three gaps.
  13: LevelData(
    id: 13,
    size: 7,
    title: 'Guided Path',
    tip: 'A staircase across the board — fill the gaps in the steps.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(6, 6),
    walls: [
      Pos(0, 2), Pos(0, 3), Pos(0, 4), Pos(0, 5), Pos(0, 6),
      Pos(1, 0), Pos(1, 3), Pos(1, 4), Pos(1, 5), Pos(1, 6),
      Pos(2, 0), Pos(2, 1), Pos(2, 4), Pos(2, 5), Pos(2, 6),
      Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 5), Pos(3, 6),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 6),
      Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 3), Pos(5, 4),
      Pos(6, 0), Pos(6, 1), Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5),
    ],
    forcedArrows: [
      ForcedArrow(1, 1, Direction.right),
      ForcedArrow(1, 2, Direction.down),
      ForcedArrow(2, 3, Direction.down),
      ForcedArrow(3, 3, Direction.right),
      ForcedArrow(3, 4, Direction.down),
      ForcedArrow(4, 4, Direction.right),
      ForcedArrow(5, 5, Direction.right),
      ForcedArrow(5, 6, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 14 — OPEN board with a few obstacle islands. Three fixed arrows are the
  // only way DOWN the board, and your toolkit has no Down arrow — so you can
  // only steer left/right onto each fixed descent. Two walls stop the dot from
  // simply falling straight down to the exit, which pins the whole route.
  // Solution: Left(2,6), Right(4,0), Left(6,6).
  14: LevelData(
    id: 14,
    size: 7,
    title: 'Tight Squeeze',
    tip: 'You have no way down — ride the fixed arrows and steer between them.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(6, 0),
    walls: [Pos(3, 6), Pos(5, 0), Pos(3, 3), Pos(5, 4)],
    forcedArrows: [
      ForcedArrow(0, 6, Direction.down),
      ForcedArrow(2, 0, Direction.down),
      ForcedArrow(4, 6, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 15 — the ultimate exam: a wide-open 8x8 with just a few obstacle islands.
  // Four fixed arrows are the ONLY way to move sideways across the board; every
  // descent is yours. Your whole toolkit is five Down arrows, so each row must
  // be left by dropping at exactly the edge the next fixed arrow waits on — any
  // other drop falls off the board. The grid looks almost empty; the entire
  // puzzle is finding the one staircase of drops that lands on the exit.
  // Solution: Down(0,7), Down(1,0), Down(3,7), Down(4,0), Down(6,7).
  15: LevelData(
    id: 15,
    size: 8,
    title: 'Final Exam',
    tip: 'Five drops, a near-empty board. Only one staircase reaches the goal.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(7, 7),
    walls: [Pos(2, 3), Pos(2, 5), Pos(5, 2), Pos(5, 4), Pos(7, 3)],
    forcedArrows: [
      ForcedArrow(1, 7, Direction.left),
      ForcedArrow(3, 0, Direction.right),
      ForcedArrow(4, 7, Direction.left),
      ForcedArrow(6, 0, Direction.right),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 5),
    ],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
