// The teleporter mechanic: entering either end of a pair moves the dot to the
// other end, keeping its heading.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

void main() {
  // Row 2 is split by a full-height wall in column 3. The only crossing is the
  // pinned portal pair, so reaching the exit proves the dot teleported.
  const crossing = LevelData(
    id: 960,
    size: 6,
    title: 'crossing',
    tip: '',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 5),
    walls: [
      Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
    ],
    teleporters: [TeleporterPair(Pos(2, 1), Pos(2, 4))],
    toolkit: [],
  );

  group('a fixed pair', () {
    test('carries the dot across an otherwise impassable wall', () {
      expect(simulate(crossing, const {}), SimOutcome.win);
    });

    test('without the pair the same board is a dead end', () {
      const noPortal = LevelData(
        id: 961,
        size: 6,
        title: 'no portal',
        tip: '',
        start: StartSpec(2, 0, Direction.right),
        exit: Pos(2, 5),
        walls: [
          Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
        ],
        toolkit: [],
      );
      expect(simulateDetailed(noPortal, const {}).cause, DeathCause.wall);
    });

    test('the heading survives the jump', () {
      // Entering the near end heading UP must leave the far end heading UP —
      // if the heading were reset or reversed this could not reach (0,4).
      const upward = LevelData(
        id: 962,
        size: 6,
        title: 'upward',
        tip: '',
        start: StartSpec(5, 1, Direction.up),
        exit: Pos(0, 4),
        walls: [
          Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
        ],
        teleporters: [TeleporterPair(Pos(2, 1), Pos(2, 4))],
        toolkit: [],
      );
      expect(simulate(upward, const {}), SimOutcome.win);
    });

    test('works from either end', () {
      // Same board, entered from the far side running left.
      const reverse = LevelData(
        id: 963,
        size: 6,
        title: 'reverse',
        tip: '',
        start: StartSpec(2, 5, Direction.left),
        exit: Pos(2, 0),
        walls: [
          Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
        ],
        teleporters: [TeleporterPair(Pos(2, 4), Pos(2, 1))],
        toolkit: [],
      );
      expect(simulate(reverse, const {}), SimOutcome.win);
    });

    test('tracePath counts the far end as visited', () {
      final visited = tracePath(crossing, const {});
      expect(visited, isNotNull);
      expect(visited, contains(2 * 6 + 1), reason: 'near end');
      expect(visited, contains(2 * 6 + 4), reason: 'far end');
    });
  });

  group('entrance / exit', () {
    PlacedElement portal(int i) => const PlacedElement(
            type: PlacedType.teleporter,
            tool: ToolType.teleporter,
            direction: null)
        .withPortalIndex(i);

    test('placements alternate entrance, exit, entrance, exit', () {
      expect(portal(0).isPortalEntrance, isTrue, reason: '1st is an entrance');
      expect(portal(1).isPortalEntrance, isFalse, reason: '2nd is an exit');
      expect(portal(2).isPortalEntrance, isTrue);
      expect(portal(3).isPortalEntrance, isFalse);
    });

    test('the nth entrance and the nth exit share a pair', () {
      expect(portal(0).portalPair, 0);
      expect(portal(1).portalPair, 0);
      expect(portal(2).portalPair, 1);
      expect(portal(3).portalPair, 1);
    });

    test('index pairing beats board order', () {
      // Indices deliberately disagree with cell order: the 1st entrance (index
      // 0) sits at a HIGH cell and its exit (index 1) at a low one. Board-order
      // pairing would mis-link these once a second pair exists.
      const bare = LevelData(
        id: 970,
        size: 4,
        title: 'ordering',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(3, 3),
        toolkit: [ToolkitEntry(ToolType.teleporter, 4)],
      );
      final links = buildTeleportLinks(bare, {
        14: portal(0), // pair 0 entrance
        2: portal(1), // pair 0 exit
        13: portal(2), // pair 1 entrance
        5: portal(3), // pair 1 exit
      });
      expect(links[14], 2, reason: 'pair 0 links across, not to its neighbour');
      expect(links[2], 14);
      expect(links[13], 5, reason: 'pair 1 likewise');
      expect(links[5], 13);
    });

    test('travel works both ways — the distinction is cosmetic', () {
      // Enter via the EXIT end and the dot still comes out at the entrance.
      const level = LevelData(
        id: 971,
        size: 6,
        title: 'both ways',
        tip: '',
        start: StartSpec(2, 5, Direction.left),
        exit: Pos(2, 0),
        walls: [
          Pos(0, 3), Pos(1, 3), Pos(2, 3), Pos(3, 3), Pos(4, 3), Pos(5, 3),
        ],
        toolkit: [ToolkitEntry(ToolType.teleporter, 2)],
      );
      // Entrance (index 0) is on the LEFT of the wall; the dot meets the exit
      // (index 1) first, coming from the right.
      expect(
          simulate(level, {2 * 6 + 1: portal(0), 2 * 6 + 4: portal(1)}),
          SimOutcome.win);
    });

    test('pair indices drive colouring for both ends', () {
      const bare = LevelData(
        id: 972,
        size: 4,
        title: 'colours',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(3, 3),
        toolkit: [ToolkitEntry(ToolType.teleporter, 4)],
      );
      final pairs = buildPortalPairs(bare, {
        1: portal(0),
        9: portal(1),
        2: portal(2),
        10: portal(3),
      });
      expect(pairs[1], pairs[9], reason: 'pair 0 shares a colour');
      expect(pairs[2], pairs[10], reason: 'pair 1 shares a colour');
      expect(pairs[1], isNot(pairs[2]), reason: 'and the pairs differ');
    });
  });

  group('link table', () {
    test('pairs both directions for a fixed pair', () {
      final links = buildTeleportLinks(crossing, const {});
      expect(links[2 * 6 + 1], 2 * 6 + 4);
      expect(links[2 * 6 + 4], 2 * 6 + 1);
    });

    test('player-placed teleporters pair two at a time', () {
      const bare = LevelData(
        id: 964,
        size: 4,
        title: 'placed',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(3, 3),
        toolkit: [ToolkitEntry(ToolType.teleporter, 2)],
      );
      const t = PlacedElement(
          type: PlacedType.teleporter,
          tool: ToolType.teleporter,
          direction: null);
      final links = buildTeleportLinks(bare, const {1: t, 9: t});
      expect(links[1], 9);
      expect(links[9], 1);
    });

    test('an odd teleporter is left inert rather than half-linked', () {
      const bare = LevelData(
        id: 965,
        size: 4,
        title: 'odd',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(3, 3),
        toolkit: [ToolkitEntry(ToolType.teleporter, 1)],
      );
      const t = PlacedElement(
          type: PlacedType.teleporter,
          tool: ToolType.teleporter,
          direction: null);
      expect(buildTeleportLinks(bare, const {1: t}), isEmpty);
    });
  });

  group('board integration', () {
    test('portal cells are pinned, not placeable', () {
      expect(crossing.hasForcedPieceAt(2, 1), isTrue);
      expect(crossing.hasForcedPieceAt(2, 4), isTrue);
      expect(placeableCells(crossing), isNot(contains(2 * 6 + 1)));
      expect(placeableCells(crossing), isNot(contains(2 * 6 + 4)));
    });

    test('both ends report the same pair index, for shared colouring', () {
      expect(crossing.teleporterPairAt(2, 1), 0);
      expect(crossing.teleporterPairAt(2, 4), 0);
      expect(crossing.teleporterPairAt(0, 0), -1);
    });

    test('a teleporter level routes to the timing-aware solver', () {
      expect(needsBruteSolver(crossing), isTrue);
      expect(() => pathSolve(crossing), throwsA(isA<PathSolverUnsupported>()));
    });

    test('reachability follows the link to the far side', () {
      // Without the jump, everything past the wall would look unreachable.
      final reach = reachableCells(crossing);
      expect(reach, contains(2 * 6 + 4), reason: 'far end');
      expect(reach, contains(2 * 6 + 5), reason: 'the exit beyond it');
    });
  });

  group('level 51', () {
    final lvl = levelDataFor(51)!;

    test('hands the player the portal pair and nothing else', () {
      expect(lvl.teleporters, isEmpty, reason: 'nothing pre-placed');
      final kit = {for (final e in lvl.toolkit) e.type: e.count};
      expect(kit[ToolType.teleporter], 2, reason: 'exactly one pair');
      expect(kit.length, 1, reason: 'just the pair — the portal in isolation');
    });

    test('needs the exhaustive solver, and the path search refuses it', () {
      // The partner portal is by definition somewhere the dot has not been, so
      // the path search cannot place it and must not silently say "unsolvable".
      expect(needsExhaustiveSolver(lvl), isTrue);
      expect(() => pathSolveAll(lvl), throwsA(isA<PathSolverUnsupported>()));
    });

    test('is solvable and every solution uses the whole pair', () {
      final sols = enumerateSolutions(lvl);
      expect(sols, isNotEmpty);
      final min = sols.map((s) => s.length).reduce((a, b) => a < b ? a : b);
      expect(min, 2, reason: 'both portals are required');
      for (final s in sols) {
        expect(simulate(lvl, s), SimOutcome.win);
      }
    });

    test('cannot be solved without building the pair', () {
      // No pieces at all — the dot runs the bottom row and off the edge.
      expect(simulate(lvl, const {}), SimOutcome.lose);
    });
  });
}
