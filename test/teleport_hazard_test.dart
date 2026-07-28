// A teleport must not launder the dot past a hazard. Landing at the far end of
// a portal faces the same checks as a normal step: a patrol, a gap or a static
// mine underfoot still resolves — die, or (with a shield) survive and
// chain-explode. Regression tests for the "teleport onto a hazard" bug, where
// the far end's hazards were skipped and only the exit was checked.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

void main() {
  const shield = PlacedElement(
      type: PlacedType.shield, tool: ToolType.shield, direction: null);

  group('teleport onto a static destroyer', () {
    // (0,0) heading right -> (0,1) portal entrance -> warps to (2,2), a mine.
    // Heading is preserved (right), so a survivor would run (2,3)->(2,4) exit.
    const level = LevelData(
      id: 990,
      size: 5,
      title: 'teleport onto a mine',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(2, 4),
      destroyers: [Pos(2, 2)],
      teleporters: [TeleporterPair(Pos(0, 1), Pos(2, 2))],
      toolkit: [],
    );

    test('without a shield the dot dies on the mine', () {
      final res = simulateDetailed(level, const {});
      expect(res.outcome, SimOutcome.lose);
      expect(res.cause, DeathCause.destroyer,
          reason: 'the destination mine must kill the dot after the jump');
    });

    test('tracePath agrees it is not a valid path', () {
      expect(tracePath(level, const {}), isNull);
    });
  });

  test('teleport onto a destroyer WITH a shield survives + chain-explodes', () {
    // The shield picked up at (0,1) is spent on the destination mine at (2,2),
    // whose blast demolishes the adjacent wall at (2,3) — the only way through
    // to the exit. A win therefore proves BOTH the survival and the chain.
    const level = LevelData(
      id: 992,
      size: 5,
      title: 'shielded teleport onto a mine',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(2, 4),
      walls: [Pos(2, 3)], // blown open only by the chain explosion
      destroyers: [Pos(2, 2)],
      teleporters: [TeleporterPair(Pos(0, 2), Pos(2, 2))],
      toolkit: [ToolkitEntry(ToolType.shield, 1)],
    );

    // Shield sits at (0,1), on the run up to the portal entrance at (0,2).
    expect(simulate(level, {0 * 5 + 1: shield}), SimOutcome.win,
        reason: 'the shield absorbs the mine and the blast opens the wall');

    // Control: without the shield the same jump dies on the mine.
    final bare = simulateDetailed(level, const {});
    expect(bare.outcome, SimOutcome.lose);
    expect(bare.cause, DeathCause.destroyer);
  });

  test('teleport onto a gap kills the dot', () {
    const level = LevelData(
      id: 993,
      size: 5,
      title: 'teleport into the void',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(2, 4),
      gaps: [Pos(2, 2)],
      teleporters: [TeleporterPair(Pos(0, 1), Pos(2, 2))],
      toolkit: [],
    );
    final res = simulateDetailed(level, const {});
    expect(res.outcome, SimOutcome.lose);
    expect(res.cause, DeathCause.gap,
        reason: 'a gap at the destination is fatal, same as stepping into one');
  });

  test('teleport onto a patrol kills the dot', () {
    // The patrol starts at (2,3) heading left; on tick 1 it steps to (2,2) just
    // as the dot warps there, so it catches the dot as it materialises.
    const level = LevelData(
      id: 994,
      size: 5,
      title: 'teleport into a patrol',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(2, 4),
      teleporters: [TeleporterPair(Pos(0, 1), Pos(2, 2))],
      movers: [MovingDestroyer(2, 3, horizontal: true, dir: -1)],
      toolkit: [],
    );
    final res = simulateDetailed(level, const {});
    expect(res.outcome, SimOutcome.lose);
    expect(res.cause, DeathCause.patrol,
        reason: 'a patrol occupying the destination catches the dot');
  });
}
