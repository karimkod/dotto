// ignore_for_file: avoid_print
// Solver check for all 50 levels — run with: dart run tool/check_levels.dart
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
  for (var n = from; n <= 50; n++) {
    final lvl = levelDataFor(n);
    if (lvl == null) continue;
    final total = toolkitTotal(lvl);
    // Moving destroyers => timing matters => brute solver is the source of truth.
    final usesBrute = lvl.movers.isNotEmpty;
    final sols = usesBrute ? solveAll(lvl) : pathSolve(lvl);
    final minP = sols.isEmpty
        ? -1
        : sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
    final tight = minP == total;
    final unique = sols.length == 1;
    print('L$n "${lvl.title}" ${lvl.size}x${lvl.size}: '
        '${usesBrute ? "[brute] " : ""}'
        'sols=${sols.length}${sols.length >= 256 ? "+" : ""} '
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
