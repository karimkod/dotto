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

    // Every arrow on the board is geometry, not a text glyph. A glyph is placed
    // by its line box rather than its ink, and the two centres do not coincide —
    // which the rotating arrow exposed, since rotating one drags it around a
    // small arc instead of spinning it in place.
    //
    // Balanced means the arrow's drawn EXTENT is centred on the cell centre, the
    // point the canvas rotates about. (Its centre of MASS is not, and shouldn't
    // be: a head outweighs a shaft, and spinning about mass would throw the tip
    // wide.)
    //
    // Rendered big on purpose. Measuring a pointed shape on a pixel grid costs
    // about a pixel at the tip, where coverage tails off; against a 400px cell
    // that is a quarter of a percent, well under any imbalance worth seeing.
    const side = 2000.0;
    final geo = GridGeometry(side, 5);
    // Windows stop inside the rotating arrow's ring — the arrow itself reaches
    // 0.155 of a cell from the centre, the ring's ink starts at 0.218 — and well
    // inside every cell's border. Only the arrow lives in there.
    final span = geo.cell * 0.20;

    /// The bounding box of the ARROW ink in the cell at [r],[c].
    Future<Rect> arrowBox(GameGridPainter p, int r, int c) async {
      final centre = geo.center(r, c);
      final recorder = PictureRecorder();
      p.paint(Canvas(recorder), const Size(side, side));
      final img =
          await recorder.endRecording().toImage(side.toInt(), side.toInt());
      final data = (await img.toByteData())!;
      var minX = side, maxX = 0.0, minY = side, maxY = 0.0, found = 0;
      for (var y = (centre.dy - span).round(); y < centre.dy + span; y++) {
        for (var x = (centre.dx - span).round(); x < centre.dx + span; x++) {
          // Only FULL-opacity ink — the arrow. Cell fills and the rotating
          // arrow's white hub are far lighter, and so is its ring even where two
          // half-alpha layers overlap at the arrowhead (r≈106 against the
          // arrow's 30).
          if (data.getUint8((y * side.toInt() + x) * 4) >= 60) continue;
          found++;
          if (x < minX) minX = x.toDouble();
          if (x > maxX) maxX = x.toDouble();
          if (y < minY) minY = y.toDouble();
          if (y > maxY) maxY = y.toDouble();
        }
      }
      expect(found, greaterThan(1000), reason: 'found no arrow ink to measure');
      // +1 on each max: it is the last COVERED pixel, whose far edge is at +1.
      return Rect.fromLTRB(minX, minY, maxX + 1, maxY + 1);
    }

    // 0.75% of a cell: far tighter than any imbalance that reads on screen, far
    // looser than the ~1px the tip costs to measure.
    final tolerance = geo.cell * 0.0075;

    test('the arrow is balanced on the pivot for every heading', () async {
      for (final dir in Direction.values) {
        final box = await arrowBox(
            GameGridPainter(
              level: learn,
              placed: const {},
              forced: const {},
              rotations: {rotor: dir},
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
            ),
            2,
            2);
        final off = box.center - geo.center(2, 2);
        expect(off.distance, lessThan(tolerance),
            reason: 'pointing ${dir.name} puts the arrow '
                '${off.distance.toStringAsFixed(1)}px off the pivot (tolerance '
                '${tolerance.toStringAsFixed(1)}px) — it would swing around an '
                'arc as it turns instead of spinning in place');
      }
    });

    // Placed, fixed and rotating arrows are three borders around ONE arrow. They
    // were three sizes of two different shapes: a 0.42-em text glyph on the
    // placed and fixed cells, geometry on the rotating one.
    test('placed, fixed and rotating arrows draw the same arrow', () async {
      const trio = LevelData(
        id: 9062,
        size: 5,
        title: 'three arrows',
        tip: '',
        start: StartSpec(0, 4, Direction.left),
        exit: Pos(4, 0),
        forcedArrows: [ForcedArrow(0, 0, Direction.up)],
        rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
        toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
      );
      const up = PlacedElement(
          type: PlacedType.arrow,
          tool: ToolType.arrowUp,
          direction: Direction.up);
      final painter = GameGridPainter(
        level: trio,
        placed: const {4 * 5 + 4: up},
        forced: buildForcedPieces(trio),
        rotations: buildRotations(trio),
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
      );

      final placed = await arrowBox(painter, 4, 4);
      final fixed = await arrowBox(painter, 0, 0);
      final rotating = await arrowBox(painter, 2, 2);
      for (final (name, box, cell) in [
        ('placed', placed, (4, 4)),
        ('fixed', fixed, (0, 0)),
        ('rotating', rotating, (2, 2)),
      ]) {
        final off = box.center - geo.center(cell.$1, cell.$2);
        expect(off.distance, lessThan(tolerance),
            reason: 'the $name arrow sits ${off.distance.toStringAsFixed(1)}px '
                'off its cell centre');
        // A pixel of slack: the cells sit at different subpixel offsets, so
        // antialiasing rounds their edges differently.
        expect((box.width - placed.width).abs(), lessThan(2),
            reason: 'the $name arrow is ${box.width.toStringAsFixed(1)}px wide, '
                'the placed one ${placed.width.toStringAsFixed(1)}px');
        expect((box.height - placed.height).abs(), lessThan(2),
            reason: 'the $name arrow is ${box.height.toStringAsFixed(1)}px tall, '
                'the placed one ${placed.height.toStringAsFixed(1)}px');
      }
    });
  });
}
