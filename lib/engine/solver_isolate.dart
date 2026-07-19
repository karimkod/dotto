import 'package:flutter/foundation.dart';

import '../models/grid_cell.dart';
import '../models/level_data.dart';
import 'level_solver.dart';

/// Off-thread wrappers around [level_solver]. A brute-force solve can run for
/// seconds, which freezes the designer if it happens on the UI thread, so every
/// entry point here hands the work to [compute].
///
/// All request/result types are plain Dart objects (ints, enums, and const-able
/// models), so they can be copied across the isolate boundary. Note that on
/// Flutter web there are no isolates and [compute] runs the callback inline —
/// correct, just not concurrent.

/// The designer's "Solver report": can the level be solved, in how many ways,
/// and does it use the whole toolkit.
class SolveReport {
  const SolveReport({
    required this.solutions,
    required this.minPieces,
    required this.total,
    required this.usedBrute,
    required this.capped,
  });

  /// Number of distinct solutions found ([capped] when the search hit its cap).
  final int solutions;

  /// Fewest pieces any solution uses, or -1 when unsolvable.
  final int minPieces;

  /// Pieces in the toolkit.
  final int total;

  /// True when the timing-aware brute force answered (see [needsBruteSolver]).
  final bool usedBrute;

  /// True when [solutions] is a floor, not an exact count.
  final bool capped;

  bool get solvable => solutions > 0;

  /// No solution wastes a piece — the design goal for every authored level.
  bool get tight => minPieces == total;
}

/// Solve [level] with whichever solver is correct for it. Pure and sendable;
/// call [solveLevelAsync] from the UI.
SolveReport solveLevel(LevelData level) {
  final brute = needsBruteSolver(level);
  final sols = brute ? solveAll(level) : pathSolve(level);
  final minPieces = sols.isEmpty
      ? -1
      : brute
          ? sols.map((m) => m.length).reduce((a, b) => a < b ? a : b)
          : pathMinPieces(level);
  return SolveReport(
    solutions: sols.length,
    minPieces: minPieces,
    total: toolkitTotal(level),
    usedBrute: brute,
    capped: !brute && sols.length >= 256,
  );
}

/// [solveLevel] on a background isolate.
Future<SolveReport> solveLevelAsync(LevelData level) =>
    compute(solveLevel, level);

/// [base] with a different toolkit swapped in — the layout is fixed while the
/// toolkit search varies the pieces.
LevelData levelWithToolkit(LevelData base, Map<ToolType, int> kit) => LevelData(
      id: base.id,
      size: base.size,
      title: base.title,
      tip: base.tip,
      start: base.start,
      exit: base.exit,
      walls: base.walls,
      destroyers: base.destroyers,
      gaps: base.gaps,
      forcedArrows: base.forcedArrows,
      movers: base.movers,
      toolkit: [for (final e in kit.entries) ToolkitEntry(e.key, e.value)],
    );

/// One "Find Toolkit" search: walk [candidates] from [cursor] for the first kit
/// that makes [base] solvable AND tight.
class FindToolkitRequest {
  const FindToolkitRequest({
    required this.base,
    required this.candidates,
    required this.cursor,
    required this.mustShield,
    required this.mustPause,
  });

  final LevelData base;
  final List<Map<ToolType, int>> candidates;

  /// Where to resume — lets "Try Another" continue past the last hit.
  final int cursor;
  final bool mustShield;
  final bool mustPause;
}

class FindToolkitResult {
  const FindToolkitResult({
    required this.kit,
    required this.solutions,
    required this.cursor,
    required this.skipped,
  });

  /// The winning toolkit, or null when the search ran out of candidates.
  final Map<ToolType, int>? kit;
  final int solutions;

  /// Resume point for the next "Try Another".
  final int cursor;

  /// Candidates passed over because solving them would cost more than
  /// [kMaxBrutePlacements]. Surfaced in the UI so a bounded search never reads
  /// as an exhaustive one.
  final int skipped;
}

/// Search [FindToolkitRequest.candidates] for the first solvable, tight toolkit.
/// Pure and sendable; call [findToolkitAsync] from the UI.
FindToolkitResult findToolkit(FindToolkitRequest req) {
  final placeable = placeableCells(req.base).length;
  var skipped = 0;
  var i = req.cursor;
  for (; i < req.candidates.length; i++) {
    final kit = req.candidates[i];
    // Constraint filter: skip toolkits that don't match the user's requirements.
    if (req.mustShield && (kit[ToolType.shield] ?? 0) == 0) continue;
    if (req.mustPause && (kit[ToolType.pause] ?? 0) == 0) continue;
    final total = kit.values.fold(0, (a, b) => a + b);
    final level = levelWithToolkit(req.base, kit);
    final int minPieces;
    final int count;
    if (needsBruteSolver(level)) {
      // Timing hazards or pause/teleporter pieces — only the brute force is
      // correct here, so bound it rather than let one candidate run away.
      if (bruteForcePlacements(placeable, kit.values) > kMaxBrutePlacements) {
        skipped++;
        continue;
      }
      final sols = solveAll(level);
      if (sols.isEmpty) continue;
      count = sols.length;
      minPieces = sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
    } else {
      final sols = pathSolve(level);
      if (sols.isEmpty) continue;
      count = sols.length;
      minPieces = pathMinPieces(level);
    }
    if (minPieces == total) {
      return FindToolkitResult(
        kit: kit,
        solutions: count,
        cursor: i + 1, // resume past this one next time
        skipped: skipped,
      );
    }
  }
  return FindToolkitResult(
      kit: null, solutions: 0, cursor: i, skipped: skipped);
}

/// [findToolkit] on a background isolate.
Future<FindToolkitResult> findToolkitAsync(FindToolkitRequest req) =>
    compute(findToolkit, req);
