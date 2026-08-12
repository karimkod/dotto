// Progress in the cloud: Play Games Saved Games on Android, Game Center saved
// games on iOS, both through the games_services plugin.
//
// Entirely invisible. There is no UI, no toast, no spinner and no error the
// player can see — a player who never signs in to Play Games or Game Center
// plays a game that behaves exactly as before, and one who does gets their
// progress on the next device without being told about it.
//
// THE MERGE ONLY EVER ADDS. Levels are unioned and the hint count takes the
// maximum, so no combination of stale cloud data, offline play and two devices
// can take a level away from someone. The cost is that progress cannot be
// undone across devices: a reset on one device is refilled by the next cloud
// load. That is the right way round — a player who loses finished levels is
// owed an apology, one who keeps a few extra is not.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import '../analytics/analytics_service.dart';
import '../progress/progress_store.dart';
import 'game_services.dart';

/// Snapshot slot. Play Games requires 1–100 characters of a-z, A-Z, 0-9 and
/// `-._~`, and the name is permanent once written.
const _slot = 'dotto_progress';

/// Schema version, so a later format can recognise and migrate this one.
const _schemaVersion = 1;

class CloudSaveService {
  CloudSaveService._();

  /// Only where a games platform exists and the player is actually signed in —
  /// saved games are per-account, so signed out there is nowhere to put them.
  static bool get _supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    return GameServices.signedIn;
  }

  static bool _saving = false;
  static bool _dirty = false;

  /// Local progress as the JSON that goes into the slot.
  @visibleForTesting
  static String encode({required Set<int> levels, required int hintsUsed}) =>
      jsonEncode({
        'completedLevels': levels.toList()..sort(),
        'hintsUsedTotal': hintsUsed,
        'version': _schemaVersion,
      });

  /// Parse a snapshot. Returns null for anything unreadable — a corrupt or
  /// future-schema save is ignored rather than allowed to wipe what is local.
  @visibleForTesting
  static ({Set<int> levels, int hintsUsed})? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final version = (map['version'] as num?)?.toInt() ?? 0;
      // A save written by a newer version of the game may mean something else
      // by these fields. Leaving it alone is safer than guessing.
      if (version > _schemaVersion) return null;
      final list = (map['completedLevels'] as List?) ?? const [];
      return (
        levels: {for (final e in list) (e as num).toInt()},
        hintsUsed: (map['hintsUsedTotal'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('Cloud save unreadable, ignoring: $e');
      return null;
    }
  }

  /// Pull the cloud snapshot, merge it into local progress, and push the merged
  /// result back so both sides agree.
  ///
  /// Called after sign-in. Never awaited by anything the player is waiting on.
  static Future<void> load() async {
    if (!_supported) return;
    try {
      final remote = decode(await SaveGame.loadGame(name: _slot));
      if (remote == null) {
        // Nothing there, or unreadable. Push what is local so the slot exists
        // for the next device.
        await _write();
        return;
      }
      final before = ProgressStore.completed().length;
      ProgressStore.importProgress(
        levels: remote.levels,
        hintsUsed: remote.hintsUsed,
      );
      final after = ProgressStore.completed().length;
      // Only write back when the merge actually changed something, or when the
      // cloud is behind — otherwise every launch costs a needless upload.
      if (after != before || remote.levels.length != after) await _write();
    } catch (e) {
      // Offline, not signed in any more, Saved Games disabled in the console:
      // all of it means "carry on with local progress".
      debugPrint('Cloud load failed: $e');
      Analytics.cloudSaveFailed('load');
    }
  }

  /// Push local progress to the cloud. Safe to call often.
  ///
  /// Coalesces: a call made while a write is in flight sets a flag and the
  /// write repeats once, rather than queueing one upload per placed piece.
  static void save() {
    if (!_supported) return;
    if (_saving) {
      _dirty = true;
      return;
    }
    unawaited(_writeLoop());
  }

  static Future<void> _writeLoop() async {
    _saving = true;
    try {
      do {
        _dirty = false;
        await _write();
      } while (_dirty);
    } finally {
      _saving = false;
    }
  }

  static Future<void> _write() async {
    try {
      await SaveGame.saveGame(
        data: encode(
          levels: ProgressStore.completed(),
          hintsUsed: ProgressStore.hintsUsed(),
        ),
        name: _slot,
      );
    } catch (e) {
      debugPrint('Cloud save failed: $e');
      Analytics.cloudSaveFailed('save');
    }
  }

  /// Tests only.
  @visibleForTesting
  static void resetForTest() {
    _saving = false;
    _dirty = false;
  }
}
