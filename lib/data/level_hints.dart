// The recorded solution for every level — one known-good set of placements.
//
// This is the data the in-game hints read from: a hint reveals the next
// placement the player has not made yet, so a wrong entry here would hand the
// player a losing board, which is worse than offering no hint at all.
//
// It is not trusted on faith. test/levels_solvable_test.dart imports these maps
// and simulates each one, so "level N intended solution wins" is simultaneously
// the proof that level N is solvable and that its hints are correct. That test
// was the original home of this data; it moved here so the game and the test
// could not drift apart.
//
// Placements are grouped the way the toolkit is: arrows carry a direction,
// shields, pauses and teleporters are bare cells. Teleporter order matters —
// consecutive entries pair up, index i with i^1 — which is how a pairing that
// board order cannot express (level 59's crossing wiring) is written down.

import '../models/game_state.dart';
import '../models/grid_cell.dart';

// Intended arrow placements per level (empty where the kit is shields-only).
const kSolutionArrows = <int, List<(int, int, Direction)>>{
  // ----- World 1 -----
  1: [],
  2: [(2, 2, Direction.up)],
  3: [(2, 0, Direction.right)],
  4: [(2, 2, Direction.left), (2, 0, Direction.up)],
  5: [(3, 2, Direction.up), (0, 2, Direction.left)],
  6: [(0, 2, Direction.left), (0, 0, Direction.down), (4, 0, Direction.right)],
  7: [(3, 1, Direction.left)],
  8: [(0, 0, Direction.right), (0, 4, Direction.down)],
  9: [(4, 2, Direction.right), (4, 4, Direction.up), (0, 4, Direction.left)],
  10: [(2, 3, Direction.down), (4, 3, Direction.right), (4, 5, Direction.down)],
  11: [(1, 0, Direction.right), (1, 3, Direction.down), (3, 3, Direction.left)],
  12: [(0, 4, Direction.down), (6, 2, Direction.up), (6, 6, Direction.up)],
  13: [(0, 1, Direction.down), (2, 2, Direction.right), (4, 5, Direction.down)],
  14: [(0, 6, Direction.down), (2, 0, Direction.down), (4, 6, Direction.down)],
  15: [
    (7, 0, Direction.right),
    (0, 1, Direction.right),
    (7, 3, Direction.right),
    (0, 4, Direction.right),
    (7, 6, Direction.right),
  ],
  // ----- World 2 (16–20): the five hand-picked destroyer levels. -----
  16: [(3, 1, Direction.up)],
  17: [(0, 2, Direction.left), (0, 0, Direction.down), (4, 0, Direction.right)],
  18: [(5, 3, Direction.up), (2, 3, Direction.right), (2, 5, Direction.up)],
  19: [(2, 5, Direction.left), (2, 3, Direction.down), (5, 3, Direction.left)],
  20: [(3, 2, Direction.right), (3, 4, Direction.up), (0, 4, Direction.right)],
  // ----- World 3 (21–35): arrows here, shields in `shields` below. -----
  21: [],
  22: [
    (0, 3, Direction.right),
    (4, 3, Direction.up),
    (4, 4, Direction.left),
  ],
  23: [
    (0, 1, Direction.down),
    (0, 3, Direction.left),
    (2, 3, Direction.up),
    (3, 1, Direction.right),
    (3, 4, Direction.down),
  ],
  24: [(0, 1, Direction.right), (2, 1, Direction.up)],
  25: [], // shields only (see below)
  26: [
    (0, 5, Direction.left),
    (2, 0, Direction.right),
    (2, 5, Direction.up),
    (4, 2, Direction.right),
    (4, 5, Direction.down),
  ],
  27: [
    (2, 5, Direction.down),
    (3, 0, Direction.down),
    (3, 5, Direction.left),
    (5, 0, Direction.right),
  ],
  28: [(0, 3, Direction.down), (5, 3, Direction.right)],
  29: [
    (3, 2, Direction.right),
    (5, 4, Direction.right),
    (5, 6, Direction.down),
  ],
  30: [
    (3, 3, Direction.right),
    (3, 5, Direction.down),
    (5, 2, Direction.down),
    (5, 5, Direction.left),
  ],
  // ----- World 4 (31–46): arrows here, pauses/shields below. -----
  31: [(3, 3, Direction.up)],
  32: [(3, 3, Direction.right), (3, 4, Direction.up), (4, 3, Direction.up)],
  33: [(0, 5, Direction.left), (5, 5, Direction.up)],
  34: [(5, 1, Direction.up), (0, 1, Direction.left)],
  // 35–39: shield + patrol chain explosions (shields listed below).
  35: [(4, 2, Direction.up)],
  36: [(4, 3, Direction.up)],
  37: [(0, 5, Direction.left), (5, 5, Direction.up)],
  38: [(0, 5, Direction.down), (5, 3, Direction.up)],
  39: [(1, 6, Direction.left), (6, 6, Direction.up)],
  // 40: pure timing — weave around the sweeping patrol.
  40: [(2, 2, Direction.down), (5, 2, Direction.right), (5, 5, Direction.up)],
  // 41–46: timing puzzles (pauses listed below).
  41: [],
  42: [(3, 3, Direction.up)],
  43: [(5, 0, Direction.up), (5, 5, Direction.left)],
  44: [(0, 2, Direction.left), (5, 2, Direction.up)],
  // 45: shield through (1,3) to blow the wall at (1,4) open, then ride the
  // forced arrow at (1,0) along row 1 and out.
  45: [
    (0, 1, Direction.right),
    (0, 2, Direction.down),
    (4, 0, Direction.up),
    (4, 2, Direction.left),
    (6, 1, Direction.up),
  ],
  // 46: climb column 2, spending a shield on each patrol row that blocks it.
  46: [(0, 2, Direction.right), (6, 2, Direction.up)],
  // 47–50: final exams.
  // 47: the exit is boxed in and there are no mines — the two patrols are the
  // only demolition charges, and the first blast frees the second patrol.
  47: [
    (2, 7, Direction.left),
    (5, 4, Direction.right),
    (5, 7, Direction.up),
    (7, 4, Direction.up),
  ],
  // 48: shield through the two floor mines, climb column 7 waiting out three
  // patrols, then run row 0 home past a third mine and two more patrols.
  48: [(0, 7, Direction.left), (7, 7, Direction.up)],
  // 49: shield the corridor patrol between the two barriers — one blast opens
  // row 2 and row 4 at the same column — then climb through and run home.
  49: [
    (1, 0, Direction.up),
    (1, 4, Direction.left),
    (5, 4, Direction.up),
    (5, 6, Direction.left),
  ],
  // 50: blast out of the sealed box through the column-2 wall, climb the free
  // left edge, then run row 0 home past the three top-run patrols.
  50: [
    (0, 0, Direction.right),
    (3, 6, Direction.down),
    (4, 0, Direction.up),
    (4, 6, Direction.left),
  ],
  // ----- World 5 (51–60): teleporters. -----
  // 51: no arrows — just the pair. Run the open bottom row into a portal at
  // (4,4) and step out at (0,3), past the L-wall, then into the exit.
  51: [],
  52: [(0, 3, Direction.left)],
  53: [], // shield + portal only
  54: [(2, 2, Direction.right)],
  // 55: warp up, then a drop arrow per serpentine row plus a left/right turn.
  55: [
    (0, 6, Direction.down),
    (2, 0, Direction.down),
    (4, 6, Direction.down),
    (2, 6, Direction.left),
    (4, 0, Direction.right),
  ],
  56: [(6, 1, Direction.up), (5, 1, Direction.left)],
  57: [(5, 4, Direction.up), (3, 4, Direction.left)],
  58: [(2, 6, Direction.down)],
  // 59 hands out only portals — no arrows. The two arrows on the path are
  // forced (fixed on the board), so the intended arrow list is empty.
  59: [],
  // 60: turn up at the track corner, left into the inner patrol's lane, and
  // down at the keystone (2,4) where the shielded kill opens the core.
  60: [(8, 8, Direction.up), (2, 6, Direction.left), (2, 4, Direction.down)],
  // ----- Master Trials (61–70): remixes of taught rules, no new pieces. ----
  // 61: over the top, trailing the patrol — the row-2 return would relaunch
  // off the start.
  61: [(2, 2, Direction.up), (0, 2, Direction.left), (0, 0, Direction.down)],
  // 62: the ring does all the turning; one arrow aims the shielded dot at
  // the mine beside the exit.
  62: [(0, 2, Direction.left)],
  // 63: the pair is the clock; the single arrow turns the climb.
  63: [(5, 5, Direction.up)],
  // 64: six arrows complete the serpentine circuit.
  64: [
    (6, 5, Direction.up),
    (4, 5, Direction.left),
    (4, 2, Direction.up),
    (2, 2, Direction.right),
    (2, 6, Direction.up),
    (0, 6, Direction.left),
  ],
  // 65: climb, hook over the pen, dive through the mine, and climb the
  // freshly patrolled chimney.
  65: [
    (6, 2, Direction.up),
    (1, 2, Direction.right),
    (1, 3, Direction.down),
    (6, 3, Direction.right),
    (6, 4, Direction.up),
  ],
  // 66: one turn up the warp column — the pair does the rest.
  66: [(6, 5, Direction.up)],
  // 67: up through the long patrol's lane, east across the short one's.
  67: [
    (6, 2, Direction.up),
    (2, 2, Direction.right),
    (2, 5, Direction.up),
    (0, 5, Direction.left),
  ],
  // 68: climb, dive through the pen mine, loop under, and climb into the
  // extended lane for the kill.
  68: [
    (6, 2, Direction.up),
    (2, 2, Direction.right),
    (2, 3, Direction.down),
    (5, 3, Direction.right),
    (5, 4, Direction.up),
  ],
  // 69: straight up the shaft, then west along the guarded exit row.
  69: [(6, 3, Direction.up), (0, 3, Direction.left)],
  // 70: the circuit's three turns — south-west cut, the climb, and the
  // launch onto the mined top row.
  70: [
    (5, 3, Direction.left),
    (5, 0, Direction.up),
    (0, 0, Direction.right),
  ],
  // ----- World 6 (71–91): rotating arrows. -----
  // 71: the DOWN arrow at the top of column 2 bounces the dot back into the
  // rotor for a second pass — by then it has turned up → right, into the exit.
  71: [(0, 2, Direction.down)],
  72: [(1, 2, Direction.down), (2, 4, Direction.left)],
  73: [], // a hold and a portal pair only (below)
  // 74: the loop home after the gears have handed the dot back and forth —
  // the shield that carries it through the mine is below.
  74: [(5, 2, Direction.right), (5, 4, Direction.up)],
  75: [
    (2, 0, Direction.down),
    (2, 3, Direction.left),
    (5, 3, Direction.up),
  ],
  // 76 — the turn back west that feeds the dial's second face, the floor run
  // east off the drop it makes, and the climb up the stem the first blast
  // opened. The lift onto row 3 is the portal pair below.
  76: [
    (3, 6, Direction.left),
    (6, 2, Direction.right),
    (6, 5, Direction.up),
  ],
  // 77 — up to the dial, back east into its second face, and after the mine
  // blast the loop over the top that re-enters row 1 heading west.
  77: [
    (6, 1, Direction.up),
    (6, 3, Direction.up),
    (4, 1, Direction.right),
    (0, 3, Direction.right),
    (0, 5, Direction.down),
    (1, 5, Direction.left),
  ],
  // 78 — the one arrow starts the climb into the dial; the portal pair (below)
  // feeds it back for all four faces, and the fourth points at the gap.
  78: [(6, 3, Direction.up)],
  // 79 — the climb out of the floor, the turn east into the upper mine, the
  // drop down the hole it opens, and the run east into the corridor the second
  // blast makes.
  79: [
    (6, 1, Direction.up),
    (1, 1, Direction.right),
    (0, 4, Direction.down),
    (5, 2, Direction.right),
  ],
  // 80 — the drop into the square, then the two turns west that keep feeding
  // the tumblers. One of only five winning placements, all of which use every
  // piece and click all four dials.
  80: [
    (0, 1, Direction.down),
    (2, 6, Direction.left),
    (4, 4, Direction.left),
  ],
  // 81 — the turn into the ring's floor and the climb that feeds it. The hold
  // that times the last lane is below.
  81: [(2, 2, Direction.down), (3, 3, Direction.up)],
  // 82 — the climb out of the floor, the two turns that work the dial's faces,
  // and the last column once the patrol kill has blown (1,7) open. The portal
  // pair that reaches into the tower is below.
  82: [
    (7, 4, Direction.up),
    (4, 2, Direction.right),
    (3, 4, Direction.right),
    (1, 2, Direction.left),
    (3, 7, Direction.up),
  ],
  83: [(2, 2, Direction.down), (4, 3, Direction.up)],
  // 84 — the climb to the dial, the turn east into the row-4 patrol, and the
  // right arrow ON the second kill cell that turns the dot through the wall
  // its own blast opens.
  84: [
    (1, 3, Direction.right),
    (4, 4, Direction.right),
    (6, 4, Direction.up),
    (7, 3, Direction.up),
  ],
  85: [], // portals only — the level has no arrows at all (below)
  86: [
    (2, 3, Direction.down),
    (2, 4, Direction.up),
    (2, 6, Direction.left),
    (3, 6, Direction.up),
  ],
  87: [(1, 0, Direction.down)],
  88: [(5, 3, Direction.up)],
  89: [(6, 5, Direction.up)],
  90: [
    (0, 5, Direction.right),
    (4, 2, Direction.right),
    (4, 5, Direction.up),
  ],
  91: [
    (1, 4, Direction.down),
    (4, 1, Direction.right),
    (4, 7, Direction.down),
    (7, 4, Direction.up),
  ],
  92: [], // one-shot only (below)
  // ----- World 7 (93–110): one-shot arrows. The depth-pass levels hand
  // the routing arrows to the player, so several entries here are full
  // tours rather than single turns.
  // 93: the steady up that starts the climb on both laps.
  93: [(4, 2, Direction.up)],
  94: [], 95: [], 96: [],
  // 97: the player-built roof line over the extended lane.
  97: [(0, 2, Direction.right), (0, 5, Direction.down)],
  98: [], 99: [],
  // 100: the player-built tour — over the wall, west along the roof.
  100: [(0, 3, Direction.down), (0, 6, Direction.left)],
  101: [], 102: [],
  // 103: the steady up that bounces both of its arrivals.
  103: [(6, 4, Direction.up)],
  // 104: the floor turn and the mine climb feeding the portal.
  104: [(6, 2, Direction.right), (6, 4, Direction.up)],
  // 105: the bounce catcher, the floor hook and the relaunch climb.
  105: [
    (1, 1, Direction.down),
    (6, 1, Direction.left),
    (6, 0, Direction.up),
  ],
  // 106: the player-built roof route into the winding dial's machine.
  106: [(0, 2, Direction.right), (0, 4, Direction.down)],
  // 107: the bounce catcher and the relaunch climb.
  107: [(2, 5, Direction.down), (7, 0, Direction.up)],
  108: [],
  // 109: the top-row west turn that starts the fall home.
  109: [(0, 7, Direction.left)],
  110: [],
};

