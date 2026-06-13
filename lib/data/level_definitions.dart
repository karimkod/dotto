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

  // 4 — two turns.
  4: LevelData(
    id: 4,
    size: 3,
    title: 'Two Turns',
    tip: 'Two arrows, two turns. Plan the whole path first.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 2),
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 5 — teach walls.
  5: LevelData(
    id: 5,
    size: 4,
    title: 'Around the Wall',
    tip: 'A wall blocks the way. Route the dot around it.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 3),
    walls: [Pos(3, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 6 — longer route, two walls.
  6: LevelData(
    id: 6,
    size: 5,
    title: 'The Long Way',
    tip: 'Both walls are in the way. Take the long way round.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(4, 2), Pos(0, 3)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 7 — teach forced arrows: a fixed arrow you can't move.
  7: LevelData(
    id: 7,
    size: 4,
    title: 'Pinned Arrow',
    tip: 'The dark arrow is fixed. Work with it to reach the goal.',
    start: StartSpec(3, 0, Direction.up),
    exit: Pos(3, 3),
    forcedArrows: [ForcedArrow(0, 0, Direction.right)],
    toolkit: [ToolkitEntry(ToolType.arrowDown, 1)],
  ),

  // 8 — the forced arrow is on the only path: the dot must ride it up, then
  // the player steers it left and down to the goal.
  8: LevelData(
    id: 8,
    size: 5,
    title: 'Detour',
    tip: 'The fixed arrow sends the dot up. Use it, then guide it down to the goal.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(2, 0),
    walls: [Pos(2, 2)],
    forcedArrows: [ForcedArrow(4, 4, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 9 — two walls force a zig-zag.
  9: LevelData(
    id: 9,
    size: 5,
    title: 'Zig Zag',
    tip: 'The top row is blocked. Weave between the walls.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(4, 2), Pos(0, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 10 — bigger board, the grand tour.
  10: LevelData(
    id: 10,
    size: 6,
    title: 'Grand Tour',
    tip: 'A big board and a long path. Take your time.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 5),
    walls: [Pos(5, 2), Pos(0, 4)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
