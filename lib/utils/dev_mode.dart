import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// Whether the level designer should exist.
///
/// Every web build and every debug build; mobile release builds, which are the
/// ones players get from a store, have it stripped. The web build is treated as
/// a dev surface — it is where levels are authored, so the designer has to
/// survive `flutter build web --release`.
///
/// Worth being clear about what that costs, because it is not nothing: the web
/// build is published to GitHub Pages on every push to main and that URL is
/// public and unauthenticated. Anyone who finds it can open the designer. That
/// is accepted deliberately — "web is dev-only" is a convention about who
/// bothers to visit, not a restriction on who can.
///
/// `const`, not a getter, so the tree shaker can drop the guarded branches from
/// a mobile release build rather than merely skipping them at runtime — the
/// designer is absent from the store binary, not hidden in it.
const bool isDevMode = kIsWeb || kDebugMode;

/// Whether the playtest feedback box should exist.
///
/// Debug builds only — stricter than [isDevMode] on purpose, so it is gone from
/// the public web build too. It writes to a local store with an "Export all
/// (JSON)" dump and reaches no inbox: in front of anyone who is not us it reads
/// as a way to make contact that quietly discards whatever they write.
const bool isFeedbackEnabled = kDebugMode;
