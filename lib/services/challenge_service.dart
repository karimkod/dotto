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

  static bool isCompleted(String id) => _completed.contains(id);

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
      unawaited(refresh());
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
      _challenges = parsed;
      await _writeCache();
    } catch (e) {
      debugPrint('Challenge fetch failed, using cache: $e');
    }
  }

  /// Record a finished challenge and pay out its reward. Returns the reward
  /// granted, so the caller can say so on the celebration screen.
  static ChallengeReward complete(Challenge challenge) {
    // Completing twice must not pay twice.
    if (!_completed.add(challenge.id)) return ChallengeReward.none;

    if (challenge.reward == ChallengeReward.hint) _bonusHints++;
    _persistProgress();
    Analytics.challengeCompleted(challenge.id, challenge.title);
    return challenge.reward;
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
    List<List<int>> pos(Iterable<dynamic> items) =>
        [for (final p in items) [p.r as int, p.c as int]];
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
          [
            [t.a.r, t.a.c],
            [t.b.r, t.b.c]
          ]
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

  static String _toolName(Object tool) {
    final n = (tool as dynamic).name as String;
    if (n.startsWith('oneShot')) return 'oneShot';
    if (n.startsWith('arrow')) return 'arrow';
    return n; // shield, pause, teleporter
  }

  static String? _toolDir(Object tool) {
    final n = (tool as dynamic).name as String;
    for (final d in ['Up', 'Down', 'Left', 'Right']) {
      if (n.endsWith(d)) return d.toLowerCase();
    }
    return null;
  }

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
