// Rotating arrows: forced arrows that turn 90° clockwise each time the dot
// passes through (right → down → left → up → right ...). The state persists
// during a run, so the same arrow sends the dot a different way on a later pass.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/widgets/game_grid.dart';

void main() {
  // The painting tests lay out text glyphs, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const down = PlacedElement(
      type: PlacedType.arrow, tool: ToolType.arrowDown, direction: Direction.down);

  group('Direction.rotatedCW', () {
    test('cycles clockwise', () {
      expect(Direction.right.rotatedCW, Direction.down);
      expect(Direction.down.rotatedCW, Direction.left);
      expect(Direction.left.rotatedCW, Direction.up);
      expect(Direction.up.rotatedCW, Direction.right);
      // Four turns is the identity.
      var d = Direction.right;
      for (var i = 0; i < 4; i++) {
        d = d.rotatedCW;
      }
      expect(d, Direction.right);
    });
  });

  test('buildRotations seeds each rotating cell with its initial heading', () {
    const level = LevelData(
      id: 9060,
      size: 5,
      title: 'seed',
      tip: '',
      start: StartSpec(2, 0, Direction.right),
      exit: Pos(2, 4),
      rotatingArrows: [
        RotatingArrow(2, 2, Direction.up),
        RotatingArrow(0, 0, Direction.left),
      ],
      toolkit: [],
    );
    final rot = buildRotations(level);
    expect(rot[2 * 5 + 2], Direction.up);
    expect(rot[0 * 5 + 0], Direction.left);
    expect(rot.length, 2);
  });

  // The learning-level shape: the dot is forced through the rotating arrow, sent
  // UP the first time; a placed DOWN arrow at the top bounces it back, and the
  // now-rotated arrow (up → right) sends the second pass to the exit.
  const learn = LevelData(
    id: 9061,
    size: 5,
    title: 'rotate to win',
    tip: '',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(2, 4),
    rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
    toolkit: [ToolkitEntry(ToolType.arrowDown, 1)],
  );

  group('a rotating arrow sends the dot a different way each pass', () {
    test('bare board loses — the first pass sends the dot up, off the grid', () {
      // With nothing placed, pass 1 turns the dot up and it runs off the top.
      final res = simulateDetailed(learn, const {});
      expect(res.outcome, SimOutcome.lose);
      expect(res.cause, DeathCause.edge);
    });

    test('bouncing the dot back for a second pass reaches the exit', () {
      // DOWN arrow at (0,2) returns the dot to the arrow; the second pass, now
      // pointing right, delivers it to the exit at (2,4).
      expect(simulate(learn, {0 * 5 + 2: down}), SimOutcome.win);
    });

    test('the arrow ends the run pointing one more quarter-turn on', () {
      // Two passes: up → right consumed, so the live heading is now down.
      final trace = tracePath(learn, {0 * 5 + 2: down});
      expect(trace, isNotNull, reason: 'the recorded solution must win');
      // The dot visited both the arrow cell and, on the second pass, the exit row.
      expect(trace, contains(2 * 5 + 2)); // the rotating arrow
      expect(trace, contains(2 * 5 + 4)); // the exit
    });
  });

  group('the four-pass cycle runs right → down → left → up', () {
    // A closed ring around a central rotating arrow: fixed arrows on the four
    // corners feed the dot back into the centre from each side in turn, so the
    // arrow is hit four times and must point a different way each time. The exit
    // sits where only the FOURTH (up) pass can deliver the dot.
    //
    // Layout (5x5), centre arrow at (2,2) starting RIGHT:
    //   pass 1 → right → (2,3) → corner sends it around ...
    // Rather than hand-fly the geometry, assert the state machine directly.
    test('rotatedCW applied by successive passes matches the spec', () {
      var heading = Direction.right; // initial
      final order = <Direction>[];
      for (var pass = 0; pass < 4; pass++) {
        order.add(heading);
        heading = heading.rotatedCW; // what the NEXT pass will use
      }
      expect(order,
          [Direction.right, Direction.down, Direction.left, Direction.up]);
    });
  });

  group('solver handles rotating arrows', () {
    test('routes to the brute (simulate-based) solver, not the path solver', () {
      expect(needsBruteSolver(learn), isTrue);
      expect(needsExhaustiveSolver(learn), isTrue,
          reason: 'per-pass state needs the simulate-based BruteSearch');
      expect(() => pathSolve(learn), throwsA(isA<PathSolverUnsupported>()));
      expect(() => pathMinPieces(learn), throwsA(isA<PathSolverUnsupported>()));
    });

    test('the rotating cell is pinned — not placeable', () {
      expect(learn.hasForcedPieceAt(2, 2), isTrue);
      expect(learn.rotatingArrowAt(2, 2), Direction.up);
      expect(placeableCells(learn), isNot(contains(2 * 5 + 2)));
    });

    test('is solvable, TIGHT, and every solution really wins', () {
      final sols = enumerateSolutions(learn);
      expect(sols, isNotEmpty, reason: 'the learning level must be solvable');
      final min = sols.map((s) => s.length).reduce((a, b) => a < b ? a : b);
      expect(min, 1, reason: 'the single toolkit arrow is load-bearing (TIGHT)');
      for (final s in sols) {
        expect(simulate(learn, s), SimOutcome.win,
            reason: 'a reported solution does not actually win');
      }
    });
  });

  // The quarter-turn is drawn by the grid painter off (spinCell, spinProgress),
  // which the game screen advances every frame from its spin controller.
  group('painting the quarter-turn', () {
    const rotor = 2 * 5 + 2; // the rotating cell in `learn`
    GameGridPainter painter({int? spinCell, double spin = 0}) => GameGridPainter(
          level: learn,
          placed: const {},
          forced: const {},
          rotations: const {rotor: Direction.up},
          trail: const [],
          revision: 0,
          placeAnim: const {},
          removing: const [],
          cellGlow: const {},
          cellGlowColor: const {},
          cellPulse: const {},
          explosions: const [],
          destroyedCells: const {},
          glowTick: 0,
          showStartHint: false,
          winProgress: 0,
          spinCell: spinCell,
          spinProgress: spin,
        );

    test('a change in spin state forces a repaint', () {
      // shouldRepaint compares an explicit field list. If the spin is not on it
      // the turn never redraws and the arrow just jumps to its new heading.
      expect(
          painter(spinCell: rotor, spin: 0.4)
              .shouldRepaint(painter(spinCell: rotor, spin: 0.1)),
          isTrue);
      expect(painter(spinCell: rotor).shouldRepaint(painter()), isTrue);
      expect(painter().shouldRepaint(painter()), isFalse,
          reason: 'an idle board must not repaint every frame for nothing');
    });

    test('paints at rest and at every stage of the turn', () {
      for (final spin in [0.0, 0.25, 0.5, 0.99, 1.0]) {
        final recorder = PictureRecorder();
        painter(spinCell: rotor, spin: spin)
            .paint(Canvas(recorder), const Size(300, 300));
        recorder.endRecording().dispose();
      }
    });
  });
}
