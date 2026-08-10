// Level-progress storage facade. localStorage on web, shared_preferences on
// mobile/desktop, and an in-memory stub where neither library exists.
//
// The conditions are ordered, first match wins: web has dart.library.js_interop,
// mobile and the VM have dart.library.io, and the stub catches anything else.

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
}
