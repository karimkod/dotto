// Web store: persists completed levels to localStorage under `dotto_progress`.

import 'dart:convert';

import 'package:web/web.dart' as web;

const _key = 'dotto_progress';

Set<int> completed() {
  try {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['completed'] as List?) ?? const [];
    return {for (final e in list) (e as num).toInt()};
  } catch (_) {
    return {};
  }
}

void markCompleted(int level) {
  final set = completed()..add(level);
  web.window.localStorage
      .setItem(_key, jsonEncode({'completed': set.toList()..sort()}));
}
