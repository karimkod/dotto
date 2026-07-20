// Proves the paced solver actually frees the event loop.
//
// This is the whole point of the sliced search: on web there are no isolates,
// so `compute()` runs inline and a brute-force sweep freezes the UI. Run this
// against a real browser with:
//
//   flutter test --platform chrome test/solver_pacing_test.dart
//
// The check is behavioural, not cosmetic: a periodic timer stands in for the
// UI's frame callbacks. If the search hogs the thread the timer cannot fire, so
// a high tick count is direct evidence that other work — including painting —
// got a turn.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';

/// Counts how many times a 4ms timer fires while [action] runs.
Future<int> ticksDuring(Future<void> Function() action) async {
  var ticks = 0;
  final timer =
      Timer.periodic(const Duration(milliseconds: 4), (_) => ticks++);
  await action();
  timer.cancel();
  return ticks;
}

void main() {
  // Level 45 is the heaviest authored level — a full sweep runs ~18s, so it is
  // the only one still long enough to expose a freeze now that the path search
  // finishes the rest in milliseconds. Both runs are capped so the test stays
  // quick; an incomplete result is fine here, since what is under test is the
  // event loop's behaviour, not the answer.
  final heavy = levelDataFor(45)!;
  const cap = Duration(milliseconds: 1200);

  test('the paced sweep lets the event loop run; the sync one does not',
      () async {
    final pacedTicks =
        await ticksDuring(() => bruteStatsPaced(heavy, cap: cap));
    final syncTicks =
        await ticksDuring(() async => bruteStats(heavy, cap: cap));

    // The synchronous sweep occupies the thread start to finish, so the timer
    // is starved (browsers coalesce the missed firings into one).
    expect(syncTicks, lessThanOrEqualTo(2),
        reason: 'the unsliced sweep should block the event loop');
    // The paced sweep hands the loop a turn every slice.
    expect(pacedTicks, greaterThan(10),
        reason: 'the sliced sweep must let other work run — got $pacedTicks '
            'ticks vs $syncTicks for the blocking sweep');
  });

  test('pacing does not change the answer', () async {
    // A level that completes well inside the cap, so both runs are exhaustive
    // and their answers must match exactly.
    final level = levelDataFor(43)!;
    final paced = await bruteStatsPaced(level);
    final sync = bruteStats(level);
    expect(paced.complete && sync.complete, isTrue);
    expect(paced.count, sync.count);
    expect(paced.minPieces, sync.minPieces);
  });

  test('no single slice overruns its budget by much', () async {
    const slice = Duration(milliseconds: 12);
    final search = PathSearch(heavy, (_) {});
    var worst = Duration.zero;
    var slices = 0;
    while (slices < 40) {
      final sw = Stopwatch()..start();
      final done = search.runSlice(slice);
      sw.stop();
      if (sw.elapsed > worst) worst = sw.elapsed;
      slices++;
      if (done) break;
      await Future<void>.delayed(Duration.zero);
    }
    // The clock is only checked every 256 leaves, so a slice can overshoot a
    // little — but nowhere near the seconds-long stall it replaces.
    expect(worst, lessThan(const Duration(milliseconds: 250)),
        reason: 'worst slice was $worst');
  });
}