// Intended teleporter placements (World 5). Both ends of a pair, since the
// player places them — the level itself pins none.
// Intended teleporter placements (World 5). Both ends of each pair, in an
// order whose board-order pairing matches the intended solution.
const kSolutionTeleports = <int, List<(int, int)>>{
  51: [(4, 4), (0, 3)],
  52: [(4, 5), (5, 3)],
  53: [(0, 3), (6, 3)],
  54: [(0, 3), (6, 2)],
  55: [(0, 0), (6, 2)],
  56: [(5, 0), (5, 6)],
  57: [(7, 1), (5, 3), (3, 3), (0, 2)],
  58: [(7, 1), (2, 4)],
  // 59 — three pairs, in pairing order (a "crossing" wiring board-order can't
  // express): (0,1)<->(6,5), (0,7)<->(7,6), (2,5)<->(7,1). The dot warps
  // right→up→left through the maze into the exit.
  59: [(0, 1), (6, 5), (0, 7), (7, 6), (2, 5), (7, 1)],
  // 60 — pair 1 warps the dot out of the sealed pocket onto the south
  // track; pair 2 takes it from the east climb into the moat at (4,6).
  60: [(0, 1), (8, 3), (6, 8), (4, 6)],
  // 62 — one pair, crossed twice: in off the floor run, out of the ring.
  62: [(5, 2), (1, 4)],
  // 63 — the warp clock: skip the first patrol's column, land in the
  // second's row on the safe beat.
  63: [(5, 2), (5, 4)],
  // 66 — from the climb into the pen, on top of the patrol.
  66: [(5, 5), (3, 4)],
  // 70 — pair 1 into the pinned ring (and back out of it); pair 2 over the
  // mined top row. Placed in pair order.
  70: [(4, 3), (2, 7), (0, 1), (0, 3)],
  // ----- World 6. -----
  // 73 — off the floor the dial drops the dot onto, back in above the dial so
  // it takes a second pass. The east wall is mined either side of the door, so
  // the approach has to come through the dial rather than along the wall.
  73: [(5, 3), (2, 3)],
  // 76 — the lift: off the floor at (6,1) and onto row 3 at (3,0), still
  // heading east, so the pinned aura is crossed sideways and the mine above it
  // never comes into play.
  76: [(6, 1), (3, 0)],
  // 78 — the return line that feeds the dial: east into (5,6), back at (5,2)
  // for the down face, and the other way round for the left face.
  78: [(5, 2), (5, 6)],
  // 79 — two pairs, in pairing order. The first carries the dot from the end
  // of the top run back to the start of it; the second is crossed twice, once
  // southbound off the second blast and once eastbound into the corridor.
  79: [(0, 1), (1, 6), (3, 2), (5, 4)],
  // 80 — two pairs, in pairing order. The first drops the dot into the square
  // of tumblers; the second is the lift home, taken once the dials have been
  // clicked round to point at it.
  80: [(0, 3), (1, 1), (1, 3), (1, 6)],
  // 82 — the pair that solves the sealed tower: one end inside it at (1,0), so
  // the dot arrives on row 1 beside the aura without ever descending, and the
  // same pair carries it back out to the east field.
  82: [(1, 0), (4, 7)],
  // 84: the lift onto the floor below the start — the dot drops in at (4,7)
  // and comes out at (7,2) to begin the climb.
  84: [(4, 7), (7, 2)],
  // 85 — three pairs, in pairing order, on the 6x6 board. The shortest of the
  // winning wirings: an 11-cell path with all six ends on it.
  85: [(1, 2), (4, 0), (1, 5), (2, 1), (4, 2), (5, 4)],
  // 91 — out of the pocket onto the tower's ground floor.
  91: [(0, 1), (7, 0)],
  // ----- World 7. -----
  // 99 — the fall enters (5,2); the far end is pinned by the chimney walls.
  99: [(5, 2), (4, 5)],
  // 104 — entered north-bound at (0,4) off the climb, west-bound off the
  // roof; (5,6) emits into the chimney and then beside the door.
  104: [(0, 4), (5, 6)],
  // 110 — the roof run enters (0,6) west-bound; (3,4) emits into the
  // rotor's second face.
  110: [(0, 6), (3, 4)],
};

