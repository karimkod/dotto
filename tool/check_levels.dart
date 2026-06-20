// ignore_for_file: avoid_print
// Solver check for all levels (World 1: 1–15, World 2: 16–30) — run with:
//   dart run tool/check_levels.dart
// Uses the fast path-based solver (scales to open grids) and prints
// solvability, distinct-solution count, min pieces vs toolkit total, and a
// sample solution per level. Pass `--brute` to also cross-check the slow
// brute-force solver on the smaller levels.

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';

void main(List<String> args) {
  final brute = args.contains('--brute');
  final from = int.tryParse(
        args.firstWhere((a) => int.tryParse(a) != null, orElse: () => ''),
      ) ??
      1;
  for (var n = from; n <= 30; n++) {
    final lvl = levelDataFor(n);
    if (lvl == null) continue;
    final total = toolkitTotal(lvl);
    final minP = pathMinPieces(lvl);
    final sols = pathSolve(lvl);
    final tight = minP == total;
    final unique = sols.length == 1;
    print('L$n "${lvl.title}" ${lvl.size}x${lvl.size}: '
        'sols=${sols.length}${sols.length >= 256 ? "+" : ""} '
        'min=$minP total=$total '
        '${tight ? "TIGHT" : "*** LOOSE ***"} '
        '${unique ? "UNIQUE" : "(${sols.length} solutions)"}');
    if (sols.isNotEmpty) {
      // Show the SHORTEST solution — reveals the unintended shortcut on a
      // loose level.
      final s = (sols.toList()..sort((a, b) => a.length.compareTo(b.length)))
          .first;
      final desc = (s.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) =>
              '(${e.key ~/ lvl.size},${e.key % lvl.size},${e.value.direction?.name ?? 'shield'})')
          .join(' ');
      print('   sample: $desc');
    }
    if (brute && lvl.size <= 7) {
      final bMin = minSolutionPieces(lvl);
      if (bMin != minP) {
        print('   *** PATH/BRUTE MISMATCH: brute min=$bMin path min=$minP ***');
      }
    }
  }
}
