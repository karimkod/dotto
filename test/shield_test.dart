// Verifies the Shield mechanic in the authoritative simulator: a shielded dot
// survives one destroyer (which is consumed), an unshielded dot dies, and the
// shield is strictly single-use.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

PlacedElement _shield() => const PlacedElement(
      type: PlacedType.shield,
      tool: ToolType.shield,
      direction: null,
    );

void main() {
  // start (0,0)→right, exit (0,3), a destroyer at (0,2).
  LevelData oneDestroyer() => LevelData(
        id: 900,
        size: 4,
        title: 'shield-1',
        tip: '',
        start: const StartSpec(0, 0, Direction.right),
        exit: const Pos(0, 3),
        destroyers: const [Pos(0, 2)],
        toolkit: const [ToolkitEntry(ToolType.shield, 1)],
      );

  test('a shielded dot survives the destroyer and reaches the exit', () {
    final level = oneDestroyer();
    expect(simulate(level, {0 * 4 + 1: _shield()}), SimOutcome.win);
  });

  test('without a shield the dot dies on the destroyer', () {
    final level = oneDestroyer();
    expect(simulate(level, {}), SimOutcome.lose);
  });

  test('the shield is single-use — a second destroyer still kills', () {
    // start (0,0)→right, exit (0,4), destroyers at (0,2) and (0,3).
    final level = LevelData(
      id: 901,
      size: 5,
      title: 'shield-2',
      tip: '',
      start: const StartSpec(0, 0, Direction.right),
      exit: const Pos(0, 4),
      destroyers: const [Pos(0, 2), Pos(0, 3)],
      toolkit: const [ToolkitEntry(ToolType.shield, 1)],
    );
    // Shield at (0,1) saves the dot at (0,2) but it dies at (0,3).
    expect(simulate(level, {0 * 5 + 1: _shield()}), SimOutcome.lose);
  });

  test('a shield does not protect against a gap', () {
    final level = LevelData(
      id: 902,
      size: 4,
      title: 'shield-gap',
      tip: '',
      start: const StartSpec(0, 0, Direction.right),
      exit: const Pos(0, 3),
      gaps: const [Pos(0, 2)],
      toolkit: const [ToolkitEntry(ToolType.shield, 1)],
    );
    expect(simulate(level, {0 * 4 + 1: _shield()}), SimOutcome.lose);
  });

  test('chain explosion clears the wall adjacent to the destroyer', () {
    // start (2,0)→right, exit (2,5), destroyer (2,2) with a wall at (2,3).
    final level = LevelData(
      id: 903,
      size: 6,
      title: 'chain',
      tip: '',
      start: const StartSpec(2, 0, Direction.right),
      exit: const Pos(2, 5),
      destroyers: const [Pos(2, 2)],
      walls: const [Pos(2, 3)],
      toolkit: const [ToolkitEntry(ToolType.shield, 1)],
    );
    // Shield at (2,1): the hit on (2,2) demolishes the adjacent wall (2,3).
    expect(simulate(level, {2 * 6 + 1: _shield()}), SimOutcome.win);
  });

  test('chain explosion does NOT clear a non-adjacent wall', () {
    // Same, but the wall is at (2,4) — two cells from the destroyer (2,2), so it
    // is not demolished and the dot dies on it even when shielded.
    final level = LevelData(
      id: 904,
      size: 6,
      title: 'chain-far',
      tip: '',
      start: const StartSpec(2, 0, Direction.right),
      exit: const Pos(2, 5),
      destroyers: const [Pos(2, 2)],
      walls: const [Pos(2, 4)],
      toolkit: const [ToolkitEntry(ToolType.shield, 1)],
    );
    expect(simulate(level, {2 * 6 + 1: _shield()}), SimOutcome.lose);
  });

  // A vertical patrol on column 2 ends on (0,2) exactly as the dot arrives there
  // (mover start (2,2) heading up: row 2→1→0 over ticks 0,1; the dot reaches
  // (0,2) on tick 1), so without a shield it is a guaranteed patrol kill.
  LevelData onePatrol() => LevelData(
        id: 905,
        size: 4,
        title: 'patrol-1',
        tip: '',
        start: const StartSpec(0, 0, Direction.right),
        exit: const Pos(0, 3),
        movers: const [MovingDestroyer(2, 2, horizontal: false, dir: -1)],
        toolkit: const [ToolkitEntry(ToolType.shield, 1)],
      );

  test('a shield protects against a moving destroyer (patrol)', () {
    expect(simulate(onePatrol(), {0 * 4 + 1: _shield()}), SimOutcome.win);
  });

  test('without a shield a patrol kills the dot', () {
    final result = simulateDetailed(onePatrol(), {});
    expect(result.outcome, SimOutcome.lose);
    expect(result.cause, DeathCause.patrol);
  });

  test('a shield destroys the patrol AND chain-explodes its adjacent wall', () {
    // The patrol ends on (0,2); a wall blocking the path sits beside it at
    // (0,3) — off the mover's column so it doesn't pen the patrol in. Shielding
    // the hit at (0,2) must demolish (0,3), letting the dot continue to (0,4).
    final level = LevelData(
      id: 906,
      size: 5,
      title: 'patrol-chain',
      tip: '',
      start: const StartSpec(0, 0, Direction.right),
      exit: const Pos(0, 4),
      walls: const [Pos(0, 3)],
      movers: const [MovingDestroyer(2, 2, horizontal: false, dir: -1)],
      toolkit: const [ToolkitEntry(ToolType.shield, 1)],
    );
    // Shield at (0,1): surviving the patrol at (0,2) chain-clears the (0,3) wall.
    expect(simulate(level, {0 * 5 + 1: _shield()}), SimOutcome.win);
  });
}