// Intended one-shot arrow placements (World 7). Same shape as `intended`, but
// these are the single-use arrows — the dot turns on one and it leaves the
// board, so the cell reads empty on any later pass.
const kSolutionOneShots = <int, List<(int, int, Direction)>>{
  // 92: the only cell the pinned arrow at (0,2) can catch. It fires the dot
  // north once; on the way back down the cell is empty and the dot falls
  // through it into the exit.
  92: [(2, 2, Direction.up)],
  // 93: the detour to the pinned shield, burned so lap two climbs through.
  93: [(2, 2, Direction.left)],
  // 94: the two batons — climb-and-fall, kick-east-and-fall.
  94: [(2, 2, Direction.up), (4, 2, Direction.right)],
  95: [(3, 3, Direction.up)],
  96: [(3, 3, Direction.up)],
  97: [(5, 2, Direction.up)],
  98: [(4, 3, Direction.up)],
  99: [(4, 2, Direction.up)],
  // 100: the interceptor that bounces the dial's first ray short of the
  // mine — the kit's permanent down is the roof-turn, this is the burn.
  100: [(2, 3, Direction.down)],
  // 101: the three fuses, burned left to right.
  101: [
    (3, 1, Direction.up),
    (3, 3, Direction.up),
    (3, 5, Direction.down),
  ],
  102: [(5, 2, Direction.up)],
  103: [(0, 4, Direction.down)],
  104: [(5, 2, Direction.up)],
  // 105: the burn that starts the double-bounce.
  105: [(2, 1, Direction.up)],
  106: [(5, 2, Direction.up)],
  // 107: the mid-board burn and the floor burn of the firebreak.
  107: [(5, 5, Direction.up), (7, 5, Direction.left)],
  // 108: the three bridges, each one rung lower.
  108: [
    (1, 2, Direction.up),
    (3, 4, Direction.up),
    (5, 6, Direction.up),
  ],
  109: [(2, 5, Direction.down)],
  110: [(7, 3, Direction.up)],
};

