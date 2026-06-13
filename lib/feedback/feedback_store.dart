// Feedback storage facade. Resolves to localStorage on web, an in-memory stub
// elsewhere (so VM tests don't touch dart:js_interop).

import 'feedback.dart';
import 'feedback_store_stub.dart'
    if (dart.library.js_interop) 'feedback_store_web.dart' as impl;

class FeedbackStore {
  FeedbackStore._();

  static List<FeedbackEntry> loadAll() => impl.loadAll();
  static void add(FeedbackEntry entry) => impl.add(entry);

  /// On web, downloads all feedback as `dotto_feedback.json`.
  static void exportJson() => impl.exportJson();
}
