// Weekly challenges, pushed from Firestore so a new one needs no app update.
//
// Firestore is read-only from the client — the rules in
// docs/challenges-setup.md deny writes outright — so nothing here can corrupt
// the collection, and a document that fails to parse is dropped rather than
// shown.
//
// Everything degrades to "no challenges": no network, no Firebase, web, or a
// collection that does not exist yet all end at an empty list and a friendly
// screen. The rest of the game never depends on this.
//
// Offline works two ways over. Firestore keeps its own cache, and the last
// good fetch is also written to SharedPreferences — which is what covers a
// cold start with no network, where Firestore's cache may not answer before
// the screen wants to draw.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics_service.dart';
import '../models/challenge.dart';
import 'free_hint_service.dart';

class ChallengeService {
  ChallengeService._();

  static const _collection = 'challenges';
  static const _cacheKey = 'challenges_cache';
  static const _completedKey = 'completed_challenges';
  static const _bonusHintsKey = 'challenge_bonus_hints';

  /// How long a cached copy is served before a refetch is attempted anyway.
  /// A week's challenge does not change often; this is about not hammering
  /// Firestore on every launch.
  static const _cacheTtl = Duration(hours: 6);
  static const _fetchedAtKey = 'challenges_fetched_at';

  static SharedPreferences? _prefs;
  static List<Challenge> _challenges = const [];
  static Set<String> _completed = {};
  static int _bonusHints = 0;
  static Future<void>? _pending;

  /// The launch fetch, for a screen built before it lands.
  ///
  /// [init] starts the refresh unawaited, so the menu decides its badge from
  /// an empty list and then has no reason to build again — on a cold start the
  /// badge would appear only when something else happened to rebuild the
  /// screen. Completes immediately when there is nothing in flight, and never
  /// with an error: [refresh] swallows its own.
  static Future<void> get pending => _pending ?? Future.value();

  /// Firestore is mobile-only here, for the same reason as the rest of the
  /// Firebase work: no web config, and no plugin host under test.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Everything known, newest first. Empty until [init] has run.
  static List<Challenge> get challenges => List.unmodifiable(_challenges);

  /// Spare hints won from challenges. Spent before the free hint.
  static int get bonusHints => _bonusHints;

  /// The most hints a player can hold at once, daily and bonus together.
  ///
  /// A hint is only worth taking if the player had to decide to earn it. Let
  /// them stockpile and the interesting levels get solved by a queue of hints
  /// nobody remembers winning.
  static const int maxHints = 3;

  /// Whether the daily hint counts toward the hand, and so whether it may be
  /// spent.
  ///
  /// Bonus hints alone can fill the cap. When they do, the daily one sits and
  /// waits rather than pushing the total to four — and, because it is spent
  /// first everywhere else, waiting is also what stops a capped player burning
  /// their regenerating hint while three banked ones go untouched.
  static bool get freeHintCounts => _bonusHints < maxHints;

  /// Everything the player can spend right now, capped at [maxHints].
  ///
  /// Clamped rather than asserted: a save from before the cap existed, or one
  /// restored from the cloud, can hold more than three. Those still get spent
  /// down one at a time — the badge just never claims a number the rules no
  /// longer allow.
  static int get hintsInHand {
    final held = (freeHintCounts && FreeHintService.available ? 1 : 0) +
        _bonusHints;
    return held > maxHints ? maxHints : held;
  }

  static bool isCompleted(String id) => _completed.contains(id);

  /// How many challenges have ever been beaten.
  ///
  /// Counted from the completed set rather than by walking [_challenges]: the
  /// Firestore fetch keeps only the last 52 weeks, so a player's older wins
  /// would quietly stop counting once they aged out of the collection.
  static int get completedCount => _completed.length;

  /// The challenge running right now, if any.
  static Challenge? currentAt(DateTime now) {
    for (final c in _challenges) {
      if (c.isActiveAt(now)) return c;
    }
    return null;
  }

  /// Challenges whose window has closed, newest first.
  static List<Challenge> pastAt(DateTime now) =>
      [for (final c in _challenges) if (c.hasEndedAt(now)) c];

  /// Challenges published ahead of their week, soonest first.
  ///
  /// Weeks are authored and published in batches, so on any given day most of
  /// the collection is in this state — ten of the eleven documents, when the
  /// screen was first pointed at a real one. Everything else here is
  /// newest-first, which is the wrong end for something that has not happened:
  /// next week should read before the week after it.
  static List<Challenge> upcomingAt(DateTime now) =>
      [for (final c in _challenges.reversed) if (c.hasNotStartedAt(now)) c];