// Intended pause placements (World 4).
const kSolutionPauses = <int, List<(int, int)>>{
  41: [(2, 1)],
  42: [(3, 2)],
  43: [(1, 4), (5, 4)],
  44: [(2, 2), (5, 1)],
  45: [(6, 2), (6, 3)],
  46: [(4, 2), (6, 1)],
  47: [(2, 6), (7, 2)],
  48: [(0, 4), (0, 6), (2, 7), (4, 7), (6, 7)],
  49: [(4, 6)],
  50: [(4, 3)],
  // World 5 timing level (60 only; 59 was redesigned to portals-only).
  // 60: a single pause in the inner lane, holding for the re-phased patrol to
  // walk back into the keystone kill that blasts the core open.
  60: [(2, 5)],
  // ----- Master Trials. -----
  // 61: hold one cell beneath the patrol's lane while it sweeps past.
  61: [(1, 2)],
  63: [(5, 1)],
  // 65: wait out the pen patrol on the way up its column.
  65: [(4, 2)],
  // 67: one pause per crossing, each at its own doorstep.
  67: [(2, 3), (4, 2)],
  68: [(4, 2)],
  // 69: both waits stacked inside the shaft to catch the convoy's only gap.
  69: [(2, 3), (1, 3)],
  // ----- World 6. -----
  // 73: the gate cell, held so the column-2 patrol has walked past.
  73: [(3, 1)],
  // 81: held inside the ring so the last lap crosses the column-2 patrol on
  // the safe beat.
  81: [(2, 4)],
  // 84: three holds — two on row 1 waiting for the climber to reach (1,5),
  // one on row 5 that lands the dot on (4,5) as the row-4 patrol arrives.
  84: [(1, 4), (1, 5), (5, 4)],
  88: [(3, 5)],
  // 89: both waits inside the wheel's own spokes.
  89: [(3, 5), (4, 5)],
  90: [(3, 2)],
  91: [(7, 3)],
  // ----- World 7. -----
  // 95: the doorstep hold that shifts both lane crossings to safe beats.
  95: [(3, 2)],
  // 97: held for the short lane's beat before the climb.
  97: [(4, 2)],
  // 98: BOTH holds stacked inside the column, one between each lane pair.
  98: [(2, 3), (3, 3)],
  // 100: held on the col-6 climb to time the roof-lane ride.
  100: [(1, 6)],
  // 102: held inside the lane, where the patrol walks into the kill.
  102: [(2, 2)],
  106: [(3, 2)],
  // 109: held above the dial before the lane ride.
  109: [(3, 5)],
  // 110: the doorstep, held on both floor passes.
  110: [(7, 2)],
};

