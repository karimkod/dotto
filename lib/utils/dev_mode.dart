import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// Whether dev-only tools (the level designer entry points) should be shown.
///
/// - On the web: true when the URL carries a `dev=true` query param, e.g.
///   `https://karimkod.github.io/dotto/?dev=true`.
/// - On non-web (and in tests): falls back to [kDebugMode].
bool get isDevMode {
  if (kIsWeb && Uri.base.queryParameters['dev'] == 'true') return true;
  return kDebugMode;
}