  /// Consecutive completed challenges, counting back from the most recent one
  /// that has ended.
  ///
  /// The live challenge is deliberately excluded: a week still in progress
  /// cannot break a streak, and counting it would show the streak dropping to
  /// zero every Monday until the player got round to playing.
  static int streakAt(DateTime now) {
    final ended = pastAt(now);
    var streak = 0;
    for (final c in ended) {
      if (!_completed.contains(c.id)) break;
      streak++;
    }
    // A completed live challenge extends the run it is attached to.
    final live = currentAt(now);
    if (live != null && _completed.contains(live.id)) streak++;
    return streak;
  }

  /// Load the cache, then refresh from Firestore in the background.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _completed = (prefs.getStringList(_completedKey) ?? const []).toSet();
      _bonusHints = prefs.getInt(_bonusHintsKey) ?? 0;
      _challenges = _decodeCache(prefs.getString(_cacheKey));
    } catch (_) {
      // No storage: challenges still work, they just refetch every launch.
    }
    if (!supported) return;

    final fetchedAt = _prefs?.getInt(_fetchedAtKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
    if (_challenges.isEmpty || age > _cacheTtl.inMilliseconds) {
      unawaited(_pending = refresh());
    }
  }

  /// Pull the collection and replace what is cached.
  ///
  /// Never throws and never awaited by the UI: the screen draws whatever is
  /// already loaded and picks the new list up on its next build.
  static Future<void> refresh() async {
    if (!supported) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .orderBy('startDate', descending: true)
          .limit(52) // a year of weeks is plenty to show
          .get();

      final parsed = <Challenge>[];
      for (final doc in snap.docs) {
        final c = Challenge.fromMap(doc.data(), docId: doc.id);
        if (c != null) {
          parsed.add(c);
        } else {
          // A malformed document is a content bug, not a player problem — it
          // is dropped here and visible in the log rather than crashing.
          debugPrint('Challenge ${doc.id} could not be parsed; skipping');
        }
      }
      // docs/challenges-setup.md tells anyone whose challenge did not appear to
      // check the log first. Until this line there was nothing in it to check:
      // a successful fetch was silent, so "no challenges" looked identical
      // whether the query returned nothing or the parser dropped everything.
      debugPrint('Challenges: ${snap.docs.length} fetched, '
          '${parsed.length} parsed');
      _challenges = parsed;
      await _writeCache();
    } catch (e) {
      debugPrint('Challenge fetch failed, using cache: $e');
    }
  }

  /// Record a finished challenge and pay out its reward. Returns the reward
  /// granted, so the caller can say so on the celebration screen.
  ///
  /// A hint reward is dropped when the player is already holding [maxHints].
  /// The challenge still counts as completed — the streak is about playing,
  /// not about having room for the prize — but the celebration screen is told
  /// [ChallengeReward.none] rather than promised a hint that was never added.
  static ChallengeReward complete(Challenge challenge) {
    // Completing twice must not pay twice.
    if (!_completed.add(challenge.id)) return ChallengeReward.none;

    var reward = challenge.reward;
    if (reward == ChallengeReward.hint) {
      if (hintsInHand >= maxHints) {
        reward = ChallengeReward.none;
      } else {
        _bonusHints++;
      }
    }
    _persistProgress();
    Analytics.challengeCompleted(challenge.id, challenge.title);
    return reward;
  }

  /// Spend a bonus hint. Returns false when there are none.
  static bool spendBonusHint() {
    if (_bonusHints <= 0) return false;
    _bonusHints--;
    _persistProgress();
    return true;
  }

  static void _persistProgress() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs
        .setStringList(_completedKey, _completed.toList())
        .catchError((_) => false));
    unawaited(
        prefs.setInt(_bonusHintsKey, _bonusHints).catchError((_) => false));
  }

  // ----- offline cache -----

  static Future<void> _writeCache() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final payload = jsonEncode([
        for (final c in _challenges)
          {
            'id': c.id,
            'title': c.title,
            'description': c.description,
            // Millis rather than Timestamp: this cache is plain JSON, and
            // Challenge._date accepts either.
            'startDate': c.startDate.millisecondsSinceEpoch,
            'endDate': c.endDate.millisecondsSinceEpoch,
            'reward': c.reward == ChallengeReward.hint ? 'hint' : 'none',
            'level': _encodeLevel(c),
          }
      ]);
      await prefs.setString(_cacheKey, payload);
      await prefs.setInt(
          _fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Challenge cache write failed: $e');
    }
  }

  static List<Challenge> _decodeCache(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          ?Challenge.fromMap((e as Map).cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('Challenge cache unreadable: $e');
      return const [];
    }
  }

  /// The level, back in the document shape, so the cache round-trips through
  /// the same parser the network path uses. One parser, one set of rules.
  static Map<String, Object?> _encodeLevel(Challenge c) {
    final l = c.level;
    // `{r, c}` rather than `[r, c]`: the same shape the published document now
    // uses, because Firestore will not store an array inside an array. The
    // cache has no such limit, but writing one shape everywhere means the
    // offline copy exercises the parser exactly as the network path does.
    List<Map<String, int>> pos(Iterable<dynamic> items) =>
        [for (final p in items) {'r': p.r as int, 'c': p.c as int}];
    return {
      'rows': l.size,
      'cols': l.size,
      'start': [l.start.r, l.start.c],
      'startDir': l.start.dir.name,
      'goal': [l.exit.r, l.exit.c],
      'walls': pos(l.walls),
      'destroyers': pos(l.destroyers),
      'gaps': pos(l.gaps),
      'pieces': [
        for (final t in l.toolkit)
          {'type': _toolName(t.type), 'direction': _toolDir(t.type),
           'count': t.count}
      ],
      'forcedPieces': [
        for (final a in l.forcedArrows)
          {'type': 'arrow', 'direction': a.dir.name, 'position': [a.r, a.c]},
        for (final p in l.forcedShields)
          {'type': 'shield', 'position': [p.r, p.c]},
        for (final p in l.forcedPauses)
          {'type': 'pause', 'position': [p.r, p.c]},
      ],
      'rotatingArrows': [
        for (final a in l.rotatingArrows)
          {'direction': a.dir.name, 'position': [a.r, a.c]}
      ],
      'teleporters': [
        for (final t in l.teleporters)
          {
            'a': {'r': t.a.r, 'c': t.a.c},
            'b': {'r': t.b.r, 'c': t.b.c},
          }
      ],
      'patrols': [
        for (final m in l.movers)
          {
            'position': [m.r, m.c],
            'horizontal': m.horizontal,
            'dir': m.dir,
          }
      ],
    };
  }

  /// [Enum], not [Object], and deliberately so: `.name` is not a member of the
  /// enum at all but comes from `extension EnumName on Enum` in dart:core, and
  /// extension members are resolved statically. Reaching one through `dynamic`
  /// therefore cannot work — the receiver really has no `name` to find at
  /// runtime, which is what it said:
  ///
  ///   NoSuchMethodError: Class 'ToolType' has no instance getter 'name'
  ///
  /// It threw every time the cache was written, and went unseen only because
  /// the fetch above it was failing first and never got this far. Widening
  /// these back to Object, or casting to dynamic to make one compile, brings it
  /// straight back.
  static String _toolName(Enum tool) {
    final n = tool.name;
    if (n.startsWith('oneShot')) return 'oneShot';
    if (n.startsWith('arrow')) return 'arrow';
    return n; // shield, pause, teleporter
  }

  static String? _toolDir(Enum tool) {
    final n = tool.name;
    for (final d in ['Up', 'Down', 'Left', 'Right']) {
      if (n.endsWith(d)) return d.toLowerCase();
    }
    return null;
  }

  /// Tests only: the encoder the cache writes through.
  ///
  /// Exposed because nothing reached it. The cache is written only after a
  /// successful fetch, so a throw in here was invisible from outside — it cost
  /// the offline copy and logged one line, and the fetch had its own reason to
  /// fail first for long enough that even that line never appeared.
  @visibleForTesting
  static Map<String, Object?> encodeLevelForTest(Challenge c) => _encodeLevel(c);

  /// Tests only.
  @visibleForTesting
  static void resetForTest({
    List<Challenge> challenges = const [],
    Set<String> completed = const {},
    int bonusHints = 0,
  }) {
    _challenges = challenges;
    _completed = {...completed};
    _bonusHints = bonusHints;
    _prefs = null;
  }
}
