import 'package:flutter/foundation.dart';

import '../models/grid_cell.dart';
import '../models/level_data.dart';
import 'level_solver.dart';

/// Keeping the designer responsive while the solver runs. A brute-force sweep
/// can take seconds, so it must never occupy the UI thread uninterrupted.
///
/// Two strategies, because the platforms differ:
///
///  * **Native** — hand the whole job to a real isolate via [compute]. True
///    parallelism; the UI thread never touches the search. All request/result
///    types here are plain Dart objects (ints, enums, const-able models), so
///    they copy across the isolate boundary.
///  * **Web** — there are no isolates, and [compute] runs the callback inline,
///    which is what froze Find Toolkit. Instead the search runs on the main
///    thread in short slices, yielding to the event loop between them so the
///    browser can paint. Slower in total, but the UI stays alive.
///
/// [kIsWeb] picks between them at the two public entry points; everything below
/// that is shared, so the two paths can't drift apart in behaviour.

/// The designer's "Solver report": can the level be solved, in how many ways,
/// and does it use the whole toolkit.
class SolveReport {
  const SolveReport({
    required this.solutions,
    required this.minPieces,
    required this.total,
    required this.usedBrute,
    required this.capped,
    this.overBudget = false,
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

  /// True when the level was never searched because an exhaustive sweep would
  /// cost more than [kMaxBrutePlacements]. Everything else in the report is
  /// meaningless in that case — the answer is "don't know", not "no".
  final bool overBudget;

  bool get solvable => solutions > 0;

  /// No solution wastes a piece — the design goal for every authored level.
  bool get tight => minPieces == total;
}

/// The path-solver half of a report — shared by the sync and paced paths.
SolveReport _pathReport(LevelData level) {
  final sols = pathSolve(level);
  return SolveReport(
    solutions: sols.length,
    minPieces: sols.isEmpty ? -1 : pathMinPieces(level),
    total: toolkitTotal(level),
    usedBrute: false,
    capped: sols.length >= 256,
  );
}

SolveReport _bruteReport(LevelData level, BruteStats stats) => SolveReport(
      solutions: stats.count,
      minPieces: stats.minPieces,
      total: toolkitTotal(level),
      usedBrute: true,
      capped: false,
      // The search ran; it just may not have finished. Predicting cost up front
      // is not possible for a path search, so we measure instead of guessing.
      overBudget: !stats.complete,
    );

/// Solve [level] with whichever solver is correct for it. Pure and sendable;
/// call [solveLevelAsync] from the UI.
SolveReport solveLevel(LevelData level) {
  if (!needsBruteSolver(level)) return _pathReport(level);
  return _bruteReport(level, bruteStats(level));
}

/// [solveLevel] in event-loop-friendly slices, for web.
Future<SolveReport> solveLevelPaced(LevelData level) async {
  if (needsBruteSolver(level)) {
    return _bruteReport(level, await bruteStatsPaced(level));
  }
  await Future<void>.delayed(Duration.zero); // let the spinner paint first
  return _pathReport(level);
}

/// Solve [level] without blocking the UI: a real isolate on native, sliced
/// cooperative work on web.
Future<SolveReport> solveLevelAsync(LevelData level) =>
    kIsWeb ? solveLevelPaced(level) : compute(solveLevel, level);

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

/// What to do with one candidate toolkit. Deciding this in one place keeps the
/// sync and paced searches honest about each other.
enum _Route {
  /// Doesn't meet the user's constraints.
  filtered,

  /// Static layout, no blind pieces — the fast path solver answers it.
  path,

  /// Timing hazards or pause/teleporter pieces: only the brute force is correct.
  brute,
}

/// Per-candidate ceiling. The sweep tries hundreds of toolkits, so no single one
/// may run as long as [kSolveCap] — a candidate that overruns is reported as
/// skipped rather than silently treated as unsolvable.
const Duration _kCandidateCap = Duration(seconds: 3);

_Route _routeFor(
  FindToolkitRequest req,
  Map<ToolType, int> kit,
  LevelData level,
) {
  if (req.mustShield && (kit[ToolType.shield] ?? 0) == 0) return _Route.filtered;
  if (req.mustPause && (kit[ToolType.pause] ?? 0) == 0) return _Route.filtered;
  return needsBruteSolver(level) ? _Route.brute : _Route.path;
}

/// A candidate that solves the layout using its whole toolkit, or null.
FindToolkitResult? _accept(
    Map<ToolType, int> kit, int index, int count, int minPieces, int skipped) {
  final total = kit.values.fold(0, (a, b) => a + b);
  if (count == 0 || minPieces != total) return null;
  return FindToolkitResult(
    kit: kit,
    solutions: count,
    cursor: index + 1, // resume past this one next time
    skipped: skipped,
  );
}

/// Search [FindToolkitRequest.candidates] for the first solvable, tight toolkit.
/// Pure and sendable; call [findToolkitAsync] from the UI.
FindToolkitResult findToolkit(FindToolkitRequest req) {
  var skipped = 0;
  var i = req.cursor;
  for (; i < req.candidates.length; i++) {
    final kit = req.candidates[i];
    final level = levelWithToolkit(req.base, kit);
    final int count;
    final int minPieces;
    switch (_routeFor(req, kit, level)) {
      case _Route.filtered:
        continue;
      case _Route.brute:
        final stats = bruteStats(level, cap: _kCandidateCap);
        if (!stats.complete) {
          skipped++; // inconclusive — never report it as unsolvable
          continue;
        }
        count = stats.count;
        minPieces = stats.minPieces;
      case _Route.path:
        final sols = pathSolve(level);
        count = sols.length;
        minPieces = sols.isEmpty ? -1 : pathMinPieces(level);
    }
    final hit = _accept(kit, i, count, minPieces, skipped);
    if (hit != null) return hit;
  }
  return FindToolkitResult(
      kit: null, solutions: 0, cursor: i, skipped: skipped);
}

/// Reports how far the paced search has got, so the UI can show progress.
typedef SearchProgress = void Function(int checked, int total);

/// [findToolkit] run cooperatively: the brute-force sweeps are sliced and the
/// loop yields between candidates, so the event loop keeps turning and the
/// spinner keeps animating. Used on web, where [compute] runs inline.
Future<FindToolkitResult> findToolkitPaced(
  FindToolkitRequest req, {
  SearchProgress? onProgress,
}) async {
  var skipped = 0;
  var i = req.cursor;
  for (; i < req.candidates.length; i++) {
    final kit = req.candidates[i];
    final level = levelWithToolkit(req.base, kit);
    final route = _routeFor(req, kit, level);
    // Report every candidate, including the ones we pass over — with a
    // constraint like "must include Pause" most kits are filtered, and a
    // counter that only moved on evaluated ones would look frozen.
    onProgress?.call(i + 1, req.candidates.length);
    final int count;
    final int minPieces;
    switch (route) {
      case _Route.filtered:
        continue;
      case _Route.brute:
        // Sliced internally — a single big candidate can't hog the thread.
        final stats = await bruteStatsPaced(level, cap: _kCandidateCap);
        if (!stats.complete) {
          skipped++; // inconclusive — never report it as unsolvable
          continue;
        }
        count = stats.count;
        minPieces = stats.minPieces;
      case _Route.path:
        final sols = pathSolve(level);
        count = sols.length;
        minPieces = sols.isEmpty ? -1 : pathMinPieces(level);
        // The path solver isn't sliced (it's quick), so breathe between kits.
        await Future<void>.delayed(Duration.zero);
    }
    final hit = _accept(kit, i, count, minPieces, skipped);
    if (hit != null) return hit;
  }
  return FindToolkitResult(
      kit: null, solutions: 0, cursor: i, skipped: skipped);
}

/// Search for a toolkit without blocking the UI: a real isolate on native,
/// sliced cooperative work on web.
Future<FindToolkitResult> findToolkitAsync(
  FindToolkitRequest req, {
  SearchProgress? onProgress,
}) =>
    kIsWeb
        ? findToolkitPaced(req, onProgress: onProgress)
        : compute(findToolkit, req);