// Intended shield placements (World 3, plus World 4's chain-explosion levels).
const kSolutionShields = <int, List<(int, int)>>{
  21: [(3, 2)],
  22: [(2, 2)],
  23: [(3, 2)],
  24: [(1, 1)],
  25: [(4, 1), (3, 4)],
  26: [(2, 1), (4, 3)],
  27: [(2, 2), (3, 4)],
  28: [(0, 2)],
  29: [(1, 2), (3, 3)],
  30: [(1, 3), (3, 4), (5, 3)],
  35: [(4, 1)],
  36: [(4, 2)],
  37: [(5, 2), (5, 3)],
  38: [(5, 2)],
  39: [(3, 6), (6, 5)],
  44: [(4, 2)],
  45: [(2, 0), (2, 1)],
  46: [(2, 2), (5, 2)],
  47: [(4, 7), (5, 5)],
  // 48: one shield per mine — two in the floor run, one on the way home.
  48: [(0, 3), (7, 1), (7, 3)],
  49: [(3, 2)],
  50: [(0, 3), (4, 4)],
  // World 5 chain-explosion levels.
  53: [(6, 2)],
  54: [(6, 3)],
  58: [(2, 5)],
  // 60: the placed shield that blasts the track's mine-door (the second
  // aura, for the keystone kill, is the level's pinned shield at (8,7)).
  60: [(8, 4)],
  // ----- Master Trials. -----
  // 65: armour up before diving into the pen's fence mine.
  65: [(2, 3)],
  // 66: carried through the warp into the arrival-collision kill.
  66: [(6, 4)],
  // 68: one aura for the fence mine, one for the patrol at its new far end.
  68: [(3, 2), (4, 4)],
  // ----- World 6. -----
  // 74: armour picked up on the way to the mine the east gear sends it into.
  74: [(2, 1)],
  // 76: the second aura, collected on the climb up the stem. The first is
  // pinned at (3,1).
  76: [(5, 5)],
  // 77: collected on the dial's first bounce, spent on the mine that
  // demolishes the wall into the exit pocket.
  77: [(5, 3)],
  // 79: one aura per mine, each collected on the leg that runs into it — the
  // climb for the upper mine, the top run for the lower one.
  79: [(5, 1), (1, 5)],
  83: [(3, 3)],
  // 84: one aura per patrol — the first rammed into the row-4 sweep, the
  // second collected on the way up to meet the climber at the wall.
  84: [(2, 3), (6, 2)],
  87: [(3, 4)],
  // ----- World 7. -----
  // 96: the one approach cell before the turn — armour for the ceiling mine.
  96: [(3, 2)],
  // 102: the aura the climb spends on the mine at (4,2).
  102: [(5, 1)],
};

