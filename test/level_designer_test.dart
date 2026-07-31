// Smoke + interaction tests for the dev level designer screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/screens/game_screen.dart';
import 'package:dotto/screens/level_designer_screen.dart';
import 'package:dotto/widgets/game_grid.dart';

void main() {
  testWidgets('Level designer renders palette, toolkit and buttons',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LevelDesignerScreen()));
    await tester.pump();

    expect(find.text('Level Designer'), findsOneWidget);
    // Palette chips.
    expect(find.text('Wall'), findsOneWidget);
    expect(find.text('Destroyer'), findsOneWidget);
    expect(find.text('Shield'), findsOneWidget);
    // Toolkit counters.
    expect(find.text('◯ Shield'), findsOneWidget);
    // Action buttons.
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Export Dart'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('painting a cell and opening the solver report works',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LevelDesignerScreen()));
    await tester.pump();

    // Paint a cell (default tool = Wall) — should not throw.
    await tester.tap(find.byKey(const ValueKey('designerBoard')));
    await tester.pump();

    // Open the solver report dialog (scroll the button into view first).
    await tester.ensureVisible(find.text('Test'));
    await tester.pumpAndSettle();
    // The solver runs on a real isolate, so the tap has to happen in the real
    // async zone — fake-async pumping alone would never see it complete.
    await tester.runAsync(() async {
      await tester.tap(find.text('Test'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(find.text('Solver report'), findsOneWidget);
    expect(find.text('Solvable'), findsOneWidget);
    expect(find.text('Play it'), findsOneWidget);
  });

  testWidgets('Play launches the level without running the solver',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LevelDesignerScreen()));
    await tester.pump();

    await tester.ensureVisible(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    // The game screen animates continuously, so settle with fixed pumps rather
    // than pumpAndSettle (which would never see an idle frame).
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Straight to the board — no solver report in between.
    expect(find.text('Solver report'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('opens pre-loaded for editing an existing level',
      (tester) async {
    const lvl = LevelData(
      id: 7,
      size: 4,
      title: 'Edit Me',
      tip: '',
      start: StartSpec(3, 0, Direction.right),
      exit: Pos(0, 3),
      walls: [Pos(1, 2)],
      destroyers: [Pos(2, 1)],
      forcedArrows: [],
      toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
    );
    await tester.pumpWidget(const MaterialApp(
      home: LevelDesignerScreen(
        initialLevel: lvl,
        initialNumber: 7,
        initialDifficulty: Difficulty.hard,
      ),
    ));
    await tester.pump();

    // The title field is populated from the loaded level.
    expect(find.text('Edit Me'), findsOneWidget);
  });

  // _loadFromLevel copies each kind of level content into the editor's state.
  // Rotating arrows were missed when they were added, so opening a World 6 level
  // for editing silently dropped its rotors — and exporting from that session
  // would have written the level back out without them.
  testWidgets('editing a level keeps every pinned piece', (tester) async {
    const lvl = LevelData(
      id: 71,
      size: 5,
      title: 'Rotor',
      tip: '',
      start: StartSpec(2, 0, Direction.right),
      exit: Pos(2, 4),
      forcedArrows: [ForcedArrow(0, 0, Direction.down)],
      rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
      forcedShields: [Pos(4, 0)],
      forcedPauses: [Pos(4, 4)],
      toolkit: [ToolkitEntry(ToolType.arrowDown, 1)],
    );
    await tester.pumpWidget(const MaterialApp(
      home: LevelDesignerScreen(initialLevel: lvl, initialNumber: 71),
    ));
    await tester.pump();

    final grid = tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byKey(const ValueKey('designerBoard')),
            matching: find.byType(CustomPaint)))
        .map((p) => p.painter)
        .whereType<GameGridPainter>()
        .single;

    expect(grid.rotations, {2 * 5 + 2: Direction.up},
        reason: 'the rotating arrow must survive the trip into the designer');
    // The pinned pieces the designer already handled, so a future addition
    // cannot quietly drop one of these either.
    expect(grid.forced.keys, containsAll(<int>[0, 4 * 5 + 0, 4 * 5 + 4]));
    expect(grid.forced[0]!.direction, Direction.down);
  });
}
