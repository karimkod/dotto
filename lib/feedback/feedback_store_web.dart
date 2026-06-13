// Web store: persists feedback to localStorage under `dotto_feedback`, and can
// trigger a JSON file download for export.

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'feedback.dart';

const _key = 'dotto_feedback';

List<FeedbackEntry> loadAll() {
  try {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) return [];
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['feedback'] as List?) ?? const [];
    return list
        .map((e) => FeedbackEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

void _saveAll(List<FeedbackEntry> entries) {
  final map = {'feedback': [for (final e in entries) e.toJson()]};
  web.window.localStorage.setItem(_key, jsonEncode(map));
}

void add(FeedbackEntry entry) {
  final all = loadAll()..add(entry);
  _saveAll(all);
}

void exportJson() {
  final all = loadAll();
  final pretty = const JsonEncoder.withIndent('  ')
      .convert({'feedback': [for (final e in all) e.toJson()]});

  final blob = web.Blob(
    [pretty.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = 'dotto_feedback.json';
  anchor.click();
  web.URL.revokeObjectURL(url);
}
