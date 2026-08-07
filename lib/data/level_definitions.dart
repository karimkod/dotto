import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Playable level definitions, keyed by level number.
///
/// World 1 (levels 1–15): from "press Play" to multi-turn routing around walls
/// and fixed (forced) arrows.
///
/// World 2 (levels 16–20): Static Destroyers. Red cells kill the dot on contact,
/// so the toolkit's specific arrows must thread a safe route.
///
/// World 3 (levels 21–30): Shields & Explosions. The Shield aura lets the dot
/// survive one destroyer; the hit chain-explodes the walls adjacent to it,
/// turning destroyers-next-to-walls into doors.
///
/// Every level is solver-verified tight — `pathMinPieces == toolkitTotal`, so no
/// piece is ever wasted (see tool/check_levels.dart and the solver tests).
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

  // 6 — the dot starts in the MIDDLE of the board heading up, then loops all
  // the way around to the far corner. A wall blocks the short way down the right
  // side, so the long route round the outside is the only one. Three turns.
  // Solution: Left(0,2), Down(0,0), Right(4,0).
  6: LevelData(
    id: 6,
    size: 5,
    title: 'The Long Way',
    tip: 'The dot starts dead centre. Send it the long way round to the goal.',
    start: StartSpec(2, 2, Direction.up),
    exit: Pos(4, 4),
    walls: [Pos(2, 4), Pos(3, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
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

  // 9 — the dot starts in the MIDDLE heading down, then wraps around the right
  // and top edges to the opposite corner. A wall blocks the short hop up the
  // left side, forcing the long way around. Three turns.
  // Solution: Right(4,2), Up(4,4), Left(0,4).
  9: LevelData(
    id: 9,
    size: 5,
    title: 'Zig Zag',
    tip: 'Another centre start — weave it around the edge to the far corner.',
    start: StartSpec(2, 2, Direction.down),
    exit: Pos(0, 0),
    walls: [Pos(2, 0), Pos(1, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
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

  // 14 — the dot starts in the MIDDLE of the board and shoots straight up, then
  // cascades back down across the whole grid. Four fixed arrows turn it at the
  // edges; your three Down arrows drop it onto each new row. Radiating from the
  // centre, it looks nothing like the corner-start staircase of level 15.
  // Solution: Down(0,6), Down(2,0), Down(4,6).
  14: LevelData(
    id: 14,
    size: 7,
    title: 'Tight Squeeze',
    tip: 'The dot starts dead centre and shoots up. Drop it down each row.',
    start: StartSpec(3, 3, Direction.up),
    exit: Pos(6, 0),
    forcedArrows: [
      ForcedArrow(0, 3, Direction.right),
      ForcedArrow(2, 6, Direction.left),
      ForcedArrow(4, 0, Direction.right),
      ForcedArrow(6, 6, Direction.left),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 3),
    ],
  ),

  // 15 — the ultimate exam: a wide-open 8x8 that runs in VERTICAL columns, not
  // rows. The dot plunges straight down column 0; from then on the fixed arrows
  // flip it up and down the columns, and YOU shift it one column right each time
  // it reaches an edge. The whole toolkit is five Right arrows, so every column
  // must be left at exactly the corner the next fixed arrow waits on. A few
  // walls block the tempting straight slides. The grid stands on end compared to
  // level 14's horizontal cascade.
  // Solution: Right(7,0), Right(0,1), Right(7,3), Right(0,4), Right(7,6).
  15: LevelData(
    id: 15,
    size: 8,
    title: 'Final Exam',
    tip: 'This board runs in columns. Shift the dot right at each edge.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(7, 7),
    walls: [Pos(3, 2), Pos(5, 2), Pos(2, 5), Pos(4, 5), Pos(3, 7)],
    forcedArrows: [
      ForcedArrow(7, 1, Direction.up),
      ForcedArrow(0, 3, Direction.down),
      ForcedArrow(7, 4, Direction.up),
      ForcedArrow(0, 6, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 5),
    ],
  ),

  // ======================= WORLD 2 — STATIC DESTROYERS =======================
  // Levels 16–20. Red destroyer cells are lethal on contact. Five hand-picked,
  // distinct patterns (a 4x4 intro, a 5x5 centre-start spiral, a 6x6 minefield,
  // a 6x6 forced-arrow escape and a 7x7 forced staircase). All solver-verified
  // tight (every toolkit piece required).

  // 16 — First Danger: a destroyer sits in the straight path; turn up before it.
  16: LevelData(
    id: 16,
    size: 4,
    title: 'First Danger',
    tip: 'The red cell destroys the dot. Turn up before you reach it.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 1),
    destroyers: [Pos(3, 2)],
    toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
  ),

  // 17 — Crossfire: a centre start with destroyers on the approaches. Several
  // routes look open, but only the long way round survives.
  17: LevelData(
    id: 17,
    size: 5,
    title: 'Crossfire',
    tip: 'Many ways look open — destroyers block all but one. Take the long way.',
    start: StartSpec(2, 2, Direction.up),
    exit: Pos(4, 4),
    destroyers: [Pos(0, 4), Pos(1, 4), Pos(3, 2), Pos(1, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 18 — Minefield: an open board scattered with destroyers; thread the one
  // safe staircase up to the corner.
  18: LevelData(
    id: 18,
    size: 6,
    title: 'Minefield',
    tip: 'Thread the staircase between the destroyers to the top corner.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 5),
    destroyers: [
      Pos(5, 4),
      Pos(2, 1),
      Pos(2, 2),
      Pos(1, 3),
      Pos(4, 4),
      Pos(3, 4),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 19 — Into the Fire: the fixed arrow plunges the dot toward a destroyer.
  // Escape left across the board, then drop down to the corner.
  19: LevelData(
    id: 19,
    size: 6,
    title: 'Into the Fire',
    tip: 'The fixed arrow drops you toward danger. Escape left and find the exit.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(5, 0),
    destroyers: [
      Pos(3, 5),
      Pos(2, 2),
      Pos(1, 1),
      Pos(1, 3),
      Pos(1, 4),
    ],
    forcedArrows: [ForcedArrow(0, 5, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 20 — Long Detour: a big open 7x7. The fixed arrow starts the climb; you
  // build the rest of the staircase around the destroyers and a wall.
  20: LevelData(
    id: 20,
    size: 7,
    title: 'Long Detour',
    tip: 'The fixed arrow starts the climb. Build the staircase to the corner.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 6),
    walls: [Pos(5, 4)],
    destroyers: [Pos(2, 1), Pos(6, 3), Pos(2, 2), Pos(3, 5), Pos(4, 4)],
    forcedArrows: [ForcedArrow(6, 2, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // ======================= WORLD 3 — SHIELDS & EXPLOSIONS ====================
  // Levels 21–35. The Shield aura lets the dot survive one destroyer; the hit
  // also CHAIN-EXPLODES every wall orthogonally adjacent to that destroyer,
  // turning destroyers-next-to-walls into doors. All solver-verified tight.

  // ----- Learn shields (21–23) -----

  // 21 — Must Shield: the destroyer is dead ahead with no way around it.
  21: LevelData(
    id: 21,
    size: 5,
    title: 'Must Shield',
    tip: 'No way around — you must shield up and go straight through.',
    start: StartSpec(4, 2, Direction.up),
    exit: Pos(0, 2),
    destroyers: [Pos(2, 2)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // 22 — Trapdoor: the only way into the walled-off exit is past a mine. Shield
  // through it (which destroys it), ride the fixed arrow's drop, then climb back
  // up through the now-clear gap to the exit.
  22: LevelData(
    id: 22,
    size: 5,
    title: 'Trapdoor',
    tip: 'Shield through the mine to clear it, take the drop, then climb back up '
        'through the gap.',
    start: StartSpec(2, 1, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(0, 1), Pos(0, 2), Pos(1, 1), Pos(1, 2)],
    destroyers: [Pos(2, 3)],
    forcedArrows: [ForcedArrow(2, 4, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 23 — Shield Around: pick up the shield FIRST, then turn into the destroyer.
  23: LevelData(
    id: 23,
    size: 5,
    title: 'Shield Around',
    tip: 'Order matters: route through the shield first, then into the danger.',
    start: StartSpec(2, 4, Direction.left),
    exit: Pos(4, 4),
    walls: [Pos(2, 0), Pos(4, 1), Pos(2, 2)],
    destroyers: [Pos(3, 3)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // ----- Shield + path clearing (24–27) -----

  // 24 — Break Through: a shielded hit blasts the wall blocking the exit.
  24: LevelData(
    id: 24,
    size: 5,
    title: 'Break Through',
    tip: 'A shielded hit also destroys the walls beside the destroyer. Open it.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(0, 3), Pos(1, 3), Pos(1, 4)],
    destroyers: [Pos(0, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 25 — Choose Your Bomb: only the destroyer beside the right wall opens a way.
  25: LevelData(
    id: 25,
    size: 5,
    title: 'Choose Your Bomb',
    tip: 'One destroyer opens the path; the other is just a trap. Pick wisely.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(4, 3), Pos(1, 4)],
    destroyers: [Pos(4, 2), Pos(2, 4)],
    forcedArrows: [ForcedArrow(4, 4, Direction.up)],
    toolkit: [ToolkitEntry(ToolType.shield, 2)],
  ),

  // 26 — Two Doors Down: a wall spans the whole of row 3; the only way past it
  // is to shield through one of the two destroyer-doors, then again past the
  // second to reach the corner.
  26: LevelData(
    id: 26,
    size: 6,
    title: 'Two Doors Down',
    tip: 'A wall blocks the way across. Blast through the destroyer-doors.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(5, 5),
    walls: [
      Pos(3, 0),
      Pos(3, 1),
      Pos(3, 2),
      Pos(3, 3),
      Pos(3, 4),
      Pos(3, 5),
      Pos(5, 4),
      Pos(1, 2),
    ],
    destroyers: [Pos(2, 2), Pos(4, 4)],
    forcedArrows: [ForcedArrow(0, 2, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.shield, 2),
    ],
  ),

  // 27 — Demolition: blast through the stacked destroyer-doors between two wall
  // barriers to climb out to the exit.
  27: LevelData(
    id: 27,
    size: 6,
    title: 'Demolition',
    tip: 'Two barriers, two doors. Open both, then climb straight out.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 3),
    walls: [
      Pos(1, 0),
      Pos(1, 1),
      Pos(1, 2),
      Pos(1, 3),
      Pos(1, 4),
      Pos(1, 5),
      Pos(4, 4),
      Pos(4, 3),
      Pos(4, 2),
      Pos(4, 1),
      Pos(4, 5),
    ],
    destroyers: [Pos(3, 3), Pos(2, 3), Pos(5, 5), Pos(0, 4), Pos(0, 0)],
    forcedArrows: [ForcedArrow(5, 3, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 2),
    ],
  ),

  // ----- Challenge + finale (28–30) -----

  // 28 — Detour Blast: the exit is walled off; route to the door and breach it.
  28: LevelData(
    id: 28,
    size: 6,
    title: 'Detour Blast',
    tip: 'The exit is boxed in. Find the destroyer-door and blow it open.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(5, 5),
    walls: [
      Pos(4, 1),
      Pos(4, 2),
      Pos(4, 4),
      Pos(4, 5),
      Pos(2, 0),
      Pos(2, 1),
      Pos(2, 2),
      Pos(2, 3),
      Pos(2, 4),
    ],
    destroyers: [Pos(1, 3), Pos(4, 0)],
    forcedArrows: [
      ForcedArrow(3, 0, Direction.down),
      ForcedArrow(0, 5, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 29 — Switchback: two full-row barriers, each with a single destroyer-door
  // offset from the last, so the dot zig-zags down — shielding through each door
  // — while a fixed arrow drops it onto the second. The exit is tucked behind a
  // wall so the lower leg is forced. Loose mines at (5,1) and (1,5) punish a
  // wrong turn.
  29: LevelData(
    id: 29,
    size: 7,
    title: 'Switchback',
    tip: 'Zig-zag down, blasting a shield through each door.',
    start: StartSpec(0, 2, Direction.down),
    exit: Pos(6, 6),
    walls: [
      Pos(2, 0), Pos(2, 1), Pos(2, 3), Pos(2, 4), Pos(2, 5), Pos(2, 6),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 5), Pos(4, 6),
      Pos(6, 5),
    ],
    destroyers: [Pos(2, 2), Pos(4, 4), Pos(5, 1), Pos(1, 5)],
    forcedArrows: [ForcedArrow(3, 4, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 30 — Grand Demolition: the World 3 finale. A wide 8x8 with THREE full-row
  // barriers, each holding one destroyer-door, the doors staggered so the dot
  // must shield through all three and weave between them, finishing on a fixed
  // arrow that sweeps it to the corner. Loose mines at (3,1) and (5,6) punish
  // the tempting wrong turns.
  30: LevelData(
    id: 30,
    size: 8,
    title: 'Grand Demolition',
    tip: 'Three barriers, three doors. Blast a path all the way down.',
    start: StartSpec(0, 3, Direction.down),
    exit: Pos(7, 7),
    walls: [
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 4), Pos(2, 5), Pos(2, 6), Pos(2, 7),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4), Pos(4, 6), Pos(4, 7),
      Pos(6, 0), Pos(6, 1), Pos(6, 3), Pos(6, 4), Pos(6, 5), Pos(6, 6), Pos(6, 7),
    ],
    destroyers: [Pos(2, 3), Pos(4, 5), Pos(6, 2), Pos(3, 1), Pos(5, 6)],
    forcedArrows: [ForcedArrow(7, 2, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 3),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // ======================= WORLD 4 — MOVING DESTROYERS + PAUSE ===============
  // Levels 31–45. Moving destroyers patrol a row/column, advancing one cell per
  // beat and bouncing at their bounds; they kill on contact and a shield does
  // NOT stop one — they are pure timing hazards. The Pause block holds the dot
  // for 2 beats so it can let a patrol pass. All solver-verified tight via the
  // brute-force (mover-aware) simulator.

  // ----- Moving destroyers (31–35) -----

  // 31 — First Patrol: an open board; a patrol sweeps a row. Turn up at the
  // right moment to slip past it.
  31: LevelData(
    id: 31,
    size: 4,
    title: 'First Patrol',
    tip: 'The red mine moves! Route around its patrol.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 3),
    movers: [MovingDestroyer(1, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 32 — Sidestep: down→right→up around a central wall block, past a patrol.
  32: LevelData(
    id: 32,
    size: 5,
    title: 'Sidestep',
    tip: 'Cross, climb and turn — slip past the patrol.',
    start: StartSpec(4, 4, Direction.left),
    exit: Pos(0, 4),
    movers: [MovingDestroyer(2, 2, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 33 — Double Patrol: two patrols (rows 2 & 4) cross the climb. Time both.
  33: LevelData(
    id: 33,
    size: 6,
    title: 'Double Patrol',
    tip: 'Two patrols guard the climb. Thread between them.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4),
      Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 3), Pos(3, 4),
    ],
    movers: [
      MovingDestroyer(2, 0, horizontal: true, dir: 1),
      MovingDestroyer(4, 5, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 34 — Patrolled Gap: an open board crossed by four patrols; thread the climb.
  34: LevelData(
    id: 34,
    size: 6,
    title: 'Patrolled Gap',
    tip: 'A patrol guards the only way up. Pick your moment.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [Pos(0, 5)],
    movers: [
      MovingDestroyer(3, 4, horizontal: true, dir: 1),
      MovingDestroyer(2, 1, horizontal: true, dir: -1),
      MovingDestroyer(1, 0, horizontal: true, dir: 1),
      MovingDestroyer(4, 5, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // ----- Shield + patrol chain explosions (35–39) -----
  // A wall blocks the exit; a moving mine patrols beside it. Route the SHIELDED
  // dot into the mine — the shielded hit destroys it and chain-explodes the
  // adjacent wall, opening the path.

  // 35 — Breach: intro. Shield the dot, climb into the patrol; the blast clears
  // the wall capping the column so the dot rolls up to the exit.
  35: LevelData(
    id: 35,
    size: 5,
    title: 'Breach',
    tip: 'Shield up and ram the mine — the blast clears the wall.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 2),
    walls: [Pos(1, 2)],
    movers: [MovingDestroyer(2, 2, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 36 — Pick a Section: a stepped wall barrier; only breaching under the exit
  // opens the way. Choose which column to climb.
  36: LevelData(
    id: 36,
    size: 5,
    title: 'Pick a Section',
    tip: 'One breach opens the wall. Aim it under the exit.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 3),
    walls: [Pos(1, 2), Pos(1, 3), Pos(0, 2), Pos(1, 4), Pos(0, 4)],
    movers: [MovingDestroyer(2, 0, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 37 — Double Breach: two walls, two patrols, two shields. Blast through both
  // gates to reach the corner.
  37: LevelData(
    id: 37,
    size: 6,
    title: 'Double Breach',
    tip: 'Two gates, two shields. Breach the floor, then the climb.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 2),
    walls: [Pos(5, 4), Pos(2, 5), Pos(1, 2)],
    movers: [
      MovingDestroyer(2, 3, horizontal: false, dir: 1),
      MovingDestroyer(3, 2, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.shield, 2),
    ],
  ),

  // 38 — Decoys: still mines sit around as bait, but the shield must go to the
  // moving one that guards the wall. Spend it wisely.
  38: LevelData(
    id: 38,
    size: 6,
    title: 'Decoys',
    tip: 'Still mines are bait — save the shield for the patrol.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(3, 5),
    walls: [Pos(0, 1), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4)],
    destroyers: [Pos(3, 1), Pos(4, 5), Pos(5, 5)],
    forcedArrows: [ForcedArrow(0, 3, Direction.right)],
    movers: [MovingDestroyer(2, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 39 — Cave-In: the exam. Two shields breach a wall cluster; a fixed arrow
  // and a patrol guard the twisting run home.
  39: LevelData(
    id: 39,
    size: 7,
    title: 'Cave-In',
    tip: 'One breach, three walls. Then ride the arrow home.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(4, 0),
    walls: [
      Pos(5, 0), Pos(5, 1), Pos(4, 1), Pos(3, 1), Pos(0, 3), Pos(1, 3),
      Pos(2, 3), Pos(3, 3), Pos(4, 5), Pos(5, 5), Pos(4, 6), Pos(3, 2),
    ],
    destroyers: [Pos(5, 6)],
    forcedArrows: [ForcedArrow(1, 0, Direction.down)],
    movers: [MovingDestroyer(0, 4, horizontal: false, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.shield, 2),
    ],
  ),

  // ----- Pure timing (40) -----

  // 40 — Timing Run: no walls at all. A vertical patrol sweeps column 3; weave
  // up-and-over (or down-and-under) it to reach the far side.
  40: LevelData(
    id: 40,
    size: 6,
    title: 'Timing Run',
    tip: 'No walls — just weave around the sweeping patrol.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 5),
    movers: [MovingDestroyer(5, 3, horizontal: false, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // ----- Timing puzzles (41–46): reason about WHEN the dot reaches each cell.

  // 41 — First Pause: the patrol sweeps the only cell the dot must pass through.
  // Pause once to let it clear, then roll on. The mechanic in isolation.
  41: LevelData(
    id: 41,
    size: 5,
    title: 'First Pause',
    tip: 'The patrol sweeps your path. Pause once and let it clear.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 4),
    movers: [MovingDestroyer(4, 2, horizontal: false, dir: -1)],
    toolkit: [ToolkitEntry(ToolType.pause, 1)],
  ),

  // 42 — Two Lanes: turn up the last column, but a patrol crosses the climb.
  // Time the turn with a pause so you slip past it.
  42: LevelData(
    id: 42,
    size: 5,
    title: 'Two Lanes',
    tip: 'Turn up — but the climb is patrolled. Pause to time it.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 3),
    movers: [MovingDestroyer(1, 0, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 43 — Pause Chain: a patrol on the floor AND one on the climb. WHERE you
  // spend each pause matters — mistime the first and the second one catches you.
  43: LevelData(
    id: 43,
    size: 6,
    title: 'Pause Chain',
    tip: 'Two patrols, two waits — and where you pause decides both.',
    start: StartSpec(1, 1, Direction.right),
    exit: Pos(1, 0),
    walls: [Pos(0, 1), Pos(2, 1), Pos(3, 1), Pos(4, 1)],
    forcedArrows: [ForcedArrow(1, 5, Direction.down)],
    movers: [
      MovingDestroyer(2, 4, horizontal: true, dir: -1),
      MovingDestroyer(2, 2, horizontal: false, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 44 — Shield or Wait?: two patrols guard a wall capping the exit. Shield
  // through one to breach the wall, and time the run with pauses.
  44: LevelData(
    id: 44,
    size: 6,
    title: 'Shield or Wait?',
    tip: 'Shield through the patrol to breach the wall — and pause for the rest.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5)],
    movers: [
      MovingDestroyer(2, 0, horizontal: true, dir: 1),
      MovingDestroyer(4, 1, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 45 — Tick Counter: the exit at (1,5) is walled in on all four sides. The
  // only door is the wall at (1,4), which a shielded hit on the destroyer at
  // (1,3) chain-explodes open. The second shield carries the dot through the
  // destroyer at (1,1) so the forced arrow at (1,0) can run it along row 1 and
  // out. NOTE: 9 toolkit pieces over 34 cells is ~2.4e12 placements, far past
  // the brute-force budget, so this level is not solver-verified (see the
  // unverifiable list in levels_solvable_test.dart).
  45: LevelData(
    id: 45,
    size: 7,
    title: 'Tick Counter',
    tip: 'The exit is sealed. Two shields open the way in — and pause for the '
        'patrol.',
    start: StartSpec(6, 6, Direction.left),
    exit: Pos(1, 5),
    walls: [
      Pos(0, 4), Pos(0, 5), Pos(0, 6), Pos(1, 6), Pos(2, 6),
      Pos(2, 5), Pos(2, 4), Pos(1, 4), Pos(1, 2), Pos(2, 3),
    ],
    destroyers: [Pos(1, 1), Pos(1, 3)],
    forcedArrows: [ForcedArrow(1, 0, Direction.right)],
    movers: [MovingDestroyer(5, 5, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 46 — Grand Timing: five patrols sweep five separate rows, with staggered
  // wall stubs breaking the climb into sections.
  46: LevelData(
    id: 46,
    size: 7,
    title: 'Grand Timing',
    tip: 'Five patrols, five rows. Two shields and two pauses — time every '
        'crossing.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 6),
    walls: [
      Pos(5, 5), Pos(5, 6), Pos(4, 3), Pos(4, 4), Pos(3, 2),
      Pos(3, 1), Pos(2, 3), Pos(2, 4), Pos(1, 5), Pos(1, 6),
    ],
    destroyers: [Pos(3, 0)],
    movers: [
      MovingDestroyer(5, 1, horizontal: true, dir: -1),
      MovingDestroyer(4, 1, horizontal: true, dir: -1),
      MovingDestroyer(2, 1, horizontal: true, dir: -1),
      MovingDestroyer(1, 1, horizontal: true, dir: -1),
      MovingDestroyer(0, 1, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // ----- Final exams (47–50): every mechanic at once. -----

  // 47 — Breach & Wait: the exit at (2,3) is boxed in on all four sides, and
  // there are no static mines — the only demolition charges are the two patrols
  // themselves. The column-5 patrol is fenced below row 4 by the wall at (4,5),
  // so the first shielded hit has to open that wall before the second patrol can
  // even climb to where its own blast opens the exit.
  47: LevelData(
    id: 47,
    size: 8,
    title: 'Breach & Wait',
    tip: 'No mines here — the patrols are your charges. Two shields, two '
        'breaches.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(2, 3),
    walls: [
      Pos(1, 2), Pos(1, 4), Pos(2, 4), Pos(2, 2), Pos(4, 5), Pos(4, 6),
      Pos(3, 2), Pos(3, 3), Pos(3, 4), Pos(1, 3), Pos(4, 1), Pos(4, 0),
      Pos(0, 0), Pos(0, 1),
    ],
    movers: [
      MovingDestroyer(5, 1, horizontal: true, dir: -1),
      MovingDestroyer(6, 5, horizontal: false, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 48 — The Gauntlet: every mechanic at once, and the biggest toolkit in the
  // game (10 pieces). Two mines sit in the floor run and one more guards the way
  // home along row 0, so all three shields are spent just getting past them. The
  // wall stripe across row 6 pushes the climb to the right edge, where three
  // patrolled rows and then two patrolled columns have to be waited out — one
  // pause each, five in all.
  //
  // Note the two floor mines sit under the stripe: blasting them also demolishes
  // (6,2) and (6,4), opening extra climbs. That is why this has ~2000 solutions
  // rather than a handful, even though it is tight.
  48: LevelData(
    id: 48,
    size: 8,
    title: 'The Gauntlet',
    tip: 'Three mines to blast through, five patrols to wait out. Nothing to '
        'spare.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(6, 1), Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5), Pos(6, 6),
      Pos(4, 1), Pos(4, 2), Pos(2, 1), Pos(2, 2), Pos(2, 6), Pos(4, 6),
    ],
    destroyers: [Pos(7, 4), Pos(7, 2), Pos(0, 2)],
    movers: [
      MovingDestroyer(5, 2, horizontal: true, dir: -1), // climb crosser
      MovingDestroyer(3, 6, horizontal: true, dir: -1), // climb crosser
      MovingDestroyer(1, 4, horizontal: true, dir: 1), // climb crosser
      MovingDestroyer(4, 3, horizontal: false, dir: 1), // row-0 crosser
      MovingDestroyer(2, 5, horizontal: false, dir: -1), // row-0 crosser
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.shield, 3),
      ToolkitEntry(ToolType.pause, 5),
    ],
  ),

  // 49 — Double Down: two full wall barriers (rows 2 and 4) pen the dot into a
  // corridor along row 3, with the forced arrow at (3,6) sending it down and
  // away from the exit. Only one shield, but the patrol sharing the corridor
  // sits between both barriers — so a single shielded hit blasts through row 2
  // AND row 4 at once. Double down on one blast.
  49: LevelData(
    id: 49,
    size: 7,
    title: 'Double Down',
    tip: 'Two walls, one shield. Catch the patrol between them and both come '
        'down.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 4), Pos(2, 5),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 4), Pos(4, 5),
    ],
    destroyers: [Pos(0, 3)],
    forcedArrows: [ForcedArrow(3, 6, Direction.down)],
    movers: [
      MovingDestroyer(5, 2, horizontal: true, dir: -1),
      MovingDestroyer(3, 3, horizontal: true, dir: 1), // shares the corridor
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 50 — The Summit: the finale, and the game's only 9x9. The dot starts SEALED
  // in a box — wall stripes across rows 2 and 6, a wall down column 2, the grid
  // edge on the right — with no static mines anywhere. The only way out is the
  // patrol sharing the box: a shielded hit on it blows the column-2 wall open.
  // Beyond that, three more patrols sweep rows 0-1, the whole run home.
  50: LevelData(
    id: 50,
    size: 9,
    title: 'The Summit',
    tip: 'Sealed in with one patrol — that is your key. Then run the top past '
        'three more.',
    start: StartSpec(3, 4, Direction.right),
    exit: Pos(0, 8),
    walls: [
      Pos(2, 2), Pos(2, 3), Pos(2, 4), Pos(2, 5), Pos(2, 6), Pos(2, 7),
      Pos(2, 8),
      Pos(3, 2), Pos(4, 2), Pos(5, 2),
      Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5), Pos(6, 6), Pos(6, 7),
      Pos(6, 8),
    ],
    movers: [
      MovingDestroyer(4, 5, horizontal: true, dir: 1), // shares the box
      MovingDestroyer(0, 2, horizontal: false, dir: 1), // top-run patrol
      MovingDestroyer(1, 4, horizontal: false, dir: -1), // top-run patrol
      MovingDestroyer(0, 6, horizontal: false, dir: 1), // top-run patrol
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // ----- World 5 (51–): teleporters. -----

  // 51 — Portal: the teleporter in isolation, and the player builds it. An
  // L-shaped wall (down column 2, then along row 3) seals the exit off from the
  // dot's side, so the only crossing is a portal pair the player places
  // themselves — one end reachable, one end past the wall.
  51: LevelData(
    id: 51,
    size: 5,
    title: 'Portal',
    tip: 'Two portals make one pair — enter either end, come out the other. '
        'Bridge the wall the dot can\'t walk around.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [
      Pos(0, 2), Pos(1, 2), Pos(2, 2), Pos(3, 2), Pos(3, 3), Pos(3, 4),
    ],
    toolkit: [
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 52 — Detour: the dot climbs column 5 straight into a mine, and a wall seals
  // off the rest of the board. The portal is the only way out — drop the
  // entrance below the mine, the exit in the open left region — then an arrow
  // runs the dot along the top to the exit, which is sealed from below so the
  // turn is required.
  52: LevelData(
    id: 52,
    size: 6,
    title: 'Detour',
    tip: 'The mine blocks the climb. Portal past it, then arrow along the top.',
    start: StartSpec(5, 5, Direction.up),
    exit: Pos(0, 0),
    walls: [
      Pos(0, 4), Pos(1, 4), Pos(2, 4), Pos(3, 4), Pos(4, 4), Pos(5, 4),
      Pos(1, 0),
    ],
    destroyers: [Pos(2, 5)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 53 — Two Ways: a wall seals the exit column, and a patrol sweeps it. One
  // portal pair crosses, one shield survives the patrol.
  53: LevelData(
    id: 53,
    size: 7,
    title: 'Two Ways',
    tip: 'A wall and a patrol guard the exit. Warp to the far side, shielded.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 6),
    walls: [
      Pos(0, 5), Pos(1, 5), Pos(2, 5), Pos(3, 5), Pos(4, 5), Pos(6, 5), Pos(5, 5),
    ],
    movers: [MovingDestroyer(4, 4, horizontal: false, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 54 — Portal Shield: a field of mines walls the exit off; a shielded hit
  // opens a way through. Portal in, shield up, and ride the fixed arrow home.
  54: LevelData(
    id: 54,
    size: 7,
    title: 'Portal Shield',
    tip: 'A minefield walls off the exit. Warp in, shield through, ride the '
        'fixed arrow home.',
    start: StartSpec(6, 6, Direction.left),
    exit: Pos(2, 6),
    walls: [Pos(3, 6), Pos(3, 5), Pos(1, 6), Pos(1, 5), Pos(2, 5)],
    destroyers: [
      Pos(2, 4), Pos(4, 5), Pos(0, 5), Pos(4, 6), Pos(0, 6),
      Pos(1, 4), Pos(0, 4), Pos(3, 4), Pos(4, 4),
    ],
    forcedArrows: [ForcedArrow(0, 2, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 55 — Portal Timing: three walled rows form a serpentine. Warp from the floor
  // up to the top corner, then snake down each row with a drop arrow, riding the
  // fixed arrow and picking up the fixed shield along the way. Solvable but heavy
  // to enumerate (~14 min, seven pieces over an open board), so it's verified by
  // its recorded solution rather than by the tightness sweep.
  55: LevelData(
    id: 55,
    size: 7,
    title: 'Portal Timing',
    tip: 'Warp up top, then serpentine down — one drop arrow per row.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(6, 4),
    walls: [
      Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 3), Pos(5, 4), Pos(5, 5),
      Pos(3, 1), Pos(3, 2), Pos(3, 5), Pos(3, 3), Pos(3, 4), Pos(3, 6),
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5),
    ],
    destroyers: [Pos(6, 3), Pos(5, 6)],
    forcedArrows: [ForcedArrow(6, 6, Direction.left)],
    forcedShields: [Pos(0, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 3),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 56 — Ricochet: a teleporter preserves the dot's heading, so the fixed arrows
  // by the exit only help if the dot arrives at them from below. Design by Fable.
  56: LevelData(
    id: 56,
    size: 7,
    title: 'Ricochet',
    tip: 'A portal keeps your heading. Line the dot up first, then step through.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(5, 4),
    walls: [
      Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3), Pos(6, 3),
      Pos(6, 2), Pos(6, 4), Pos(6, 5), Pos(6, 6),
    ],
    destroyers: [Pos(2, 1), Pos(2, 6)],
    forcedArrows: [
      ForcedArrow(1, 4, Direction.right),
      ForcedArrow(1, 5, Direction.down),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 57 — Chain Warp: a serpentine of mines and walls. Warp out of the start
  // pocket, climb the shaft, then warp again into the vault, which only opens
  // from the right. Design by Fable. Two-pair, so the shipped solvers cannot
  // enumerate it — verified TIGHT by tool/verify_pairs.dart.
  57: LevelData(
    id: 57,
    size: 8,
    title: 'Chain Warp',
    tip: 'Warp out, climb the shaft, then warp again — the vault only opens from '
        'the right.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(0, 4), Pos(0, 5), Pos(0, 6), Pos(0, 7), Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5), Pos(1, 6), Pos(1, 7), Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 3), Pos(2, 5), Pos(2, 6), Pos(2, 7), Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 5), Pos(3, 6), Pos(3, 7), Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 3), Pos(4, 5), Pos(4, 6), Pos(4, 7), Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 6), Pos(5, 7), Pos(6, 2), Pos(6, 3), Pos(6, 4), Pos(6, 5), Pos(6, 6), Pos(6, 7), Pos(7, 3), Pos(7, 4), Pos(7, 5), Pos(7, 6), Pos(7, 7),
    ],
    destroyers: [Pos(0, 3), Pos(2, 4), Pos(5, 5), Pos(6, 0), Pos(6, 1), Pos(7, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.teleporter, 4),
    ],
  ),

  // 58 — Portal Breach: warp past the barrier, grab the shield, and time the drop
  // so the patrol takes the shielded hit. Single pair — solver-verified TIGHT.
  58: LevelData(
    id: 58,
    size: 8,
    title: 'Portal Breach',
    tip: 'Warp across, grab the shield, and drop through the patrol\'s lane — '
        'the shield eats the hit.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(6, 6),
    walls: [
      Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(3, 4), Pos(5, 6), Pos(5, 7), Pos(5, 5), Pos(4, 4), Pos(5, 4), Pos(6, 5), Pos(7, 5), Pos(7, 6), Pos(7, 7), Pos(6, 7), Pos(0, 3),
    ],
    movers: [MovingDestroyer(4, 5, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 59 — The Labyrinth: no arrows in hand, just three portal pairs and two fixed
  // arrows on the board — bridge the maze in three hops. Three-pair, so the
  // shipped solvers can't pair it — verified TIGHT by tool/verify_pairs.dart.
  59: LevelData(
    id: 59,
    size: 8,
    title: 'The Labyrinth',
    tip: 'No arrows — only portals. Chain three jumps through the walls; each '
        'keeps your heading, the fixed arrows do the turning.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(4, 0), Pos(4, 2), Pos(4, 1), Pos(4, 3), Pos(5, 3), Pos(6, 3), Pos(7, 3), Pos(7, 4), Pos(6, 4), Pos(5, 4), Pos(4, 4), Pos(4, 5), Pos(4, 6), Pos(4, 7), Pos(3, 3), Pos(3, 2), Pos(3, 1), Pos(3, 0), Pos(3, 4), Pos(3, 5), Pos(3, 6), Pos(3, 7), Pos(2, 4), Pos(1, 4), Pos(0, 4), Pos(2, 3), Pos(1, 3), Pos(0, 3),
    ],
    destroyers: [Pos(1, 0)],
    forcedArrows: [
      ForcedArrow(6, 6, Direction.left),
      ForcedArrow(2, 7, Direction.up),
    ],
    toolkit: [
      ToolkitEntry(ToolType.teleporter, 6),
    ],
  ),

  // 60 — The Core: the final exam. A concentric fortress — the exit dead-centre
  // behind an inner wall ring, an outer ring around that, a one-cell moat
  // between them, and an L-shaped track along the south and east edges. The dot
  // starts sealed in a two-cell pocket, so the very first placement is forced:
  // warp out. Design by Fable.
  //
  // The intended run: pair 1 drops the dot onto the south track at (8,3), one
  // cell ahead of the track patrol, which chases it the whole way — the placed
  // shield at (8,4) blasts the mine-door at (8,5), the chain explosion opens
  // the wall at (8,6), and the patrol follows the dot straight through the
  // breach. Grab the pinned shield at (8,7), turn up at (8,8) as the patrol
  // slams into the corner behind, climb the east edge and take pair 2 from
  // (6,8) into the moat at (4,6). Ride the pinned pause at (3,6), turn left at
  // (2,6) into the inner patrol's lane, pause at (2,5) while the patrol walks
  // back — then step into it at (2,4). The shielded hit destroys it and blasts
  // open (3,4): the way in.
  //
  // Everything else is a trap: the mine-gate at (7,4) right under the core, the
  // east mine at (4,8), warping into the moat with the wrong heading, and
  // ramming the track patrol (mines are not walls, so its blast opens nothing
  // useful). The pinned pauses at (2,2)/(2,3) seal the inner lane's west end,
  // closing the direct-warp shortcut into it.
  //
  // Two placeable pairs, so the shipped solvers cannot enumerate it — instead
  // exhaustively verified by tool/verify_pairs.dart: solvable, and the intended
  // run above wins under the real simulator. The toolkit hands out exactly the
  // nine pieces the run uses (one pause, not two), so every piece is load-bearing.
  60: LevelData(
    id: 60,
    size: 9,
    title: 'The Core',
    tip: 'Two rings guard the core. Warp out, outrun the moat patrol, blast '
        'the door, climb, warp in — and meet the last patrol dead-centre.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(4, 4),
    walls: [
      // North wall — seals the start pocket and the whole top edge.
      Pos(0, 2), Pos(0, 3), Pos(0, 4), Pos(0, 5), Pos(0, 6), Pos(0, 7),
      Pos(0, 8),
      // West wall.
      Pos(1, 0), Pos(2, 0), Pos(3, 0), Pos(4, 0), Pos(5, 0), Pos(6, 0),
      Pos(7, 0),
      // Outer ring.
      Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5), Pos(1, 6),
      Pos(1, 7),
      Pos(2, 1), Pos(3, 1), Pos(4, 1), Pos(5, 1), Pos(6, 1),
      Pos(2, 7), Pos(3, 7), Pos(4, 7), Pos(5, 7), Pos(6, 7),
      Pos(7, 1), Pos(7, 2), Pos(7, 3), Pos(7, 5), Pos(7, 6), Pos(7, 7),
      // Inner ring around the core.
      Pos(3, 3), Pos(3, 4), Pos(3, 5),
      Pos(4, 3), Pos(4, 5),
      Pos(5, 3), Pos(5, 4), Pos(5, 5),
      // The wall the door-blast opens.
      Pos(8, 6),
    ],
    destroyers: [Pos(8, 5), Pos(5, 6), Pos(7, 4), Pos(4, 8)],
    forcedShields: [Pos(8, 7)],
    forcedPauses: [Pos(3, 6), Pos(2, 3), Pos(2, 2)],
    movers: [
      MovingDestroyer(8, 1, horizontal: true, dir: 1), // track patrol
      MovingDestroyer(2, 4, horizontal: true, dir: 1), // inner-lane patrol
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.teleporter, 4),
    ],
  ),

  // ============== MASTER TRIALS (61–70) — no new pieces ======================
  // Ten levels built entirely from rules the game has already taught, each one
  // starring a consequence of those rules no earlier level ever featured: the
  // start cell's permanent redirect, two-way portal travel, warp distance as a
  // timing tool, pinned pieces as machinery, blast-extended patrol lanes,
  // teleport-arrival collisions, crossing patrol clocks, and a patrol whose
  // rhythm changes mid-run. All solver-verified TIGHT (61–69 by the shipped
  // solvers, 70 by tool/verify_pairs.dart); 62, 64 and 70 are UNIQUE.

  // 61 — Boomerang: the start cell re-aims the dot on EVERY visit, so the
  // tempting return along the start's own row relaunches you away from the
  // exit one cell short of it. The real way is over the top — through the
  // patrol's row, pausing one cell beneath its lane while it sweeps past,
  // then trailing it to the corner. Solver-verified UNIQUE.
  61: LevelData(
    id: 61,
    size: 6,
    title: 'Boomerang',
    tip: 'The start re-aims the dot every time it crosses it — the way back '
        'is not the way in. Go over the top, and let the patrol pass first.',
    start: StartSpec(2, 1, Direction.right),
    exit: Pos(2, 0),
    walls: [Pos(1, 1), Pos(1, 3), Pos(3, 3), Pos(3, 0)],
    movers: [MovingDestroyer(0, 1, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 62 — Round Trip: one pair, used in BOTH directions. The sealed east chamber
  // loops the dot over a pinned shield and back onto the portal it arrived by,
  // spitting it out of the entrance heading up — then the mine by the exit
  // takes the aura. Solver-verified UNIQUE.
  62: LevelData(
    id: 62,
    size: 6,
    title: 'Round Trip',
    tip: 'A pair works both ways. Warp in, ride the ring, and step back '
        'through the same door — it faces a new direction now.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
      Pos(0, 4), Pos(0, 5), Pos(4, 4), Pos(4, 5), Pos(5, 4), Pos(5, 5),
      Pos(1, 0), Pos(1, 1),
    ],
    destroyers: [Pos(0, 1)],
    forcedArrows: [
      ForcedArrow(1, 5, Direction.down),
      ForcedArrow(3, 5, Direction.left),
      ForcedArrow(3, 4, Direction.up),
    ],
    forcedShields: [Pos(2, 5)],
    toolkit: [
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 63 — Warp Clock: a warp skips walking distance, and distance is time — so
  // WHERE the pair sits decides WHEN the dot lands in the second patrol's row.
  // Walking dies on the first patrol's column by construction; the mines pin
  // the landing cell; the climb gate forces the pause.
  63: LevelData(
    id: 63,
    size: 6,
    title: 'Warp Clock',
    tip: 'A warp skips distance — and distance is time. Place the pair to '
        'arrive between the sweeps, and pause once to fit the climb.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 5),
    walls: [
      Pos(0, 3), Pos(1, 3), Pos(3, 3), Pos(4, 3),
      Pos(2, 2), Pos(0, 4), Pos(1, 4), Pos(4, 1),
    ],
    destroyers: [Pos(5, 3), Pos(3, 4), Pos(4, 4)],
    movers: [
      MovingDestroyer(3, 2, horizontal: false, dir: 1),
      MovingDestroyer(2, 4, horizontal: true, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 64 — The Machine: a serpentine of wall stripes whose two full-row patrols
  // and two pinned pauses are already wired in; the player's six arrows finish
  // the circuit. Enter each patrol row mid-lane and it falls in behind you —
  // enter it anywhere else and the gears bite. Solver-verified UNIQUE.
  64: LevelData(
    id: 64,
    size: 7,
    title: 'The Machine',
    tip: 'Six arrows complete the machine. The pinned pauses set its rhythm — '
        'ride the gears, never fight them.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 5),
      Pos(3, 0), Pos(3, 1), Pos(3, 3), Pos(3, 4), Pos(3, 5), Pos(3, 6),
      Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 3), Pos(5, 4), Pos(5, 6),
    ],
    forcedPauses: [Pos(6, 3), Pos(5, 5)],
    movers: [
      MovingDestroyer(4, 2, horizontal: true, dir: -1),
      MovingDestroyer(2, 4, horizontal: true, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 3),
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 65 — Lane Breaker: the pen patrol is fenced in by a mine. Blast it and the
  // wall behind it, and the patrol's lane EXTENDS through the breach — into
  // the very chimney the dot must climb. The pinned pauses over the chimney
  // let climbers through but shove row-walkers into the dead end.
  65: LevelData(
    id: 65,
    size: 7,
    title: 'Lane Breaker',
    tip: 'Blast the fence and the patrol runs further than it used to. Break '
        'its lane, then thread the lane you broke.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [
      Pos(0, 3), Pos(0, 5),
      Pos(1, 0), Pos(1, 1), Pos(1, 5), Pos(1, 6),
      Pos(3, 4), Pos(3, 5),
    ],
    destroyers: [Pos(3, 3)],
    forcedPauses: [Pos(2, 4), Pos(1, 4)],
    movers: [MovingDestroyer(3, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 66 — Hot Landing: the exit pen is sealed on every side and the patrol
  // inside is the only demolition charge. A teleport arrival faces the landing
  // cell's hazards — so warp in ON TOP of the patrol, shielded, at the exact
  // beat it crosses the pen's centre, and the blast opens the roof.
  66: LevelData(
    id: 66,
    size: 7,
    title: 'Hot Landing',
    tip: 'The pen is sealed and the patrol inside is the only charge. Warp in '
        'right on top of it — shielded — as it crosses the middle.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(1, 4),
    walls: [
      Pos(1, 3), Pos(1, 5), Pos(0, 4),
      Pos(2, 3), Pos(2, 4), Pos(2, 5),
      Pos(4, 3), Pos(4, 4), Pos(4, 5),
      Pos(3, 6),
    ],
    destroyers: [Pos(3, 2)],
    movers: [MovingDestroyer(3, 4, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 67 — Crossfire Gate: a full-width patrol rides the middle corridor and a
  // short one ping-pongs in a three-cell pocket of column 4. The slits in the
  // two wall stripes are offset, so the route crosses the long patrol's lane
  // going up and the short one's going east — each on its own clock, each
  // needing its own pause at the right doorstep.
  67: LevelData(
    id: 67,
    size: 7,
    title: 'Crossfire Gate',
    tip: 'Two patrols, two crossings, two pauses. The doors are offset — time '
        'each one on its own clock.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(5, 0), Pos(5, 1), Pos(5, 3), Pos(5, 4), Pos(5, 5), Pos(5, 6),
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 4), Pos(1, 6),
    ],
    movers: [
      MovingDestroyer(3, 3, horizontal: true, dir: -1),
      MovingDestroyer(4, 4, horizontal: false, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 68 — Chain Reaction: the first shield blasts the mine fencing the pen, and
  // the patrol's lane extends through the breach — from period four to period
  // eight. The second shield kills that same patrol at its NEW far end, the
  // only blast that can open the exit chimney's door. Cross it at one rhythm,
  // kill it at another.
  68: LevelData(
    id: 68,
    size: 7,
    title: 'Chain Reaction',
    tip: 'The first shield frees the patrol; the second one spends it. Cross '
        'at period four — kill at period eight.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [
      Pos(0, 3), Pos(0, 5),
      Pos(1, 3), Pos(1, 5),
      Pos(2, 4),
      Pos(3, 4), Pos(3, 5),
    ],
    destroyers: [Pos(3, 3)],
    movers: [MovingDestroyer(3, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 69 — The Convoy: three patrols share the middle corridor and a fourth owns
  // the exit row. The only crossing is the aligned shaft at column 3, and the
  // convoy's stagger leaves exactly one gap — both kit pauses go on the
  // doorstep, in exactly one arrangement. Solver-verified UNIQUE.
  69: LevelData(
    id: 69,
    size: 7,
    title: 'The Convoy',
    tip: 'A convoy owns the corridor and one more guards the exit row. Stack '
        'your waits inside the shaft and take the only gap in the traffic.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 4), Pos(2, 5), Pos(2, 6),
      Pos(4, 0), Pos(4, 1), Pos(4, 2), Pos(4, 4), Pos(4, 5), Pos(4, 6),
    ],
    movers: [
      MovingDestroyer(3, 1, horizontal: true, dir: 1),
      MovingDestroyer(3, 5, horizontal: true, dir: 1),
      MovingDestroyer(0, 2, horizontal: true, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 70 — Full Circle: the Master Trials finale. The exit sits ONE CELL above
  // the start — and the start guards it: anything stepping onto the launch pad
  // is relaunched west, so the underbelly approach can never work. The circuit
  // runs the whole board: warp into the pinned ring for the first shield, ride
  // it back out of the same portal heading down, cut the south row past the
  // patrol, climb through the pen mine (spending the aura), collect the second
  // pinned shield, warp over the mined top row, and dive through the mine-door
  // into the core. Two pairs, chained, one of them used in both directions.
  // Not solver-verifiable by the shipped solvers (two placeable pairs) —
  // exhaustively verified by tool/verify_pairs.dart: TIGHT and UNIQUE.
  70: LevelData(
    id: 70,
    size: 8,
    title: 'Full Circle',
    tip: 'The exit was one cell above the start all along — and your own '
        'launch pad guards it. Chain both pairs and come full circle.',
    start: StartSpec(4, 4, Direction.left),
    exit: Pos(3, 4),
    walls: [
      Pos(3, 3), Pos(3, 5),
      Pos(1, 3), Pos(1, 5),
      Pos(2, 3), Pos(0, 5), Pos(2, 5),
      Pos(3, 6), Pos(3, 7), Pos(4, 5), Pos(4, 6), Pos(4, 7),
      Pos(1, 1), Pos(1, 2), Pos(3, 1), Pos(3, 2),
      Pos(2, 1), Pos(2, 2), Pos(4, 1), Pos(4, 2),
      Pos(5, 4), Pos(5, 5), Pos(5, 6), Pos(5, 7),
      Pos(6, 4), Pos(6, 5), Pos(6, 6), Pos(6, 7),
      Pos(7, 4), Pos(7, 5), Pos(7, 6), Pos(7, 7),
    ],
    destroyers: [Pos(0, 2), Pos(1, 4), Pos(2, 0)],
    forcedArrows: [
      ForcedArrow(2, 6, Direction.up),
      ForcedArrow(0, 6, Direction.right),
      ForcedArrow(0, 7, Direction.down),
      ForcedArrow(0, 4, Direction.down),
    ],
    forcedShields: [Pos(1, 6), Pos(1, 0)],
    forcedPauses: [Pos(2, 4)],
    movers: [MovingDestroyer(6, 0, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.teleporter, 4),
    ],
  ),

  // ============== WORLD 6 (71–) — ROTATING ARROWS ============================
  // The first mechanic with per-pass state: a pinned arrow that turns a quarter
  // turn clockwise every time the dot goes through it, so the same cell plays
  // differently on the second visit.

  // 71 — Rotor: the World 6 opener, and a pure teaching board. Nothing to dodge,
  // one arrow in the kit. The dot runs east into the rotor at (2,2), which points
  // UP on the first pass and throws it off the top of the board — the bare-board
  // loss the player is meant to see first. Bouncing it back down (the DOWN arrow
  // anywhere in column 2 above the rotor) buys a second pass, and by then the
  // rotor has turned up → right: straight into the exit. Solver-verified via the
  // exhaustive BruteSearch (rotating arrows route away from the path solver) —
  // solvable and TIGHT.
  71: LevelData(
    id: 71,
    size: 5,
    title: 'Rotor',
    tip: 'This arrow turns a quarter-turn each time you pass. Send the dot up, '
        'bounce it back — the second pass points the way out.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 4),
    rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
    toolkit: [ToolkitEntry(ToolType.arrowDown, 1)],
  ),

  // World 6 proper (72–91): twenty rotating-arrow levels, easy to brutal. Each
  // is built around a different consequence of the dial's one rule — it fires
  // its current heading, then advances a quarter-turn clockwise per pass.
  // Solver-verified TIGHT (the suite's BruteSearch for 72–90 bar 76, 77, 79 and
  // 80, and 91 — too heavy to enumerate there — by tool/verify_pairs.dart); 75,
  // 81 and 89 are UNIQUE. 76, 77, 79 and 80 carry kits far past what the
  // exhaustive search can enumerate — a rotating arrow rules out the path solver, and the
  // exhaustive one cannot prune — so they are verified by their recorded
  // solutions winning under the simulator, not by a sweep. See the note on
  // solverTooSlow in levels_solvable_test.dart.

  // 72 — Second Pass: build one loop and spin the dial to its third heading.
  72: LevelData(
    id: 72,
    size: 5,
    title: 'Second Pass',
    tip: 'The dial turns every time you pass. Loop it twice — the third '
        'heading points home.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(4, 2),
    walls: [Pos(3, 3), Pos(0, 2)],
    rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 73 — Four Winds: two vertical patrols bracket the dial, mines flank the
  // door, and the kit is a hold and one portal pair. The hold at (3,1) times the
  // column-2 crossing; the dial then drops the dot south onto a portal that puts
  // it back on the only safe approach. The mines at (2,5) and (4,5) are what
  // make the dial matter — they close the routes that used to reach the exit
  // down the east wall. Solver-verified TIGHT, 6 winning placements (the hold is
  // forced, the pair can slide up the middle column).
  73: LevelData(
    id: 73,
    size: 6,
    title: 'Four Winds',
    tip: 'Two columns on patrol, and mines either side of the door. Hold at the '
        'gate to time the crossing, then let the dial and a portal put you on '
        'the one safe line in.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(3, 5),
    destroyers: [Pos(2, 5), Pos(4, 5)],
    rotatingArrows: [RotatingArrow(3, 3, Direction.down)],
    movers: [
      MovingDestroyer(1, 2, horizontal: false, dir: 1),
      MovingDestroyer(4, 4, horizontal: false, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 74 — Meshed Gears: two dials facing each other across a mine. The shield
  // carries the dot east through the mine; the east dial turns it back west, the
  // west dial — turned by that first pass — drops it south, and the two arrows
  // loop it round to climb into the east dial's second pass and out. Every dial
  // face is used twice. Solver-verified TIGHT, 3 winning placements (the return
  // loop can run along any of the three southern rows).
  74: LevelData(
    id: 74,
    size: 6,
    title: 'Meshed Gears',
    tip: 'Armour up before the mine. The two gears hand you back and forth — '
        'and every pass turns them, until both point your way.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(1, 2), Pos(0, 3), Pos(0, 5)],
    destroyers: [Pos(2, 3)],
    rotatingArrows: [
      RotatingArrow(2, 4, Direction.left),
      RotatingArrow(2, 2, Direction.right),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 75 — Long Way Round: the short bounce reaches the exit ray unarmed — the
  // mine there only falls to the wide western circuit over the pinned shield,
  // home through the start's relaunch, and up into the dial's second pass.
  // The up arrow works double duty on both climbs. Solver-verified UNIQUE.
  75: LevelData(
    id: 75,
    size: 6,
    title: 'Long Way Round',
    tip: 'The quick bounce arrives unarmed. Take the long way — over the '
        'shield, home past your launch pad, and up through the dial again.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(3, 5),
    walls: [Pos(4, 5)],
    destroyers: [Pos(3, 4)],
    forcedShields: [Pos(2, 1)],
    rotatingArrows: [RotatingArrow(3, 3, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 76 — Figure Eight: the exit at (0,5) is walled in on three sides and mined
  // on the fourth, and the cell BELOW that mine is a wall too — so the only way
  // in is to open (2,5) first. That takes the lower mine at (3,5): ram it
  // shielded and the blast demolishes the wall above it. Two mines, two auras,
  // in that order — the pinned shield at (3,1) is the first, the kit's the
  // second.
  //
  // Three mines, two auras — so one mine has to be walked around rather than
  // rammed. The mine at (2,1) sits directly above the pinned shield, which makes
  // the obvious climb a trap: take (3,1) heading north and the aura you just
  // picked up is spent one cell later on a blast that opens nothing, leaving the
  // stem mine unarmed. The pinned aura has to be crossed SIDEWAYS.
  //
  // The kit is six pieces with a single up arrow, and that arrow is needed for
  // the final climb — so the portal pair is the only lift onto row 3. It lands
  // the dot at (3,0) still heading east, which is exactly the sideways crossing
  // the pinned aura needs, and keeps the run clear of (2,1) altogether.
  //
  // Then the figure: the dial's first face fires the dot east into the lower
  // mine, whose blast opens the stem; the far arrow turns it back west along
  // row 3 and into the dial's SECOND face, which drops it down the middle column
  // to the floor; the floor run east collects the second aura and the last arrow
  // climbs the stem, spending that aura on the mine in the doorway. The dial is
  // used twice, the path crosses itself, and every one of the six pieces is
  // load-bearing.
  76: LevelData(
    id: 76,
    size: 7,
    title: 'Figure Eight',
    tip: 'Two auras, three mines — one has to be dodged, not rammed. Your only '
        'lift is the portal; save the climb for the stem you blow open.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 5),
    walls: [
      Pos(0, 4), Pos(0, 6), Pos(1, 4), Pos(1, 6),
      Pos(2, 4), Pos(2, 5), Pos(2, 6),
    ],
    destroyers: [Pos(1, 5), Pos(2, 1), Pos(3, 5)],
    rotatingArrows: [RotatingArrow(3, 2, Direction.right)],
    forcedShields: [Pos(3, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 77 — Demolition Dial: the exit pocket at (1,0)–(1,1) is sealed — every
  // neighbour is a wall, so no route reaches it as the board stands. The mine at
  // (1,3) is the key: ram it shielded and the blast takes out the walls either
  // side of it, (1,2) and (1,4), opening row 1 all the way to the door. The dot
  // has to hit the mine from above or below (both its row-1 neighbours are still
  // walls at that point), then come back round and run row 1 west through the
  // hole it made. A patrol sweeps row 3, and with no pause in the kit the dial's
  // bounce is the only clock.
  77: LevelData(
    id: 77,
    size: 7,
    title: 'Demolition Dial',
    tip: 'The door is bricked in. The mine beside it is the demolition charge — '
        'ram it shielded, then come back round and run the row you opened.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(1, 0),
    walls: [
      Pos(0, 0), Pos(0, 1), Pos(1, 2), Pos(1, 4), Pos(2, 0), Pos(2, 1),
    ],
    destroyers: [Pos(1, 3)],
    rotatingArrows: [RotatingArrow(4, 3, Direction.down)],
    movers: [MovingDestroyer(3, 2, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 78 — Gear Train: row 1 is a wall with one gap, at (1,3), so every route to
  // the exit climbs column 3 through it and takes the fixed arrow at (0,3) home
  // along the top. The dial sits in that column at (5,3) and its fourth face is
  // the only one pointing north — so the intended run feeds it all four in
  // order, the portal pair returning the dot to it each time: east into the
  // portal, back for the down face, up again for the left face, into the portal
  // the other way, and on the fourth pass it finally points at the gap.
  // Solver-verified TIGHT, and cheap enough that the shipped BruteSearch does it
  // outright — 2.74e4 placements, 143 solutions.
  78: LevelData(
    id: 78,
    size: 7,
    title: 'Gear Train',
    tip: 'One gap in the wall, and the dial guards the column below it. Feed '
        'the dial until it points north — then it opens the way itself.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 0),
    walls: [
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 4), Pos(1, 5), Pos(1, 6),
    ],
    forcedArrows: [ForcedArrow(0, 3, Direction.left)],
    rotatingArrows: [RotatingArrow(5, 3, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 79 — Ratchet: the exit at (3,6) is a sealed pocket — walls on all three
  // sides — and so is the mine at (3,4) that would open it, boxed in by walls on
  // all four. The way in is a chain: ram the UPPER mine at (1,4) shielded and
  // its blast takes out (2,4), which is the only cell that touches the lower
  // mine's box. Come back down through that hole with the second aura, ram
  // (3,4), and its blast opens (3,3), (3,5) and (4,4) at once — turning row 3
  // into a corridor running straight to the door. The second portal pair then
  // does double duty: crossed southbound off the second blast, and again
  // eastbound to enter that corridor.
  //
  // Tight — every one of the ten pieces lies on the winning path — but the DIAL
  // is not load-bearing. In all 18 winning placements found, the dot reaches
  // (3,1) already heading north and the dial's first face points north too, so
  // it passes straight through and never redirects anything. It is scenery here,
  // not a mechanism. Turning its initial heading, or moving it off the column-1
  // climb, would make it earn its place.
  79: LevelData(
    id: 79,
    size: 7,
    title: 'Ratchet',
    tip: 'The door is bricked in, and so is the charge that opens it. Blow the '
        'upper mine to reach the lower one — that blast opens the whole row.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(3, 6),
    walls: [
      Pos(2, 3), Pos(2, 4), Pos(2, 5), Pos(2, 6),
      Pos(3, 3), Pos(3, 5),
      Pos(4, 3), Pos(4, 4), Pos(4, 5), Pos(4, 6),
    ],
    destroyers: [Pos(1, 4), Pos(3, 4)],
    rotatingArrows: [RotatingArrow(3, 1, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.teleporter, 4),
    ],
  ),

  // 80 — Tumblers: four dials in a square, every one of them pointing east, and
  // an exit walled off at (0,5) and (1,5) so the only way in is from (1,6)
  // heading north. Nothing in the kit points up — the single north-facing thing
  // on the board is the pinned arrow at (5,3), and the only other way to face
  // north is a dial that has been clicked round to its fourth face. So the run
  // is a lock: drop into the square, feed each tumbler until it clicks past
  // east, and use the pinned arrow at the bottom as the kicker that starts the
  // second half. The last dial to come round to north is the one that lifts the
  // dot into the portal home.
  //
  // The wall runs two cells deep at (0,4)/(1,4) and (0,5)/(1,5) so the top-right
  // corner cannot be cut: reaching the door means coming up column 6 from below,
  // and the only lift is a portal entered while already heading north. Two more
  // blocks, at (0,2) and (3,4), close the routes that skipped half the machine —
  // (0,2) stops the top run reaching column 3 before the dot has been down into
  // the square, and (3,4) severs the lane that let the upper dials hand straight
  // back to the exit column.
  //
  // Solver-verified via restricted search: exactly 5 wins, and every one of them
  // uses all seven pieces AND crosses all four dials. No slack placement and no
  // two-dial shortcut survives — the lock has to be worked in full.
  //
  // Those two cells were found by sweeping all 703 pairs of floor cells against
  // the 606 wins of the unplugged board: (0,2)+(3,4) is the ONLY pair that
  // leaves nothing but tight four-dial solutions. Every single-wall option
  // failed — the ones that forced tightness ((4,2), (4,4)) killed every
  // four-dial route, and the ones that spared the four-dial routes pruned almost
  // nothing.
  80: LevelData(
    id: 80,
    size: 7,
    title: 'Tumblers',
    tip: 'Four tumblers, all facing east, and nothing in your kit points north. '
        'Every one of them has to click before the door will.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(0, 6),
    walls: [
      Pos(0, 2), Pos(0, 4), Pos(0, 5), Pos(1, 4), Pos(1, 5), Pos(3, 4),
    ],
    forcedArrows: [ForcedArrow(5, 3, Direction.up)],
    rotatingArrows: [
      RotatingArrow(2, 1, Direction.right),
      RotatingArrow(2, 3, Direction.right),
      RotatingArrow(4, 1, Direction.right),
      RotatingArrow(4, 3, Direction.right),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 2),
      ToolkitEntry(ToolType.teleporter, 4),
    ],
  ),

  // 81 — Roundabout: four dials set as a ring in the north-east, each pointing
  // at the next one round, so a dot fed into the ring is carried corner to
  // corner — and every lap advances all four, so the ring hands it back out on a
  // different face each time. A patrol runs column 2, which is the lane the exit
  // sits under, so the kit's pause is the clock for the last crossing.
  81: LevelData(
    id: 81,
    size: 7,
    title: 'Roundabout',
    tip: 'The ring passes you corner to corner, and every lap turns it. Ride it '
        'until it spits you at the floor, and time the last lane.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(6, 2),
    rotatingArrows: [
      RotatingArrow(0, 3, Direction.right),
      RotatingArrow(0, 5, Direction.down),
      RotatingArrow(2, 3, Direction.up),
      RotatingArrow(2, 5, Direction.left),
    ],
    movers: [MovingDestroyer(2, 2, horizontal: false, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 82 — Odometer: an 8x8 cut in two by a wall spine, with a pinned aura at
  // (1,1) inside the west tower and a patrol sweeping row 2. The exit at (0,7)
  // is boxed by (0,6) and (1,7) and the level has no mines, so the only way to
  // open it is to spend the aura on the patrol — the blast takes out the walls
  // beside wherever it dies, and killing it against the east edge demolishes
  // (1,7) to make column 7 the way in.
  //
  // The tower looks sealed: the spine at row 3 and the walls at (1,3)/(2,3)
  // leave it no ground-level mouth, and the kit holds no down arrow, so nothing
  // can descend into it from row 0. The portal pair is the answer — one end
  // dropped INSIDE it at (1,0) lands the dot straight on row 1 beside the aura
  // with no descent at all, and the same pair carries it back out.
  //
  // Solver-verified via restricted search (a portal end in the tower, the other
  // in the east field, arrows swept over 16 cells — 6.2M placements): 4 wins,
  // every one using all seven pieces. They differ only in how far along row 4
  // the return arrow sits and which cell catches it.
  82: LevelData(
    id: 82,
    size: 8,
    title: 'Odometer',
    tip: 'The tower has no door — but a portal does not need one. Fetch the '
        'aura, then spend it on the patrol to blow the last wall open.',
    start: StartSpec(7, 0, Direction.right),
    exit: Pos(0, 7),
    walls: [
      Pos(0, 6), Pos(1, 3), Pos(1, 6), Pos(1, 7),
      Pos(2, 3), Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 3),
    ],
    forcedShields: [Pos(1, 1)],
    rotatingArrows: [RotatingArrow(4, 4, Direction.right)],
    movers: [MovingDestroyer(2, 5, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 83 — Spin Doctor: the delay dial re-aims the shielded dot at the pen once
  // per cycle — pick the cycle the patrol is home, and the kill at the pen's
  // centre blasts open the exit door above it.
  83: LevelData(
    id: 83,
    size: 7,
    title: 'Spin Doctor',
    tip: 'The machine re-aims you at the pen every cycle. Choose the cycle '
        'the patrol is home.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 3),
    walls: [Pos(2, 0), Pos(2, 6), Pos(1, 3), Pos(0, 2), Pos(0, 4)],
    rotatingArrows: [RotatingArrow(4, 2, Direction.up)],
    movers: [MovingDestroyer(2, 2, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 84 — Escapement: the exit at (1,7) is bricked in on all three sides and the
  // board carries no mines, so the ONLY way to open it is a shielded collision
  // with a patrol — the blast takes out the walls beside wherever the patrol
  // dies. That makes the two patrols the demolition charges, and the order is
  // forced:
  //
  //   1. Ram the row-4 patrol on (4,5) with the first aura. Its blast opens
  //      (3,5) — the one wall boxing the column-5 patrol into rows 4-7.
  //   2. That patrol can now climb. Meet it on (1,5) with the second aura; that
  //      blast opens (1,6), the only cell touching the door.
  //   3. A right arrow ON (1,5) does the rest: the simulator resolves the
  //      collision BEFORE the cell's piece, so the dot kills the climber, the
  //      wall goes, and only then does the arrow turn it east into the exit.
  //
  // The row-4 patrol starts at (4,0) so that it and the climber are never on
  // (4,5) on the same tick — otherwise one blast destroys both and step 2 has
  // nothing left to kill. The three pauses are the clock that lands the dot on
  // each cell exactly when its patrol is there.
  //
  // Eleven pieces on an 8x8 is far past any exhaustive sweep (5.03e9 placements
  // for a six-piece kit alone), so this one is carried by its recorded solution
  // — which uses every piece on the path.
  84: LevelData(
    id: 84,
    size: 8,
    title: 'Escapement',
    tip: 'The door is bricked in and you have no charges — but the patrols are '
        'charges. Blow one to free the other, then meet it at the wall.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(1, 7),
    walls: [
      Pos(0, 6), Pos(0, 7), Pos(1, 6), Pos(2, 6), Pos(2, 7),
      Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 4), Pos(3, 5), Pos(3, 6),
      Pos(3, 7),
    ],
    rotatingArrows: [RotatingArrow(6, 3, Direction.right)],
    movers: [
      MovingDestroyer(4, 0, horizontal: true, dir: 1),
      MovingDestroyer(6, 5, horizontal: false, dir: -1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.pause, 3),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 85 — Moulinet: an empty board, two dials, and nothing but portals. No walls,
  // no mines, no arrows — the only turns in the level are the two dials, and the
  // only way to reach them is to wire the pairs so the dot arrives on their rows
  // already pointing at them.
  //
  // The sequence the geometry forces: the dot runs west along row 7 with no way
  // to turn, so a pair must drop it onto row 6 heading west into the (6,1) dial.
  // That dial's FIRST face is west, which pushes it out to (6,0) — so a second
  // pair catches it there and feeds it back for the second face, which is north.
  // The column-1 climb then reaches the (1,1) dial, whose first face is east,
  // and a third pair lifts that row-1 run onto row 0 heading east, into the door
  // at (0,7).
  //
  // Six portals is three pairs and fifteen ways to wire them, so this is carried
  // by its recorded solution rather than a sweep. All six ends are on the path.
  85: LevelData(
    id: 85,
    size: 6,
    title: 'Moulinet',
    tip: 'No walls, no arrows — two dials and six portals. Wire them so each '
        'dial gets the pass it needs.',
    start: StartSpec(5, 5, Direction.left),
    exit: Pos(0, 5),
    rotatingArrows: [
      RotatingArrow(1, 1, Direction.right),
      RotatingArrow(4, 1, Direction.left),
    ],
    toolkit: [
      ToolkitEntry(ToolType.teleporter, 6),
    ],
  ),

  // 86 — Winding Key: wind the dial to its second pass to sweep over the
  // pinned shield, fold back, and climb into the mine-door under the sealed
  // exit chimney.
  86: LevelData(
    id: 86,
    size: 7,
    title: 'Winding Key',
    tip: 'Wind the dial to reach the shield, then climb into the mine under '
        'the sealed chimney.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(0, 3), Pos(0, 5), Pos(1, 3), Pos(1, 5)],
    destroyers: [Pos(1, 4)],
    forcedShields: [Pos(3, 4)],
    rotatingArrows: [RotatingArrow(3, 3, Direction.up)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 87 — Caught Ray: the second dial catches the first one's ray, sweeps the
  // dot west over the shield cell, and the start relaunches it into the
  // first dial's second pass — straight through the mine-door.
  87: LevelData(
    id: 87,
    size: 7,
    title: 'Caught Ray',
    tip: 'The second dial catches the first one\'s throw. Ride it home '
        'across your launch pad — the second pass breaks through.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(3, 6),
    destroyers: [Pos(3, 5), Pos(4, 2), Pos(0, 2)],
    forcedPauses: [Pos(2, 2)],
    rotatingArrows: [
      RotatingArrow(3, 2, Direction.up),
      RotatingArrow(1, 2, Direction.left),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.shield, 1),
    ],
  ),

  // 88 — Stopwatch: the pinned machine ticks the dial through two counts by
  // itself; the player's bounce is the third tick — placed inside the
  // patrol's lane, with the wait sized to fit both clocks.
  88: LevelData(
    id: 88,
    size: 7,
    title: 'Stopwatch',
    tip: 'The machine counts one and two on its own. Your bounce is the '
        'third tick — inside the patrol\'s lane.',
    start: StartSpec(3, 6, Direction.left),
    exit: Pos(3, 0),
    forcedArrows: [
      ForcedArrow(2, 3, Direction.down),
      ForcedArrow(3, 4, Direction.left),
    ],
    rotatingArrows: [RotatingArrow(3, 3, Direction.up)],
    movers: [MovingDestroyer(4, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 89 — Flywheel: the world's great wheel — four dials at the far corners,
  // rays three cells long, a patrol threading its heart. One lap clockwise,
  // one lap back, then the south-east dial's third pass hurls the dot out
  // east. The waits go INSIDE the wheel's own spokes.
  89: LevelData(
    id: 89,
    size: 7,
    title: 'Flywheel',
    tip: 'A wheel as wide as the board, a patrol through its heart. Slow the '
        'spin from inside the spokes, and step off where it throws you.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(5, 6),
    walls: [Pos(6, 6)],
    rotatingArrows: [
      RotatingArrow(1, 1, Direction.right),
      RotatingArrow(1, 5, Direction.down),
      RotatingArrow(5, 5, Direction.left),
      RotatingArrow(5, 1, Direction.up),
    ],
    movers: [MovingDestroyer(3, 3, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 90 — Grand Clockwork: the meshed gears at scale, with a patrol corridor
  // under the gearbox crossed on the down-stroke and again on the up-stroke.
  90: LevelData(
    id: 90,
    size: 8,
    title: 'Grand Clockwork',
    tip: 'Two gears above, one patrol below. Cross on the down-stroke, again '
        'on the up-stroke, and out through the chimney.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(0, 7),
    walls: [
      Pos(1, 2), Pos(0, 4), Pos(1, 4), Pos(6, 2), Pos(6, 5), Pos(1, 7),
      Pos(3, 3), Pos(1, 6),
    ],
    forcedPauses: [Pos(2, 3), Pos(2, 4)],
    rotatingArrows: [
      RotatingArrow(2, 2, Direction.right),
      RotatingArrow(2, 5, Direction.left),
    ],
    movers: [MovingDestroyer(4, 2, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 2),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 91 — Clock Tower: the World 6 summit. Warp out of the pocket, collect the
  // pinned shield (the south's toll — no warp shortcut survives the mine
  // without it), climb through the patrol lane into the dial, ride the caught
  // ray and the wound-up passes across the tower, blast the mine, and drop
  // down the far shaft. Too heavy for the suite's exhaustive solver —
  // verified TIGHT by tool/verify_pairs.dart (2 solutions, all 7 pieces).
  91: LevelData(
    id: 91,
    size: 8,
    title: 'Clock Tower',
    tip: 'Warp in, pay the shield toll, cross the lane twice, catch the ray, '
        'wind the dial to three — and drop home. The final exam.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(7, 7),
    walls: [
      Pos(0, 2), Pos(0, 4), Pos(0, 6),
      Pos(1, 0), Pos(1, 1), Pos(1, 2), Pos(1, 3), Pos(1, 5), Pos(1, 6),
      Pos(2, 0), Pos(2, 1), Pos(2, 2), Pos(2, 3),
      Pos(2, 5), Pos(3, 0), Pos(3, 1), Pos(3, 2), Pos(3, 3), Pos(3, 5),
      Pos(3, 6), Pos(3, 7), Pos(4, 0),
      Pos(5, 0), Pos(5, 1), Pos(5, 2), Pos(5, 3), Pos(5, 5),
      Pos(5, 6), Pos(6, 5), Pos(6, 6), Pos(7, 6),
    ],
    destroyers: [Pos(4, 6)],
    forcedShields: [Pos(7, 1)],
    forcedPauses: [Pos(4, 2), Pos(4, 3), Pos(2, 4), Pos(3, 4)],
    rotatingArrows: [RotatingArrow(4, 4, Direction.left)],
    movers: [MovingDestroyer(6, 2, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowDown, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // ============== WORLD 7 (92–) — ONE-SHOT ARROWS ============================
  // An arrow the dot uses up: it turns once, then leaves the board. The same
  // cell answers differently on the way back, which is the whole idea.

  // 92 — Once Only: the World 7 opener, built so the lesson cannot be missed.
  // The dot runs east into a dead end — nothing but the edge past (2,2) — so the
  // one-shot is the only way to survive. It fires north, the pinned arrow at
  // (0,2) turns the dot straight back down the column it came up, and on that
  // second pass the cell is EMPTY: the dot falls through where it was turned
  // moments ago and drops into the exit below.
  //
  // An ordinary up arrow in the same cell would catch the dot again and loop it
  // forever. Being used up is what makes the route work, not a detail of it.
  //
  // Unique: the pinned arrow only catches column 2, so (2,2) is the one cell the
  // one-shot can sit on.
  92: LevelData(
    id: 92,
    size: 5,
    title: 'Once Only',
    tip: 'This arrow works once, then it is gone. Turn up, come back down — '
        'and fall straight through where it used to be.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(4, 2),
    forcedArrows: [ForcedArrow(0, 2, Direction.down)],
    toolkit: [ToolkitEntry(ToolType.oneShotUp, 1)],
  ),

  // World 7 proper (93–110): eighteen one-shot levels, easy to brutal. The
  // design rule every board here obeys: a one-shot slot must NEED the turn on
  // its first pass (straight ahead is death) and NEED the empty cell on a
  // later pass (a permanent arrow there loops forever) — otherwise the piece
  // is an ordinary arrow in disguise. All eighteen are solver-verified TIGHT
  // by the shipped BruteSearch (one-shots route away from the path solver)
  // and re-verified by the one-shot-aware PairSearch in
  // tool/verify_pairs.dart.
  //
  // Depth pass (2026-08-07, after playtest feedback that the world felt
  // repetitive and easy): 97, 98, 100 and 104–107, 109 were rebuilt so the
  // player builds the tours — pinned routing arrows moved into the kits
  // (kits of 3–5), a third lane and second pause for 98, and stray shortcut
  // families closed with walls, guard mines and pinned pauses rather than
  // steering. 93–95, 99, 101, 103 and 108 keep unique solutions; the rebuilt
  // boards verify TIGHT with a handful of same-machine builds, which is the
  // point — the route is the player's now. 96, 102 and 110 keep their
  // original forms: their de-pinned variants were proven structurally
  // unsound (fungible auras, phase-immune lane rides, and a relaunch orbit
  // no patrol phase can cover).

  // 93 — Burn the Detour: one arrow of each kind, and the lap decides which
  // is which. The permanent up at (4,2) starts the climb on BOTH laps; the
  // one-shot left detours lap one to the pinned shield, the pinned arrow
  // drops the dot home, and the relaunched climb runs straight through the
  // spent cell into the mine the aura now pays for. A permanent left would
  // orbit forever; a one-shot up at (4,2) would leave lap two running off the
  // east edge. The wall at (0,3) closes the back door into the exit row.
  93: LevelData(
    id: 93,
    size: 5,
    title: 'Burn the Detour',
    tip: 'One arrow lasts, one burns. Spend the left fetching the shield — '
        'next lap the climb falls straight through where it was, armour and '
        'all.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 2),
    walls: [Pos(0, 3)],
    destroyers: [Pos(1, 2)],
    forcedArrows: [ForcedArrow(2, 0, Direction.down)],
    forcedShields: [Pos(2, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.oneShotLeft, 1),
    ],
  ),

  // 94 — Relay: two one-shots passed like a baton. Climb and fall through the
  // first (92's figure), kick east off the second and fall back through it
  // westward, collect the pinned shield on the way home, and let the start
  // relaunch the third pass — east across both spent cells and through the
  // mine blast to the door. The mines at (5,2) and (2,4) are the two "straight
  // ahead is death" guards that make each burn mandatory.
  94: LevelData(
    id: 94,
    size: 6,
    title: 'Relay',
    tip: 'Two arrows, each burned once: climb and fall, kick east and fall '
        'again. Grab the armour on the way home — the third pass runs the row '
        'clean through.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 5),
    destroyers: [Pos(5, 2), Pos(2, 4)],
    forcedArrows: [
      ForcedArrow(0, 2, Direction.down),
      ForcedArrow(4, 4, Direction.left),
      ForcedArrow(4, 0, Direction.up),
    ],
    forcedShields: [Pos(4, 1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.oneShotRight, 1),
    ],
  ),

  // 95 — Turnstile: the 92 bounce-figure through a patrol lane, crossed once
  // going up and once falling back down. The patrol hits column 3 at ticks
  // {1,7} of its 10-beat lap: the unheld run's crossings land on 3 and 7 —
  // dead on the second — while the doorstep hold shifts both to safe beats.
  // A hold inside the column is counted twice and dies at tick 11 ≡ 1.
  // Solver-verified TIGHT and UNIQUE.
  95: LevelData(
    id: 95,
    size: 6,
    title: 'Turnstile',
    tip: 'One turn of the stile, then it folds flat. Hold a beat on the '
        'doorstep — the lane above is crossed going up AND coming down.',
    start: StartSpec(3, 1, Direction.right),
    exit: Pos(5, 3),
    forcedArrows: [ForcedArrow(0, 3, Direction.down)],
    movers: [MovingDestroyer(2, 4, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 96 — Backdraft: the climb rams the mine and the blast demolishes the wall
  // ABOVE it — the climb clears its own ceiling. The bounce then falls back
  // through the hole and the spent cell alike. The mine at (3,4) kills the
  // straight run east, so the turn is mandatory; the shield's only slot is
  // the one approach cell. Solver-verified TIGHT and UNIQUE.
  96: LevelData(
    id: 96,
    size: 6,
    title: 'Backdraft',
    tip: 'Armour up, punch through the mine — the blast takes the ceiling '
        'with it. The way home falls through the hole you made.',
    start: StartSpec(3, 1, Direction.right),
    exit: Pos(5, 3),
    walls: [Pos(1, 3)],
    destroyers: [Pos(2, 3), Pos(3, 4)],
    forcedArrows: [ForcedArrow(0, 3, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.oneShotUp, 1),
    ],
  ),

  // 97 — Roadworks: a short patrol lane walled at (3,4), and the mine above
  // that wall is the demolition charge — ramming it shielded EXTENDS the lane
  // mid-run, so the descent crosses a longer, slower patrol than the climb
  // did. The top of the tour is the player's to build (the old pinned right
  // and down joined the kit — depth pass); the wall at (4,3) closes the
  // freeway a mid-climb turn would open. Solver-verified TIGHT (three roof
  // lines, one machine).
  97: LevelData(
    id: 97,
    size: 7,
    title: 'Roadworks',
    tip: 'The wall pens the patrol into half its road. Blast it open and the '
        'lane doubles — build the tour over the top, and time each crossing '
        'for its own road.',
    start: StartSpec(5, 1, Direction.right),
    exit: Pos(5, 5),
    walls: [Pos(3, 4), Pos(4, 3)],
    destroyers: [Pos(2, 4), Pos(5, 3)],
    forcedArrows: [
      ForcedArrow(6, 4, Direction.left),
      ForcedArrow(6, 1, Direction.up),
    ],
    forcedShields: [Pos(0, 3), Pos(6, 2)],
    movers: [MovingDestroyer(3, 1, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 98 — Metronome: the bounce column now crosses THREE patrol lanes — six
  // crossings in one run — and the kit holds two pauses. The only winning
  // build stacks both holds inside the column, one between each pair of
  // lanes, each counted on the climb AND the fall (depth pass; phases found
  // by a full three-lane sweep). Solver-verified TIGHT and UNIQUE.
  98: LevelData(
    id: 98,
    size: 7,
    title: 'Metronome',
    tip: 'Six crossings, three lanes, two holds. Stack the beats between the '
        'lanes — each one is counted going up and again coming down.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(6, 3),
    forcedArrows: [ForcedArrow(0, 3, Direction.down)],
    movers: [
      MovingDestroyer(1, 1, horizontal: true, dir: 1),
      MovingDestroyer(3, 1, horizontal: true, dir: 1),
      MovingDestroyer(5, 3, horizontal: true, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.pause, 2),
    ],
  ),

  // 99 — Through the Floor: the 92 bounce falls through the spent cell INTO a
  // portal on the floor below it, and pops out at the top of the walled
  // chimney beside the exit. The mine at (5,4) kills every warp shortcut
  // along the floor, and the chimney walls pin the exit-side end to (4,5) —
  // the pair's wiring is forced. Solver-verified TIGHT and UNIQUE.
  99: LevelData(
    id: 99,
    size: 6,
    title: 'Through the Floor',
    tip: 'Fall through where the arrow was, straight into the warp below it — '
        'and step out at the top of the chimney next door.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(5, 5),
    walls: [Pos(0, 5), Pos(1, 5), Pos(2, 5), Pos(3, 5)],
    destroyers: [Pos(5, 4)],
    forcedArrows: [ForcedArrow(0, 2, Direction.down)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),

  // 100 — Wind-Up: the rotor fires up into the one-shot, which bounces the
  // ray back short of the mine — the bare ray dies on it. The wound dial
  // throws the tour east through two pinned holds, and from there the route
  // is the player's to build (depth pass: the roof turns joined the kit):
  // over the wall, west along the roof through the row-0 lane, and down
  // through the mine blast into the spent cell and the third face. The walls
  // at (3,5) and (2,0) close the short-tour and start-relaunch cheats.
  // Solver-verified TIGHT.
  100: LevelData(
    id: 100,
    size: 7,
    title: 'Wind-Up',
    tip: 'Bounce the first ray short of the mine and the dial winds itself — '
        'then build the grand tour yourself: over the wall, along the roof, '
        'and down through the blast into the third face.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(6, 3),
    walls: [Pos(3, 5), Pos(2, 0)],
    destroyers: [Pos(1, 3)],
    forcedArrows: [ForcedArrow(4, 6, Direction.up)],
    forcedShields: [Pos(2, 6)],
    forcedPauses: [Pos(4, 4), Pos(4, 5)],
    rotatingArrows: [RotatingArrow(4, 3, Direction.up)],
    movers: [MovingDestroyer(0, 0, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotDown, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 101 — Slow Fuse: three one-shots on the start row, burned strictly left
  // to right over three relaunch laps. Loop one fetches the first aura; loop
  // two spends it on the mine, rides the top, falls down the east wall over
  // the second aura and KILLS the row-5 patrol at exactly (5,5) — the kill's
  // chain blast is what opens the wall door at (4,5). The final burn drops
  // through the door. No aura can fake a wall opening, so the loops cannot
  // be skipped; the pinned pause at (5,5) keeps the kill cell placement-free
  // and holds the ride two beats over the meet. Solver-verified TIGHT and
  // UNIQUE.
  101: LevelData(
    id: 101,
    size: 7,
    title: 'Slow Fuse',
    tip: 'Three fuses on one row, burned in order. The second lap must ram '
        'the patrol right beside the door — only that blast opens it for the '
        'third.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(6, 5),
    walls: [Pos(4, 5)],
    destroyers: [Pos(2, 3)],
    forcedArrows: [
      ForcedArrow(1, 1, Direction.left),
      ForcedArrow(1, 0, Direction.down),
      ForcedArrow(0, 3, Direction.right),
      ForcedArrow(0, 6, Direction.down),
      ForcedArrow(5, 6, Direction.left),
      ForcedArrow(5, 0, Direction.up),
    ],
    forcedShields: [Pos(2, 1), Pos(2, 6)],
    forcedPauses: [Pos(5, 5)],
    movers: [MovingDestroyer(5, 4, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 2),
      ToolkitEntry(ToolType.oneShotDown, 1),
    ],
  ),

  // 102 — Punch Card: the climb blasts the mine with the placed aura, picks
  // up the pinned one, and must MEET the row-2 patrol in its own column —
  // the kill is what makes the later fall safe on every beat. The fall then
  // drops through the whole punched column: dead lane, taken shield, cleared
  // mine, spent one-shot — and the floor run rides the row-6 patrol's lane
  // to the door. Two winning timings of the same kill (hold above the lane,
  // or hold inside it); solver-verified TIGHT.
  102: LevelData(
    id: 102,
    size: 7,
    title: 'Punch Card',
    tip: 'Punch the column: mine, shield, sentry, arrow. Meet the patrol in '
        'your own lane — the fall only reads clean through a dead one.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(6, 6),
    destroyers: [Pos(4, 2)],
    forcedArrows: [
      ForcedArrow(0, 2, Direction.down),
      ForcedArrow(6, 2, Direction.right),
    ],
    forcedShields: [Pos(3, 2)],
    movers: [
      MovingDestroyer(2, 1, horizontal: true, dir: 1),
      MovingDestroyer(6, 2, horizontal: true, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.pause, 1),
    ],
  ),

  // 103 — Three Clocks: one machine, three kinds of answer. The permanent up
  // at (6,4) bounces both of its arrivals; the rotor at (1,4) gives a
  // different ray each pass — right, down, left; the one-shot down at (0,4)
  // answers once, and the final run west crosses its empty cell into the
  // mine the pinned aura pays for. Swap the two kit arrows and the board
  // refuses both ways. Solver-verified TIGHT and UNIQUE.
  103: LevelData(
    id: 103,
    size: 7,
    title: 'Three Clocks',
    tip: 'A steady arrow answers every time, a dial answers differently, a '
        'one-shot answers once. Place the two you hold where each is the '
        'right kind of clock.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 0),
    destroyers: [Pos(0, 2)],
    forcedArrows: [
      ForcedArrow(1, 6, Direction.up),
      ForcedArrow(0, 6, Direction.left),
      ForcedArrow(1, 1, Direction.down),
      ForcedArrow(5, 1, Direction.right),
      ForcedArrow(5, 6, Direction.up),
    ],
    forcedShields: [Pos(3, 1)],
    rotatingArrows: [RotatingArrow(1, 4, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.oneShotDown, 1),
    ],
  ),

  // 104 — Tinderbox: one portal pair, entered twice with different headings.
  // The bounce falls through the spent cell, and from there the tour is
  // player-built (depth pass: the floor and chimney turns joined the kit):
  // along the floor, up through a mine, into the portal NORTH-bound — out at
  // the chimney, over the second mine, back along the roof — and into the
  // same portal WEST-bound, landing beside the door. The mine at (5,3)
  // guards the straight run AND blocks the portal-on-the-floor cheat.
  // Solver-verified TIGHT; several tours win, all five pieces deep.
  104: LevelData(
    id: 104,
    size: 7,
    title: 'Tinderbox',
    tip: 'One warp, two ways through it: in from below climbing, in from the '
        'roof walking west. Build the tour that feeds it twice.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(5, 5),
    walls: [Pos(6, 5), Pos(6, 0), Pos(4, 5)],
    destroyers: [Pos(5, 4), Pos(3, 6), Pos(5, 3)],
    forcedArrows: [
      ForcedArrow(0, 2, Direction.down),
      ForcedArrow(0, 6, Direction.left),
    ],
    forcedShields: [Pos(6, 3), Pos(1, 4)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.teleporter, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 105 — Powder Trail: a player-built double-bounce through two patrol
  // lanes (depth pass: every pinned arrow joined the kit). Burn up into the
  // top catcher, fall back through the spent cell and BOTH lanes, hook west
  // over the pinned aura, climb the wall to the start's relaunch — and run
  // the spent row home through the mine. Five lane crossings against two
  // clocks, and the whole route is the player's. Walls at (1,6) and (3,6)
  // close the east-wall hooks. Solver-verified TIGHT.
  105: LevelData(
    id: 105,
    size: 7,
    title: 'Powder Trail',
    tip: 'Build the whole trail: burn up, fall through both lanes, hook west '
        'for the armour, and let your launch pad fire the lap that blasts '
        'home.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 6),
    walls: [Pos(1, 6), Pos(3, 6)],
    destroyers: [Pos(2, 4)],
    forcedShields: [Pos(4, 1)],
    movers: [
      MovingDestroyer(1, 3, horizontal: true, dir: 1),
      MovingDestroyer(3, 3, horizontal: true, dir: 1),
    ],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 106 — Matchbook: the rotor at (5,4) winds itself — its first face throws
  // the dot down into the pinned bounce, the second throws it west across
  // the spent cell to the start, and the relaunch feeds it a third time. But
  // the third face's ray up column 4 is mined, and the only aura hangs off
  // the one-shot's climb over the top and down the east wall, through the
  // row-2 patrol. The roof route is player-built (depth pass: the top turns
  // joined the kit); the wall at (1,3) seals the hook into the exit row.
  // Solver-verified TIGHT (six builds, one machine).
  106: LevelData(
    id: 106,
    size: 7,
    title: 'Matchbook',
    tip: 'The dial winds itself off the wall below it — but its last ray is '
        'mined. Build the climb over the top yourself, fetch the armour, and '
        'let the third face throw you through.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(1, 4),
    walls: [Pos(1, 3)],
    destroyers: [Pos(3, 4)],
    forcedArrows: [
      ForcedArrow(6, 6, Direction.left),
      ForcedArrow(6, 4, Direction.up),
    ],
    forcedShields: [Pos(2, 6)],
    rotatingArrows: [RotatingArrow(5, 4, Direction.down)],
    movers: [MovingDestroyer(2, 3, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 107 — Firebreak: a fully player-built double-burn on the 8x8 (depth
  // pass: no pinned arrows at all). Burn up mid-board, catch the climb with
  // your own down arrow and fall back through the spent cell, the lane and
  // the pinned aura; burn west along the floor, climb your own up arrow to
  // the start's relaunch — and the final lap runs both spent cells into the
  // mine blast and out the east door. The wall chimney at (4,7)/(6,7) seals
  // the east-wall drop-ins. Solver-verified TIGHT.
  107: LevelData(
    id: 107,
    size: 8,
    title: 'Firebreak',
    tip: 'No rails this time. Two burns, a catcher, a climb — build the whole '
        'firebreak, and let your launch pad fire the last lap through the '
        'blast.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(5, 7),
    walls: [Pos(4, 7), Pos(6, 7)],
    destroyers: [Pos(5, 6)],
    forcedShields: [Pos(6, 5)],
    movers: [MovingDestroyer(6, 3, horizontal: true, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.oneShotLeft, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 108 — Burning Bridges: the pure exam — three bounces on a descending
  // ladder, each pinned catcher one rung lower, each fall burning the bridge
  // it just crossed. One mine guards the first row; every other straight
  // line ends at an edge, so each turn is mandatory and each spent cell is
  // fallen through. No shields, no patrols, no warps: just geometry and
  // three arrows that stop existing. Solver-verified TIGHT and UNIQUE.
  108: LevelData(
    id: 108,
    size: 8,
    title: 'Burning Bridges',
    tip: 'Three bridges, three burns, each one rung lower. Cross, fall '
        'through the ashes, and cross again — there is no way back up.',
    start: StartSpec(1, 0, Direction.right),
    exit: Pos(7, 7),
    destroyers: [Pos(1, 4)],
    forcedArrows: [
      ForcedArrow(0, 2, Direction.down),
      ForcedArrow(3, 2, Direction.right),
      ForcedArrow(2, 4, Direction.down),
      ForcedArrow(5, 4, Direction.right),
      ForcedArrow(4, 6, Direction.down),
      ForcedArrow(7, 6, Direction.right),
    ],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 3),
    ],
  ),

  // 109 — Embers: the caught-ray exam. The rotor's first ray is bounced
  // short of the mine by the once-down; the second face throws the dot east
  // through the pinned hold into the column-7 lane — a five-cell ride
  // straight up a patrol's own road, which only the right hold survives. The
  // top-row return — its west turn now the player's own arrow (depth pass) —
  // falls back down column 5, blasts the mine with the aura from the ride,
  // crosses the spent cell, and the third face drops the dot out at the
  // bottom. The pinned pause on the ray keeps the cheap ray-bounce slot out
  // of reach. Solver-verified TIGHT.
  109: LevelData(
    id: 109,
    size: 8,
    title: 'Embers',
    tip: 'Bounce the first ray, ride the second straight up the sentry\'s own '
        'column, and build the return that falls home down the third — '
        'through the ember you already burned.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(7, 5),
    destroyers: [Pos(1, 5)],
    forcedArrows: [
      ForcedArrow(5, 7, Direction.up),
      ForcedArrow(0, 5, Direction.down),
    ],
    forcedShields: [Pos(2, 7)],
    forcedPauses: [Pos(5, 6)],
    rotatingArrows: [RotatingArrow(5, 5, Direction.up)],
    movers: [MovingDestroyer(3, 7, horizontal: false, dir: 1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotDown, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.arrowLeft, 1),
    ],
  ),

  // 110 — Once and For All: the World 7 finale, and the whole world in one
  // run. The burn at (7,3) starts the climb across the lane into the rotor's
  // first face; the pinned drop brings the dot home for the relaunch, whose
  // doorstep pause is held on BOTH floor passes; the relaunch crosses the
  // spent cell, blasts the first mine, and climbs the far tower over the
  // second aura; the roof run enters the portal WEST-bound — its wiring
  // forced by the column-5 mine seam and the exit's mined flanks — and the
  // rotor's second face lifts the dot up the guarded column, through the
  // last blast, into the door. Solver-verified TIGHT and UNIQUE.
  110: LevelData(
    id: 110,
    size: 8,
    title: 'Once and For All',
    tip: 'Everything burns once: the arrow, the auras, the beats of the '
        'doorstep hold. Wind the dial twice, thread the warp, and finish it '
        '— once and for all.',
    start: StartSpec(7, 1, Direction.right),
    exit: Pos(0, 3),
    walls: [Pos(0, 2)],
    destroyers: [
      Pos(7, 5), Pos(3, 5), Pos(0, 5), Pos(0, 4), Pos(1, 3),
    ],
    forcedArrows: [
      ForcedArrow(3, 0, Direction.down),
      ForcedArrow(7, 0, Direction.right),
      ForcedArrow(7, 7, Direction.up),
      ForcedArrow(0, 7, Direction.left),
    ],
    forcedShields: [Pos(5, 0), Pos(1, 7)],
    rotatingArrows: [RotatingArrow(3, 3, Direction.left)],
    movers: [MovingDestroyer(6, 6, horizontal: true, dir: -1)],
    toolkit: [
      ToolkitEntry(ToolType.oneShotUp, 1),
      ToolkitEntry(ToolType.pause, 1),
      ToolkitEntry(ToolType.teleporter, 2),
    ],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
