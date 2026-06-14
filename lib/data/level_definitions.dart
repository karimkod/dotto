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
  // at higher difficulty. Each is a fully-walled corridor so the only solution
  // uses every piece. -----

  // 11 — start top-right; a winding 6x6 corridor with two fixed arrows.
  11: LevelData(
    id: 11,
    size: 6,
    title: 'Crossroads',
    tip: 'Read the whole corridor, then place your turns.',
    start: StartSpec(0, 5, Direction.down),
    exit: Pos(5, 0),
    walls: [
      Pos(0, 0), Pos(0, 1), Pos(0, 2), Pos(0, 3), Pos(0, 4),
      Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 4), Pos(2, 5),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4),
    ],
    forcedArrows: [
      ForcedArrow(1, 5, Direction.left),
      ForcedArrow(3, 5, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 12 — a long 7x7 maze; three fixed arrows guide part of the path.
  12: LevelData(
    id: 12,
    size: 7,
    title: 'The Maze',
    tip: 'A long maze. The fixed arrows guide part of the way.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(6, 0),
    walls: [
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5),
      Pos(3, 1), Pos(3, 2), Pos(3, 3), Pos(3, 4), Pos(3, 5), Pos(3, 6),
      Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 3), Pos(5, 4), Pos(5, 5),
    ],
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

  // 13 — start bottom-right; three fixed arrows force the route, you fill gaps.
  13: LevelData(
    id: 13,
    size: 6,
    title: 'Guided Path',
    tip: 'The fixed arrows force the route — just fill the gaps.',
    start: StartSpec(5, 5, Direction.left),
    exit: Pos(0, 0),
    walls: [
      Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4), Pos(4, 5),
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 4),
      Pos(0, 1), Pos(0, 2), Pos(0, 3), Pos(0, 4), Pos(0, 5),
    ],
    forcedArrows: [
      ForcedArrow(5, 0, Direction.up),
      ForcedArrow(3, 5, Direction.up),
      ForcedArrow(1, 0, Direction.up),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 14 — tight 7x7 routing, walls everywhere and just enough pieces.
  14: LevelData(
    id: 14,
    size: 7,
    title: 'Tight Squeeze',
    tip: 'Walls everywhere and just enough pieces. No room for waste.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(6, 6),
    walls: [
      Pos(0, 1), Pos(0, 2), Pos(0, 3), Pos(0, 4), Pos(0, 5), Pos(0, 6),
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 4), Pos(2, 5),
      Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4), Pos(4, 5), Pos(4, 6),
      Pos(6, 0), Pos(6, 1), Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5),
    ],
    forcedArrows: [
      ForcedArrow(1, 6, Direction.down),
      ForcedArrow(5, 6, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 15 — the ultimate World 1 exam: an 8x8 maze, two fixed arrows, five of
  // yours.
  15: LevelData(
    id: 15,
    size: 8,
    title: 'Final Exam',
    tip: 'Everything you have learned. Read the maze and route the dot home.',
    start: StartSpec(0, 7, Direction.down),
    exit: Pos(7, 7),
    walls: [
      Pos(0, 0), Pos(0, 1), Pos(0, 2), Pos(0, 3), Pos(0, 4), Pos(0, 5), Pos(0, 6),
      Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 4), Pos(2, 5), Pos(2, 6), Pos(2, 7),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4), Pos(4, 5), Pos(4, 6),
      Pos(6, 1), Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5), Pos(6, 6), Pos(6, 7),
    ],
    forcedArrows: [
      ForcedArrow(1, 7, Direction.left),
      ForcedArrow(5, 7, Direction.left),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 3),
      ToolkitEntry(ToolType.arrowRight, 2),
    ],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
