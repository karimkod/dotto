// Non-web fallback: in-memory completed-level set (VM tests).

final Set<int> _completed = {};

Set<int> completed() => {..._completed};

void markCompleted(int level) => _completed.add(level);
