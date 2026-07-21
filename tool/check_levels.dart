// ignore_for_file: avoid_print
// Solver check for every defined level — run with: dart run tool/check_levels.dart
// Levels with moving destroyers (World 4) need the timing-aware BRUTE-FORCE
// solver; the rest use the fast path-based solver. Prints distinct-solution
// count, min pieces vs toolkit total, tightness, and a sample solution.

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';

void main(List<String> args) {
  final from = int.tryParse(
        args.firstWhere((a) => int.tryParse(a) != null, orElse: () => ''),
      ) ??
      1;
  // Walk the definitions themselves rather than a hardcoded range, so adding a
  // level can never leave it silently unchecked.
  for (final n in levelDefinitions.keys.toList()..sort()) {
    if (n < from) continue;
    final lvl = levelDefinitions[n]!;
    final total = toolkitTotal(lvl);
    // Moving destroyers or pause/teleporter pieces => timing matters => the
    // brute solver is the source of truth.
    final usesBrute = needsBruteSolver(lvl);
    // Both solvers follow the dot's path, so even level 45's 9-piece toolkit is
    // tractable — no level needs skipping any more.
    final sols = usesBrute ? enumerateSolutions(lvl) : pathSolve(lvl);
    // Only pathSolve caps its results; pathSolveAll counts are exact.
    final capped = !usesBrute && sols.length >= 256;
    final minP = sols.isEmpty
        ? -1
        : sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
    final tight = minP == total;
    final unique = sols.length == 1;
    print('L$n "${lvl.title}" ${lvl.size}x${lvl.size}: '
        '${usesBrute ? "[brute] " : ""}'
        'sols=${sols.length}${capped ? "+" : ""} '
        'min=$minP total=$total '
        '${sols.isEmpty ? "*** UNSOLVABLE ***" : (tight ? "TIGHT" : "*** LOOSE ***")} '
        '${unique ? "UNIQUE" : "(${sols.length} solutions)"}');
    if (sols.isNotEmpty) {
      final s = (sols.toList()..sort((a, b) => a.length.compareTo(b.length)))
          .first;
      final desc = (s.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) =>
              '(${e.key ~/ lvl.size},${e.key % lvl.size},${e.value.direction?.name ?? e.value.type.name})')
          .join(' ');
      print('   sample: $desc');
    }
  }
}
