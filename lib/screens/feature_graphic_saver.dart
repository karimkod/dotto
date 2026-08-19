// Where the exported feature graphic ends up. Resolves to a file write off
// web and to a browser download (plus a `window` handoff) on it — the same
// stub/io/web split the feedback store and the SFX engine already use, so the
// screen itself never learns which platform it is on.

import 'dart:typed_data';

import 'feature_graphic_saver_io.dart'
    if (dart.library.js_interop) 'feature_graphic_saver_web.dart' as impl;

/// Saves [png] under [name] and returns a human-readable description of where
/// it went (a path off web, the handoff name on it).
Future<String> saveFeatureGraphic(Uint8List png, String name) =>
    impl.saveFeatureGraphic(png, name);
