import 'package:flutter/foundation.dart' show kDebugMode;

/// Whether dev-only tools — the level designer and the playtest feedback box —
/// should exist at all.
///
/// Debug builds only, and deliberately `const`: a compile-time constant lets
/// the tree shaker drop every guarded branch from a release build, so the
/// designer is not merely hidden there but absent from the binary.
///
/// This used to be a getter that also returned true on the web when the URL
/// carried `?dev=true`. That was a hole rather than a convenience — the web
/// build is compiled `--release` and deployed publicly on every push to main,
/// so anyone appending the parameter got the level designer and the feedback
/// export on the live site. A dev tool that a URL can summon in production is
/// not gated.
const bool isDevMode = kDebugMode;
