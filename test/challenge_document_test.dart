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
import 'package:dotto/models/level_data.dart';
import 'package:dotto/services/challenge_service.dart';


void main() {
  final file = File('scripts/challenge_week_2026_33.json');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  group('every published document', () {
    // docs/challenges-setup.md promises that a challenge JSON under scripts/
    // gets checked. It only held for the one file named above until the weeks
    // 34-43 batch was authored, which is exactly when it stopped being true —
    // so the promise is kept here by sweeping the directory instead.
    final files = Directory('scripts')
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('challenge_week_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    test('there are documents to check', () => expect(files, isNotEmpty));

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

      test('$name parses and can be beaten', () {
        final c = Challenge.fromMap(doc);
        expect(c, isNotNull,
            reason: 'the app would drop $name and show no challenge');
        // The one failure the parser cannot catch, and the worst of them: an
        // unsolvable board renders fine and wastes the whole week.
        expect(isSolvable(c!.level), isTrue,
            reason: '$name cannot be won by any placement');
      });
    }

    test('the windows run consecutively, newest last', () {
      final windows = [
        for (final f in files)
          Challenge.fromMap(
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)!
      ];
      for (final c in windows) {
        expect(c.endDate.isAfter(c.startDate), isTrue, reason: c.id);
      }
      // Weeks 34 onward were authored as one unbroken run, so each window has
      // to start where the last ended or a week goes by with nothing live.
      // week_2026_33 was published earlier on a Wednesday cadence and overlaps
      // week_2026_34 by two days, so the chain is checked from 34.
      final chained = windows.where((c) => c.id.compareTo('week_2026_34') >= 0)
          .toList();
      for (var i = 1; i < chained.length; i++) {
        expect(chained[i].startDate, chained[i - 1].endDate,
            reason: '${chained[i].id} does not abut ${chained[i - 1].id}');
      }
    });
  });

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

  group('the offline copy', () {
    // What the cache writes has to be readable by the same parser that reads
    // the published document, because on the next cold start it is read by
    // exactly that. Nothing checked it: the cache is written only after a
    // successful fetch, so a throw in the encoder cost the offline copy and
    // logged one line, and for a while the fetch was failing first and even
    // that line never appeared.

    test('every kind of piece survives being encoded', () {
      // The encoder names pieces from their enum. `.name` is not a member of
      // the enum — it comes from `extension EnumName on Enum` — so reaching it
      // through `dynamic` threw instead of returning a name, for every
      // toolkit, every time.
      const toolkit = [
        ToolkitEntry(ToolType.arrowLeft, 1),
        ToolkitEntry(ToolType.oneShotUp, 2),
        ToolkitEntry(ToolType.shield, 1),
        ToolkitEntry(ToolType.pause, 1),
        ToolkitEntry(ToolType.teleporter, 1),
      ];
      final encoded = ChallengeService.encodeLevelForTest(
        _challengeWith(toolkit),
      );

      final pieces = (encoded['pieces']! as List).cast<Map<String, Object?>>();
      expect(pieces, hasLength(5));
      // An arrow keeps its heading; a one-shot is an arrow that is spent,
      // named apart but still carrying a direction; the rest have none.
      expect(pieces[0], containsPair('type', 'arrow'));
      expect(pieces[0], containsPair('direction', 'left'));
      expect(pieces[1], containsPair('type', 'oneShot'));
      expect(pieces[1], containsPair('direction', 'up'));
      expect(pieces[1], containsPair('count', 2));
      expect(pieces[2], containsPair('type', 'shield'));
      expect(pieces[2], containsPair('direction', isNull));
      expect(pieces[3], containsPair('type', 'pause'));
      expect(pieces[4], containsPair('type', 'teleporter'));
    });

    test('static terrain survives the round trip', () {
      // The encoder writes cells as `{r, c}` now, matching what Firestore can
      // actually store. Week 33 has no terrain at all, so the round trip below
      // would pass just as well with the encoder writing nonsense here.
      final original = Challenge(
        id: 'week_terrain',
        title: 'Terrain',
        description: '',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 8),
        reward: ChallengeReward.none,
        level: const LevelData(
          id: -1,
          size: 5,
          title: 'Terrain',
          tip: '',
          start: StartSpec(0, 0, Direction.right),
          exit: Pos(4, 4),
          toolkit: [],
          walls: [Pos(1, 1), Pos(2, 2)],
          gaps: [Pos(3, 3)],
          destroyers: [Pos(3, 1)],
          teleporters: [TeleporterPair(Pos(0, 4), Pos(4, 0))],
        ),
      );

      final cached = jsonDecode(jsonEncode(
        ChallengeService.encodeLevelForTest(original),
      )) as Map<String, dynamic>;
      final reparsed = Challenge.fromMap({
        'id': original.id,
        'startDate': original.startDate.millisecondsSinceEpoch,
        'endDate': original.endDate.millisecondsSinceEpoch,
        'level': cached,
      })!.level;

      expect(reparsed.walls, hasLength(2));
      expect(reparsed.walls.first.r, 1);
      expect(reparsed.walls.first.c, 1);
      expect(reparsed.gaps, hasLength(1));
      expect(reparsed.destroyers, hasLength(1));
      expect(reparsed.teleporters, hasLength(1));
      expect(reparsed.teleporters.first.a.c, 4);
      expect(reparsed.teleporters.first.b.r, 4);
    });

    test('the published document reads back the same after a round trip', () {
      final original = Challenge.fromMap(raw)!;
      // The shape _writeCache stores, rebuilt here and put back through the
      // real parser — JSON in between, so nothing survives on object identity.
      final cached = jsonDecode(jsonEncode({
        'id': original.id,
        'title': original.title,
        'description': original.description,
        'startDate': original.startDate.millisecondsSinceEpoch,
        'endDate': original.endDate.millisecondsSinceEpoch,
        'reward': original.reward == ChallengeReward.hint ? 'hint' : 'none',
        'level': ChallengeService.encodeLevelForTest(original),
      })) as Map<String, dynamic>;

      final reparsed = Challenge.fromMap(cached);
      expect(reparsed, isNotNull,
          reason: 'a cache the parser rejects is no cache at all');
      expect(reparsed!.id, original.id);
      expect(reparsed.level.size, original.level.size);
      expect(reparsed.level.start.dir, original.level.start.dir);
      expect(reparsed.level.forcedArrows.length,
          original.level.forcedArrows.length);
      expect(
        reparsed.level.toolkit.fold<int>(0, (n, e) => n + e.count),
        original.level.toolkit.fold<int>(0, (n, e) => n + e.count),
      );
      // Still winnable on the other side, which is the only property the
      // player would notice going missing.
      expect(isSolvable(reparsed.level), isTrue);
    });
  });
}

/// A challenge whose only interesting part is its toolkit.
Challenge _challengeWith(List<ToolkitEntry> toolkit) => Challenge(
      id: 'week_encode',
      title: 'Encode',
      description: '',
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 1, 8),
      reward: ChallengeReward.hint,
      level: LevelData(
        id: -1,
        size: 5,
        title: 'Encode',
        tip: '',
        start: const StartSpec(0, 0, Direction.right),
        exit: const Pos(4, 4),
        toolkit: toolkit,
      ),
    );
