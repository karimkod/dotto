// The daily free hint: one, shared across every level, back 24 hours after it
// is spent.
//
// Non-cumulative on purpose. Leaving it unused does not bank a second one, so
// the ceiling is always one — which is what makes it a rhythm rather than a
// currency to hoard.
//
// ONE SOURCE OF TRUTH: when it was last spent. Availability is derived from
// that, not stored beside it. A separate "available" flag would be a second
// record of the same fact and the two can disagree — a write that half-lands, a
// clock change, an app killed between the two setters — and a player looking at
// a hint the game will not give them has no way to argue.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FreeHintService {
  FreeHintService._();

  /// Epoch millis of the last spend. 0 means never spent, so one is waiting.
  static const _usedAtKey = 'free_hint_used_at';

  /// How long regenerating takes.
  static const Duration regenerates = Duration(hours: 24);

  static SharedPreferences? _prefs;
  static int _usedAt = 0;

  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _usedAt = prefs.getInt(_usedAtKey) ?? 0;
    } catch (_) {
      // No storage: the hint is available and stays available for the session.
    }
  }

  /// Whether a free hint is ready.
  static bool availableAt(DateTime now) {
    if (_usedAt == 0) return true;
    final elapsed = now.millisecondsSinceEpoch - _usedAt;
    // A negative elapsed means the device clock moved backwards — a timezone
    // change, or a player fishing for an early hint. Either way, hand it over
    // rather than lock them out for however long the clock was wound back.
    // Being generous about a rare edge beats trapping someone behind a date.
    if (elapsed < 0) return true;
    return elapsed >= regenerates.inMilliseconds;
  }

  static bool get available => availableAt(DateTime.now());

  /// What is left before the next one, or zero when one is ready.
  static Duration remainingAt(DateTime now) {
    if (availableAt(now)) return Duration.zero;
    final elapsed = now.millisecondsSinceEpoch - _usedAt;
    return regenerates - Duration(milliseconds: elapsed);
  }

  static Duration get remaining => remainingAt(DateTime.now());

  /// "14h 32m", or "40m" under an hour. Never seconds — a countdown ticking by
  /// the second invites watching it, and this is a wait measured in hours.
  ///
  /// Minutes round UP, which is both how people read a countdown and what stops
  /// the label reading "23h 59m" a millisecond after the hint was spent. It
  /// also means it never shows "0m" while there is still time to wait.
  static String remainingLabel(DateTime now) {
    final left = remainingAt(now);
    if (left == Duration.zero) return '';
    final minutes = (left.inMilliseconds / Duration.millisecondsPerMinute)
        .ceil();
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Spend the free hint. False when one is not ready.
  static bool spendAt(DateTime now) {
    if (!availableAt(now)) return false;
    _usedAt = now.millisecondsSinceEpoch;
    final prefs = _prefs;
    if (prefs != null) {
      // Fire and forget: it is already spent in memory, so a failed write costs
      // the player an extra hint rather than one they paid for.
      unawaited(prefs.setInt(_usedAtKey, _usedAt).catchError((_) => false));
    }
    return true;
  }

  static bool spend() => spendAt(DateTime.now());

  /// Tests only.
  @visibleForTesting
  static void resetForTest({int usedAt = 0}) {
    _usedAt = usedAt;
    _prefs = null;
  }
}
