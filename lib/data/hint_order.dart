// Which piece a hint gives away first.
//
// Hints used to reveal the recorded solution in the order it is written down —
// portals, then arrows in route order, then one-shots, shields and pauses. So
// the first hint on most levels was the first turn out of the start: the one
// piece the board had already shown the player, since pressing Play crashes the
// dot right beside it. Players paid for an ad and got what they knew.
//
// A piece is easy to find when something on the board points at it:
//   * Play does. Without the piece, the dot crashes on the very next cell, so
//     the place to put it is where the crash is.
//   * The exit does. The last turn before the exit is the one you work out
//     backwards from the exit itself.
// And it is easy to place when it has room: a shield or a pause that would win
// from several cells is hard to get wrong once you know what it is for.
//
// So hints go, in tiers:
//   1. unique pieces the crash does not point at — furthest from it first;
//   2. pieces that would also win from another cell, discounted by how many;
//   3. pieces Play shows you (the dot crashes right beside them);
//   4. the final turn into the exit;
//   5. pieces the recorded solution does not actually need.
//
// Everything is read off the simulator, so a level's ranking follows its design
// with nothing extra to keep in sync.

import '../engine/simulator.dart';
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';
import 'level_hints.dart';

/// [solution] reordered for hints: the piece a player is least likely to find
/// on their own comes first. See the top of this file for the rule.
///
/// A solution that does not win on [level] — a designer preview sharing a
/// campaign level's id, say — comes back unchanged: there is no route to rank
/// it against.
List<HintPlacement> hintOrder(LevelData level, List<HintPlacement> solution) {
  if (solution.length < 2) return solution;
  final n = level.size;
  int key(HintPlacement p) => p.r * n + p.c;
  Map<int, PlacedElement> board(Iterable<HintPlacement> ps) =>
      {for (final p in ps) key(p): p.element};

  final full = board(solution);
  final route = <int>[];
  if (simulateDetailed(level, full, trail: route).outcome != SimOutcome.win) {
    return solution;
  }
  final pieceCells = full.keys.toSet();
  // Where on the route the dot first meets each piece. A piece it never meets
  // sorts as the deepest; it is also, necessarily, one the level wins without.
  int met(HintPlacement p) {
    final i = route.indexOf(key(p));
    return i < 0 ? route.length : i;
  }

  HintPlacement? partnerOf(HintPlacement p) {
    final i = p.element.portalIndex;
    if (i == null) return null;
    for (final q in solution) {
      if (q.element.portalIndex == (i ^ 1)) return q;
    }
    return null;
  }

  final free = [
    for (var k = 0; k < n * n; k++)
      if (level.baseTypeAt(k ~/ n, k % n) == CellType.empty &&
          !level.hasForcedPieceAt(k ~/ n, k % n) &&
          !pieceCells.contains(k))
        k,
  ];

  // How many cells the dot keeps going after [cell] on [b] before the run
  // ends, counted so that "crashes on the very next cell" is 0 whether it hit a
  // wall (and never left [cell]) or rolled onto a mine (and died on it).
  int runOn(Map<int, PlacedElement> b, int cell) {
    final t = <int>[];
    final res = simulateDetailed(level, b, trail: t);
    final at = t.indexOf(cell);
    if (at < 0 || res.outcome == SimOutcome.win) return 0;
    // Out of ticks: the dot circles and never crashes, so nothing points at
    // the piece at all. As far from it as a run can get.
    if (res.cause == null) return t.length - at;
    var m = t.length - 1 - at;
    if (res.cause == DeathCause.destroyer ||
        res.cause == DeathCause.gap ||
        res.cause == DeathCause.patrol) {
      m--;
    }
    return m < 0 ? 0 : m;
  }

  final ranked = <_Ranked>[];
  for (var i = 0; i < solution.length; i++) {
    final p = solution[i];
    final rest = {...full}..remove(key(p));
    final turns = p.element.type == PlacedType.arrow ||
        p.element.type == PlacedType.bouncer ||
        p.element.type == PlacedType.teleporter;

    // How far past the piece the dot gets before the board complains.
    //
    // A piece that turns the dot is judged the way a player meets it: every
    // piece before it on the route in place, nothing after, so the dot carries
    // straight on where the turn should be. A shield or a pause changes nothing
    // where it stands — its absence only shows at the mine or the patrol it was
    // for — so it is judged with everything else down.
    final int gap;
    if (turns) {
      final partner = partnerOf(p);
      var entry = met(p);
      if (partner != null && met(partner) < entry) entry = met(partner);
      if (entry >= route.length) {
        gap = 0;
      } else {
        final before = solution.where(
            (q) => q != p && q != partner && met(q) < entry);
        gap = runOn(board(before), route[entry]);
      }
    } else {
      gap = runOn(rest, key(p));
    }

    // Other cells the same piece would win from, everything else unchanged.
    var room = 0;
    for (final cell in free) {
      if (simulate(level, {...rest, cell: p.element}) == SimOutcome.win) {
        room++;
      }
    }

    final unneeded = simulate(level, rest) == SimOutcome.win;
    final at = met(p);
    // The last piece the dot meets before the exit, when it is the one that
    // points it there: nothing the player places comes after it.
    final last = turns &&
        at < route.length &&
        !route.skip(at + 1).any((k) => k != key(p) && pieceCells.contains(k));

    var tier = 1;
    var score = gap.toDouble();
    if (unneeded) {
      tier = 5;
    } else if (last) {
      tier = 4;
    } else if (gap == 0) {
      tier = 3;
    } else if (room > 0) {
      tier = 2;
      score = gap / (room + 1);
    }
    if (tier > 2) score = 0;
    ranked.add(_Ranked(p, tier, score, room, at, i));
  }

  ranked.sort((a, b) {
    if (a.tier != b.tier) return a.tier.compareTo(b.tier);
    if (a.score != b.score) return b.score.compareTo(a.score);
    if (a.room != b.room) return a.room.compareTo(b.room);
    // Deeper first: the further along the route, the more of the level the
    // player has to have right before Play can show them anything there.
    if (a.met != b.met) return b.met.compareTo(a.met);
    return a.index.compareTo(b.index);
  });
  return [for (final r in ranked) r.placement];
}

class _Ranked {
  _Ranked(this.placement, this.tier, this.score, this.room, this.met,
      this.index);
  final HintPlacement placement;
  final int tier;
  final double score;
  final int room;
  final int met;
  final int index;
}
