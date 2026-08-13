// The published challenge document, checked with the app's own code.
//
// A challenge is authored by hand and validated by nothing on the way in: a
// malformed one is silently dropped (invisible, not crashing) and an unsolvable
// one is worse — it renders, and the player cannot win. Neither failure shows
// up until it is live in front of everyone, so the document that actually ships
// is read off disk here and put through the real parser and the real solver.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/grid_cell.dart';


void main() {
  final file = File('scripts/challenge_week_2026_33.json');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('the document parses at all', () {
    // fromMap returns null for anything it cannot trust, so this doubles as
    // the check that every field name matches what the app reads.
    expect(Challenge.fromMap(raw), isNotNull,
        reason: 'the app would drop this document and show no challenge');
  });

  test('it carries the intended metadata', () {
    final c = Challenge.fromMap(raw)!;
    expect(c.id, 'week_2026_33');
    expect(c.title, 'Arrow Maze');
    expect(c.reward, ChallengeReward.hint);
  });

  test('it is live this week and ends a week later', () {
    final c = Challenge.fromMap(raw)!;
    // The window it was published for. Aug 13 is inside it.
    expect(c.isActiveAt(DateTime.utc(2026, 8, 13)), isTrue);
    expect(c.isActiveAt(DateTime.utc(2026, 8, 11, 23)), isFalse);
    expect(c.hasEndedAt(DateTime.utc(2026, 8, 19)), isTrue);
  });

  test('the board is the one that was designed', () {
    final level = Challenge.fromMap(raw)!.level;
    expect(level.size, 5);
    expect(level.start.r, 0);
    expect(level.start.c, 0);
    expect(level.start.dir, Direction.right);
    // Pos has no ==, so compare the coordinates rather than the instance.
    expect(level.exit.r, 4);
    expect(level.exit.c, 4);
    // Two forced arrows, and four pieces to place.
    expect(level.forcedArrows.length, 2);
    expect(level.toolkit.fold<int>(0, (n, e) => n + e.count), 4);
  });

  test('and it can actually be beaten', () {
    // The one failure the parser cannot catch. Unsolvable is the worst
    // outcome of the three: it looks fine and wastes everyone's week.
    final level = Challenge.fromMap(raw)!.level;
    expect(isSolvable(level), isTrue);
  });
}