/// One placement from a level's recorded solution: which cell, and what goes
/// there.
class HintPlacement {
  const HintPlacement(this.r, this.c, this.element);

  final int r;
  final int c;
  final PlacedElement element;
}

/// The recorded solution for [level], flattened into the order hints reveal it.
///
/// Teleporters come first and keep their recorded order, because they pair by
/// placement order — revealing one half of a pair before the other, or out of
/// sequence, would wire the portals differently from the solution that was
/// verified. The rest follow in toolkit groups.
List<HintPlacement> recordedSolution(int level) {
  final out = <HintPlacement>[];

  var portal = 0;
  for (final (r, c) in kSolutionTeleports[level] ?? const <(int, int)>[]) {
    out.add(HintPlacement(
      r,
      c,
      PlacedElement(
        type: PlacedType.teleporter,
        tool: ToolType.teleporter,
        portalIndex: portal++,
      ),
    ));
  }
  for (final (r, c, dir) in kSolutionArrows[level] ?? const <(int, int, Direction)>[]) {
    out.add(HintPlacement(
      r,
      c,
      PlacedElement(
        type: PlacedType.arrow,
        tool: dir.arrowTool,
        direction: dir,
      ),
    ));
  }
  for (final (r, c, dir) in kSolutionOneShots[level] ?? const <(int, int, Direction)>[]) {
    // One-shots are ordinary arrows to the simulator; the tool is what marks
    // them as spent after a single use.
    out.add(HintPlacement(
      r,
      c,
      PlacedElement(
        type: PlacedType.arrow,
        tool: dir.oneShotTool,
        direction: dir,
      ),
    ));
  }
  for (final (r, c) in kSolutionShields[level] ?? const <(int, int)>[]) {
    out.add(HintPlacement(
      r,
      c,
      const PlacedElement(type: PlacedType.shield, tool: ToolType.shield),
    ));
  }
  for (final (r, c) in kSolutionPauses[level] ?? const <(int, int)>[]) {
    out.add(HintPlacement(
      r,
      c,
      const PlacedElement(type: PlacedType.pause, tool: ToolType.pause),
    ));
  }
  return out;
}
