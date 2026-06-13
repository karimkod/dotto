// Non-web fallback: in-memory store (used by the VM test runner). Mobile
// persistence (SharedPreferences / file) can replace this later; the web build
// persists to localStorage.

import 'feedback.dart';

final List<FeedbackEntry> _entries = [];

List<FeedbackEntry> loadAll() => List.of(_entries);

void add(FeedbackEntry entry) => _entries.add(entry);

void exportJson() {/* no-op off web */}
