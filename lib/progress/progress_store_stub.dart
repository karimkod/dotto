// Fallback: in-memory completed-level set, for any platform with neither
// dart.library.js_interop nor dart.library.io.

final Set<int> _completed = {};

/// Nothing to load — this store only ever lives for one session.
Future<void> init() async {}

Set<int> completed() => {..._completed};

void markCompleted(int level) => _completed.add(level);

int _hints = 0;

int hintsUsed() => _hints;

void bumpHintsUsed() => _hints++;

void clear() => _completed.clear();
