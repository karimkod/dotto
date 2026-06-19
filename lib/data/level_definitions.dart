import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Playable level definitions, keyed by level number.
///
/// World 1 (levels 1–15): from "press Play" to multi-turn routing around walls
/// and fixed (forced) arrows.
///
/// World 2 (levels 16–25): Static Destroyers. Red cells kill the dot on contact,
/// so the toolkit's specific arrows must thread a safe route.
///
/// World 3 (levels 26–40): Shields & Explosions. The Shield aura lets the dot
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
  // Levels 16–30. Red destroyer cells are lethal on contact. Open layouts where
  // possible: destroyers eliminate the wrong routes instead of walls building
  // corridors. All solver-verified tight (every toolkit piece required).

  // ----- Learn (16–18) -----

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

  // 17 — Two Threats: two destroyers; route between them to the far corner.
  17: LevelData(
    id: 17,
    size: 4,
    title: 'Two Threats',
    tip: 'Two red cells lie ahead. Steer the dot safely between them.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(3, 3),
    destroyers: [Pos(2, 0), Pos(2, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowRight, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 18 — Destroyer Wall: three destroyers form a barrier; go up and over it.
  18: LevelData(
    id: 18,
    size: 5,
    title: 'Destroyer Wall',
    tip: 'A wall of destroyers blocks the way. Climb up and over the top.',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    destroyers: [Pos(2, 2), Pos(3, 2), Pos(4, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // ----- Combine (19–22) -----

  // 19 — Trap Arrow: the fixed arrow aims the dot straight at a destroyer.
  // Redirect with your Up arrow before it gets there, then run home.
  19: LevelData(
    id: 19,
    size: 5,
    title: 'Trap Arrow',
    tip: 'The fixed arrow points the dot toward a destroyer. Save it in time.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(0, 4),
    walls: [Pos(2, 3), Pos(3, 3)],
    destroyers: [Pos(4, 2), Pos(1, 4)],
    forcedArrows: [ForcedArrow(4, 0, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 20 — Crossfire: a centre start with destroyers on the approaches. Several
  // routes look open, but only the long way round survives.
  20: LevelData(
    id: 20,
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

  // 21 — Minefield: an open board scattered with destroyers; thread the one
  // safe staircase up to the corner.
  21: LevelData(
    id: 21,
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

  // 22 — Safe Passage: ride the fixed arrow up and across, then slip down the
  // one gap in the destroyer line before sliding home along the bottom.
  22: LevelData(
    id: 22,
    size: 6,
    title: 'Safe Passage',
    tip: 'Follow the fixed arrow, then find the one safe drop past the red line.',
    start: StartSpec(5, 0, Direction.up),
    exit: Pos(5, 5),
    destroyers: [
      Pos(0, 3),
      Pos(1, 1),
      Pos(1, 5),
      Pos(2, 5),
      Pos(3, 5),
      Pos(4, 5),
    ],
    forcedArrows: [ForcedArrow(0, 0, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // ----- Challenge (23–25) -----

  // 23 — Needle's Eye: a dense destroyer field with one threading path.
  23: LevelData(
    id: 23,
    size: 6,
    title: "Needle's Eye",
    tip: 'A dense field of destroyers. There is only one way through.',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 4),
    destroyers: [
      Pos(5, 3),
      Pos(2, 1),
      Pos(2, 2),
      Pos(1, 3),
      Pos(2, 5),
      Pos(0, 3),
    ],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 24 — Into the Fire: the fixed arrow plunges the dot toward a destroyer.
  // Escape left across the board, then drop down to the corner.
  24: LevelData(
    id: 24,
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

  // 25 — Long Detour: a big open 7x7. The fixed arrow starts the climb; you
  // build the rest of the staircase around the destroyers and a wall.
  25: LevelData(
    id: 25,
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
  // Levels 26–40. The Shield aura lets the dot survive one destroyer; the hit
  // also CHAIN-EXPLODES every wall orthogonally adjacent to that destroyer,
  // turning destroyers-next-to-walls into doors. All solver-verified tight.

  // ----- Learn shields (26–28) -----

  // 26 — Shield Up: grab the shield, then survive the destroyer in the way.
  26: LevelData(
    id: 26,
    size: 4,
    title: 'Shield Up',
    tip: 'Place the shield before the destroyer. The aura lets the dot survive.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(3, 3),
    destroyers: [Pos(3, 2)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // 27 — Must Shield: the destroyer is dead ahead with no way around it.
  27: LevelData(
    id: 27,
    size: 5,
    title: 'Must Shield',
    tip: 'No way around — you must shield up and go straight through.',
    start: StartSpec(4, 2, Direction.up),
    exit: Pos(0, 2),
    destroyers: [Pos(2, 2)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // 28 — Shield Timing: pick up the shield FIRST, then turn into the destroyer.
  28: LevelData(
    id: 28,
    size: 5,
    title: 'Shield Timing',
    tip: 'Order matters: route through the shield first, then into the danger.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(4, 4),
    destroyers: [Pos(3, 4)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // ----- Shield + path clearing (29–32) -----

  // 29 — Break Through: a shielded hit blasts the wall blocking the exit.
  29: LevelData(
    id: 29,
    size: 5,
    title: 'Break Through',
    tip: 'A shielded hit also destroys the walls beside the destroyer. Open it.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 4),
    destroyers: [Pos(2, 2)],
    walls: [Pos(1, 3), Pos(2, 3), Pos(3, 3)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // 30 — Choose Your Bomb: only the destroyer beside the right wall opens a way.
  30: LevelData(
    id: 30,
    size: 5,
    title: 'Choose Your Bomb',
    tip: 'One destroyer opens the path; the other is just a trap. Pick wisely.',
    start: StartSpec(0, 2, Direction.down),
    exit: Pos(4, 2),
    destroyers: [Pos(2, 2), Pos(1, 4)],
    walls: [Pos(3, 2), Pos(1, 3)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // 31 — Double Breach: two destroyer-doors, two shields and a turn.
  31: LevelData(
    id: 31,
    size: 6,
    title: 'Double Breach',
    tip: 'Two walls, two doors. Shield up for each blast.',
    start: StartSpec(0, 0, Direction.down),
    exit: Pos(5, 5),
    destroyers: [Pos(2, 0), Pos(5, 2)],
    walls: [Pos(3, 0), Pos(5, 3)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 32 — Demolition: one keystone destroyer levels a whole wall cluster.
  32: LevelData(
    id: 32,
    size: 6,
    title: 'Demolition',
    tip: 'A single shielded blast clears every wall around the destroyer.',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 5),
    destroyers: [Pos(2, 2)],
    walls: [Pos(1, 2), Pos(1, 3), Pos(2, 3), Pos(3, 2), Pos(3, 3)],
    toolkit: [ToolkitEntry(ToolType.shield, 1)],
  ),

  // ----- Challenge (33–35) -----

  // 33 — Detour Blast: the exit is walled off; route to the door and breach it.
  33: LevelData(
    id: 33,
    size: 6,
    title: 'Detour Blast',
    tip: 'The exit is boxed in. Find the destroyer-door and blow it open.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(5, 5),
    destroyers: [Pos(5, 3)],
    walls: [Pos(4, 5), Pos(5, 4)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 34 — Pinned Breach: ride the fixed arrow, breach a wall, drop to the exit.
  34: LevelData(
    id: 34,
    size: 7,
    title: 'Pinned Breach',
    tip: 'The fixed arrow turns the corner. Breach the wall, then drop home.',
    start: StartSpec(6, 0, Direction.up),
    exit: Pos(6, 6),
    destroyers: [Pos(0, 3)],
    walls: [Pos(0, 4)],
    forcedArrows: [ForcedArrow(0, 0, Direction.right)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // 35 — Twin Doors: two doors in series — breach, turn, breach again.
  35: LevelData(
    id: 35,
    size: 7,
    title: 'Twin Doors',
    tip: 'Two doors, one after the other. Carry a shield into each.',
    start: StartSpec(1, 0, Direction.right),
    exit: Pos(5, 4),
    destroyers: [Pos(1, 2), Pos(3, 4)],
    walls: [Pos(1, 3), Pos(4, 4)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 2),
      ToolkitEntry(ToolType.arrowDown, 1),
    ],
  ),

  // ----- Exams (36–40): combine arrows, walls, forced arrows, deadly + door
  // destroyers and shields. Open layouts, growing to 8x8. -----

  // 36 — a boxed exit door, with a deadly destroyer to steer clear of.
  36: LevelData(
    id: 36,
    size: 6,
    title: 'Live Wire',
    tip: 'Breach the door to the exit — and don\'t touch the loose destroyer.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(5, 5),
    destroyers: [Pos(5, 3), Pos(2, 2)],
    walls: [Pos(4, 5), Pos(5, 4)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 37 — Wall Breaker: punch through the wall on the floor, then climb.
  37: LevelData(
    id: 37,
    size: 7,
    title: 'Wall Breaker',
    tip: 'Breach the wall across the floor, then turn up to the exit.',
    start: StartSpec(6, 0, Direction.right),
    exit: Pos(0, 6),
    destroyers: [Pos(6, 2)],
    walls: [Pos(6, 3)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
    ],
  ),

  // 38 — Boxed In: drop down, run across and breach the door to the corner.
  38: LevelData(
    id: 38,
    size: 7,
    title: 'Boxed In',
    tip: 'The exit is sealed. Work down to the door and blast your way in.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(6, 6),
    destroyers: [Pos(6, 4)],
    walls: [Pos(5, 6), Pos(6, 5)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 39 — The Vault: a big 8x8; reach the sealed corner, dodging a loose mine.
  39: LevelData(
    id: 39,
    size: 8,
    title: 'The Vault',
    tip: 'Cross the board to the sealed corner and breach the vault door.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(7, 7),
    destroyers: [Pos(7, 5), Pos(0, 3)],
    walls: [Pos(6, 7), Pos(7, 6)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),

  // 40 — Grand Demolition: the World 3 finale. A wide 8x8 minefield with a
  // sealed exit; thread past the loose mines and breach the vault.
  40: LevelData(
    id: 40,
    size: 8,
    title: 'Grand Demolition',
    tip: 'Mines everywhere. Thread to the sealed corner and blow it open.',
    start: StartSpec(0, 0, Direction.right),
    exit: Pos(7, 7),
    destroyers: [Pos(7, 5), Pos(4, 1), Pos(2, 5)],
    walls: [Pos(6, 7), Pos(7, 6)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowDown, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
