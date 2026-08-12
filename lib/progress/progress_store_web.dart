// Web store: persists completed levels to localStorage under `dotto_progress`.

import 'dart:convert';

import 'package:web/web.dart' as web;

const _key = 'dotto_progress';

/// localStorage reads synchronously, so there is nothing to preload.
Future<void> init() async {}

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

const _hintsKey = 'dotto_hints_used';

int hintsUsed() {
  try {
    return int.tryParse(web.window.localStorage.getItem(_hintsKey) ?? '') ?? 0;
  } catch (_) {
    return 0;
  }
}

void bumpHintsUsed() {
  try {
    web.window.localStorage.setItem(_hintsKey, '${hintsUsed() + 1}');
  } catch (_) {}
}

void clear() {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {}
}

void importProgress({required Set<int> levels, required int hintsUsed}) {
  try {
    // Read storage directly rather than calling hintsUsed(): the parameter
    // shares that name and shadows the function throughout this body. The
    // signature is fixed by the facade, so the read moves instead.
    final current =
        int.tryParse(web.window.localStorage.getItem(_hintsKey) ?? '') ?? 0;
    final set = completed()..addAll(levels);
    web.window.localStorage
        .setItem(_key, jsonEncode({'completed': set.toList()..sort()}));
    if (hintsUsed > current) {
      web.window.localStorage.setItem(_hintsKey, '$hintsUsed');
    }
  } catch (_) {}
}
