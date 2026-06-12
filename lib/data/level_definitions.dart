import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Playable level definitions, keyed by level number. Mirrors the HTML
/// prototype. More levels will be ported in over time.
const Map<int, LevelData> levelDefinitions = {
  // Level 1 — teach arrows. 4x4. Dot runs right along the bottom row; place
  // the single Up arrow at (3,3) so it turns up the right edge into the exit.
  1: LevelData(
    id: 1,
    size: 4,
    title: 'Level 1',
    tip: 'You have one Up arrow. Place it where the dot should turn '
        'toward the exit.',
    start: StartSpec(3, 0, Direction.right),
    exit: Pos(0, 3),
    toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
  ),
};

/// Returns the definition for a level number, or null if not yet built.
LevelData? levelDataFor(int number) => levelDefinitions[number];
