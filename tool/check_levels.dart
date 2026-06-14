// ignore_for_file: avoid_print
// Quick solver check for World 1 exam levels — run with:
//   dart run tool/check_levels.dart
// Prints solvability, solution count, min pieces vs toolkit total, and a
// sample solution per level.

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';

void main() {
  for (var n = 11; n <= 15; n++) {
    final lvl = levelDataFor(n)!;
    final sols = solveAll(lvl);
    final total = toolkitTotal(lvl);
    final minP = minSolutionPieces(lvl);
    final tight = minP == total;
    print('L$n "${lvl.title}" ${lvl.size}x${lvl.size}: '
        'sols=${sols.length} min=$minP total=$total '
        '${tight ? "TIGHT" : "*** LOOSE ***"}');
    if (sols.isNotEmpty) {
      final s = sols.first;
      final desc = (s.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) =>
              '(${e.key ~/ lvl.size},${e.key % lvl.size},${e.value.direction!.name})')
          .join(' ');
      print('   sample: $desc');
    }
  }
}
