// Mobile/desktop store: persists completed levels to shared_preferences under
// `dotto_progress`, in the same JSON shape the web build writes to localStorage.
//
// The facade reads synchronously (buildInitialLevels needs an answer during a
// build), but shared_preferences is async — so the set lives in memory and the
// preferences file is the backup that repopulates it on launch. [init] hydrates
// the cache once at startup; every read after that is served from memory and
// every write updates memory first and persists in the background.
//
// That ordering also makes this safe under `flutter test`, where the plugin has
// no host to answer it: getInstance throws, _prefs stays null, and the cache
// behaves exactly like the old in-memory stub instead of taking the suite down.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _key = 'dotto_progress';

final Set<int> _cache = {};
SharedPreferences? _prefs;

Future<void> init() async {
  try {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _hints = prefs.getInt(_hintsKey) ?? 0;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['completed'] as List?) ?? const [];
    _cache.addAll({for (final e in list) (e as num).toInt()});
  } catch (_) {
    // No storage available (or corrupt JSON). The player starts fresh rather
    // than the app failing to launch.
  }
}

Set<int> completed() => {..._cache};

void markCompleted(int level) {
  if (!_cache.add(level)) return; // already recorded — nothing to write
  final prefs = _prefs;
  if (prefs == null) return;
  final payload = jsonEncode({'completed': _cache.toList()..sort()});
  // Fire and forget: progress is already true in memory, so a failed write
  // costs this session's tail rather than the level the player just won.
  unawaited(prefs.setString(_key, payload).catchError((_) => false));
}

const _hintsKey = 'dotto_hints_used';

/// Cached like the completed set, and for the same reason: the read is
/// synchronous while shared_preferences is not.
int _hints = 0;

int hintsUsed() => _hints;

void bumpHintsUsed() {
  _hints++;
  final prefs = _prefs;
  if (prefs == null) return;
  unawaited(prefs.setInt(_hintsKey, _hints).catchError((_) => false));
}
