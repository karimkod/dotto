// The toolkit tiles must show the SAME icons the board paints, not text stand-ins
// for them: a tile is a preview of the piece you are about to place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/widgets/game_grid.dart';
import 'package:dotto/widgets/game_toolbar.dart';

void main() {
  const tools = [
    ToolType.arrowUp,
    ToolType.arrowRight,
    ToolType.arrowDown,
    ToolType.arrowLeft,
    ToolType.shield,
    ToolType.pause,
    ToolType.teleporter,
  ];

  Future<void> pumpToolbar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GameToolbar(
          tools: tools,
          counts: {for (final t in tools) t: 2},
          selected: ToolType.arrowUp,
          onSelect: (_) {},
          enabled: true,
          tileKeys: {for (final t in tools) t: GlobalKey()},
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('every tile draws its piece rather than typing it', (tester) async {
    await pumpToolbar(tester);

    expect(find.byType(ArrowGlyph), findsNWidgets(4));
    expect(find.byType(ShieldGlyph), findsOneWidget);
    expect(find.byType(PauseGlyph), findsOneWidget);
    expect(find.byType(PortalGlyph), findsOneWidget);

    // The old text icons are gone. The tiles keep their word labels (UP, SHIELD
    // …), which is what the tests drive drags from, so only the symbols count.
    for (final glyph in ['↑', '→', '↓', '←', '❚❚', '◎', '🛡']) {
      expect(find.text(glyph), findsNothing,
          reason: 'a tile is still showing the "$glyph" character');
    }
    for (final t in tools) {
      expect(find.text(t.label), findsOneWidget);
    }
  });

  testWidgets('each arrow tile points the way its piece will', (tester) async {
    await pumpToolbar(tester);
    final dirs =
        tester.widgetList<ArrowGlyph>(find.byType(ArrowGlyph)).map((g) => g.dir);
    expect(dirs, [
      Direction.up,
      Direction.right,
      Direction.down,
      Direction.left,
    ]);
  });

  // The ghost that follows the finger is the same set of icons: if it drew the
  // piece differently, the piece would change shape as it landed.
  testWidgets('the drag ghost draws the same icons', (tester) async {
    for (final (tool, matcher) in [
      (ToolType.arrowLeft, find.byType(ArrowGlyph)),
      (ToolType.shield, find.byType(ShieldGlyph)),
      (ToolType.pause, find.byType(PauseGlyph)),
      (ToolType.teleporter, find.byType(PortalGlyph)),
    ]) {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: DragGhost(tool: tool)))));
      await tester.pump();
      expect(matcher, findsOneWidget, reason: 'the $tool ghost');
      expect(find.byType(Text), findsNothing,
          reason: 'the $tool ghost is still drawing text');
    }
  });
}
