// Level-progress storage facade. localStorage on web, shared_preferences on
// mobile/desktop, and an in-memory stub where neither library exists.
//
// The conditions are ordered, first match wins: web has dart.library.js_interop,
// mobile and the VM have dart.library.io, and the stub catches anything else.

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'progress_store_stub.dart'
    if (dart.library.js_interop) 'progress_store_web.dart'
    if (dart.library.io) 'progress_store_io.dart' as impl;

class ProgressStore {
  ProgressStore._();

  /// Loads saved progress into memory. Call once before `runApp`; the reads
  /// below are synchronous, so anything not loaded by then reads as unplayed.
  static Future<void> init() => impl.init();

  /// The set of completed level numbers.
  static Set<int> completed() => impl.completed();

  /// Record a level as completed (which unlocks the next one).
  static void markCompleted(int level) => impl.markCompleted(level);

  /// Lifetime count of hints taken, across every level and session. Reported as
  /// an analytics user property; nothing in the game reads it.
  static int hintsUsed() => impl.hintsUsed();

  static void bumpHintsUsed() => impl.bumpHintsUsed();

  /// Merge a saved snapshot into local progress.
  ///
  /// Union for levels, max for the hint count — see CloudSaveService for why
  /// that direction is the only safe one.
  static void importProgress({
    required Set<int> levels,
    required int hintsUsed,
  }) =>
      impl.importProgress(levels: levels, hintsUsed: hintsUsed);

  /// Erase every completed level. No longer reachable from the game — the
  /// Reset progress row is gone — but kept because the cloud-save tests need a
  /// clean slate between cases, and because a player-facing reset is the kind
  /// of thing that comes back.
  @visibleForTesting
  static void clear() => impl.clear();
}
