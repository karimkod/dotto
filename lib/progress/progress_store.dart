// Level-progress storage facade. localStorage on web, in-memory stub elsewhere.

import 'progress_store_stub.dart'
    if (dart.library.js_interop) 'progress_store_web.dart' as impl;

class ProgressStore {
  ProgressStore._();

  /// The set of completed level numbers.
  static Set<int> completed() => impl.completed();

  /// Record a level as completed (which unlocks the next one).
  static void markCompleted(int level) => impl.markCompleted(level);
}
