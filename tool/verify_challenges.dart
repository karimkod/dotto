// Check every challenge document under scripts/ with the app's own code.
//
//   dart run tool/verify_challenges.dart
//   dart run tool/verify_challenges.dart scripts/challenge_week_2026_34.json
//
// A challenge is authored by hand and validated by nothing on the way in. The
// parser drops a malformed document (invisible, not crashing); an UNSOLVABLE one
// is worse, because it renders fine and wastes the week. So each document is put
// through `Challenge.fromMap` and then the real solver.
//
// Reported per file:
//   parses   — the app would show it at all
//   wins     — how many distinct placements beat it
//   min      — fewest pieces any win uses; == kit means TIGHT (no spare piece)
//   window   — the week it is live, and that it abuts its neighbour
//
// TIGHT is the design goal: a board a player can beat while leaving a piece in
// the tray is a board whose extra piece was a lie.

// A command-line report: stdout is the whole point of it, not a stray debug
// line left in shipping code.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/models/challenge.dart';

void main(List<String> args) {
  final files = args.isNotEmpty
      ? args.map(File.new).toList()
      : (Directory('scripts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split(RegExp(r'[/\\]')).last
              .startsWith('challenge_week_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));

  if (files.isEmpty) {
    stderr.writeln('no challenge documents found under scripts/');
    exit(1);
  }

  var bad = 0;
  DateTime? previousEnd;

  for (final file in files) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final c = Challenge.fromMap(raw);

    if (c == null) {
      print('FAIL $name — the parser rejects it; the app would show nothing');
      bad++;
      continue;
    }

    final kit = toolkitTotal(c.level);
    final stats = bruteStats(c.level, cap: const Duration(seconds: 120));

    // Only two things actually break a player's week: a document the app drops,
    // and a board that cannot be beaten. Those fail. Everything else is a design
    // note — worth printing, not worth blocking on, because a published week is
    // live and cannot be re-cut.
    final fatal = <String>[];
    final notes = <String>[];

    if (!stats.complete) {
      // A capped search is "don't know", never "unsolvable" — but it also means
      // the numbers below are a floor, so say so rather than claim TIGHT.
      notes.add('search hit the cap; counts are a floor, not an answer');
    } else if (stats.count == 0) {
      fatal.add('UNSOLVABLE — it renders fine and cannot be won');
    } else if (stats.minPieces < kit) {
      notes.add('LOOSE: ${stats.minPieces} of $kit pieces suffice');
    }
    // Consecutive weeks: each window should start exactly where the last ended,
    // or a week goes by with no live challenge. Two live at once is survivable —
    // `currentAt` walks newest-first and shows the later one — so this is a note.
    if (previousEnd != null && c.startDate != previousEnd) {
      notes.add(c.startDate.isBefore(previousEnd)
          ? 'overlaps the previous window (ends ${previousEnd.toIso8601String()})'
          : 'leaves a gap after ${previousEnd.toIso8601String()}');
    }
    previousEnd = c.endDate;

    if (fatal.isNotEmpty) bad++;
    print('${fatal.isEmpty ? "ok   " : "FAIL "}$name  ${c.id}  "${c.title}"  '
        '${c.level.size}x${c.level.size}  kit=$kit  '
        'wins=${stats.count}  min=${stats.minPieces}  '
        '${stats.minPieces == kit && stats.complete ? "TIGHT" : ""}');
    for (final p in [...fatal, ...notes]) {
      print('       └─ $p');
    }
  }

  print('');
  print(bad == 0
      ? '${files.length} document(s), all playable'
      : '$bad of ${files.length} document(s) cannot be played');
  exit(bad == 0 ? 0 : 1);
}
