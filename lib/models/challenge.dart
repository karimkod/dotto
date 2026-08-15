// A weekly challenge and the board it carries.
//
// The document comes from Firestore, which means it is written by hand in a
// console and can be wrong in ways the compiler will never see. Everything here
// is therefore defensive: a field of the wrong type, a coordinate off the
// board, a direction spelled differently — any of it yields null rather than a
// half-built level that crashes when the dot reaches it. A challenge that fails
// to parse is simply not offered.
//
// The JSON shape is the one in docs/challenges-setup.md. It is close to
// level_definitions.dart but not identical, and the differences are deliberate:
// a console document is written by a person, so it uses `rows`/`cols` and
// `[row, col]` pairs rather than the Dart constructors.

import 'grid_cell.dart';
import 'level_data.dart';

/// What finishing a challenge gives the player.
enum ChallengeReward { none, hint }

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.reward,
    required this.level,
  });

  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final ChallengeReward reward;
  final LevelData level;

  /// Live right now.
  bool isActiveAt(DateTime now) =>
      !now.isBefore(startDate) && now.isBefore(endDate);

  /// Finished and gone — playable from the archive, but no longer the one to
  /// beat this week.
  bool hasEndedAt(DateTime now) => !now.isBefore(endDate);

  /// Published, but its week has not come round yet.
  ///
  /// Weeks are authored in batches and published all at once, so most of the
  /// collection is normally in this state — which is why it needs a name.
  bool hasNotStartedAt(DateTime now) => now.isBefore(startDate);

  /// Whole days left, floored, never negative.
  int daysRemainingAt(DateTime now) {
    final left = endDate.difference(now);
    return left.isNegative ? 0 : left.inDays;
  }

  /// Calendar days until it opens, never negative.
  ///
  /// Counted between dates rather than as elapsed time, because it is read out
  /// as "today" and "tomorrow": a window opening at midnight on the 17th is two
  /// sleeps away on the 15th, however few hours short of 48 that happens to be.
  /// The half-day offset absorbs a daylight-saving shift in between.
  int daysUntilAt(DateTime now) {
    final opens = DateTime(startDate.year, startDate.month, startDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = (opens.difference(today).inHours + 12) ~/ 24;
    return days < 0 ? 0 : days;
  }

  /// Build from a Firestore document, or null if it cannot be trusted.
  ///
  /// [raw] is the document data; [docId] the document's own id, used when the
  /// document omits its `id` field.
  static Challenge? fromMap(Map<String, dynamic> raw, {String? docId}) {
    try {
      final id = (raw['id'] as String?) ?? docId;
      if (id == null || id.isEmpty) return null;

      final start = _date(raw['startDate']);
      final end = _date(raw['endDate']);
      if (start == null || end == null) return null;
      // A window that ends before it starts would be active never or always
      // depending on the comparison; refuse it rather than pick.
      if (!end.isAfter(start)) return null;

      final level = _level(raw['level'], id: id);
      if (level == null) return null;

      return Challenge(
        id: id,
        title: (raw['title'] as String?)?.trim().isNotEmpty == true
            ? (raw['title'] as String).trim()
            : 'Weekly Challenge',
        description: (raw['description'] as String?)?.trim() ?? '',
        startDate: start,
        endDate: end,
        reward: (raw['reward'] as String?) == 'hint'
            ? ChallengeReward.hint
            : ChallengeReward.none,
        level: level,
      );
    } catch (_) {
      return null;
    }
  }

  /// Firestore hands back a Timestamp, but a hand-written document or the
  /// local cache may hold an ISO string or millis instead.
  static DateTime? _date(Object? v) {
    if (v == null) return null;
    // Timestamp, without importing cloud_firestore into a model file.
    try {
      final dynamic d = v;
      if (d is DateTime) return d;
      if (d is int) return DateTime.fromMillisecondsSinceEpoch(d);
      if (d is String) return DateTime.tryParse(d);
      return d.toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  static int? _int(Object? v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

  /// A cell, written either as a `[row, col]` pair or as a `{"r": …, "c": …}`
  /// map, checked against the board.
  ///
  /// The map form is not a convenience. Firestore refuses to store an array
  /// inside an array — `400 Nested arrays are not allowed` — and `walls`,
  /// `gaps`, `destroyers` and `teleporters` are all lists of pairs, so as bare
  /// `[row, col]` they could not be written at all and had to be left empty.
  /// A map *is* storable inside an array, so the same cell written as
  /// `{"r": 1, "c": 2}` goes through and the static terrain comes back.
  ///
  /// `[row, col]` is still read everywhere, and is still what `start`, `goal`
  /// and each `position` use: those sit directly inside a map rather than
  /// inside an array, so Firestore never objected to them.
  static Pos? _pos(Object? v, int size) {
    int? r;
    int? c;
    if (v is List && v.length >= 2) {
      r = _int(v[0]);
      c = _int(v[1]);
    } else if (v is Map) {
      // `row`/`col` as well as `r`/`c`: the document is written by hand, and
      // both spellings are the obvious one to reach for.
      r = _int(v['r'] ?? v['row']);
      c = _int(v['c'] ?? v['col']);
    }
    if (r == null || c == null) return null;
    if (r < 0 || c < 0 || r >= size || c >= size) return null;
    return Pos(r, c);
  }

  static Direction? _dir(Object? v) => switch (v) {
        'up' => Direction.up,
        'down' => Direction.down,
        'left' => Direction.left,
        'right' => Direction.right,
        _ => null,
      };

  static ToolType? _tool(String? type, Direction? dir) => switch (type) {
        'arrow' => dir?.arrowTool,
        'oneShot' => dir?.oneShotTool,
        'shield' => ToolType.shield,
        'pause' => ToolType.pause,
        'teleporter' => ToolType.teleporter,
        _ => null,
      };

  static LevelData? _level(Object? v, {required String id}) {
    if (v is! Map) return null;
    final map = v.cast<String, dynamic>();

    // The board is square. `rows` and `cols` are both accepted because the
    // documented shape carries them, but a non-square board has nowhere to go
    // in LevelData, so a mismatch is refused rather than silently cropped.
    final rows = _int(map['rows']);
    final cols = _int(map['cols']) ?? rows;
    if (rows == null || cols == null || rows != cols) return null;
    if (rows < 3 || rows > 12) return null;
    final size = rows;

    final startPos = _pos(map['start'], size);
    final goal = _pos(map['goal'], size);
    if (startPos == null || goal == null) return null;
    // The dot needs a heading; the documented shape has no direction on
    // `start`, so `startDir` is optional and rightward is the default.
    final startDir = _dir(map['startDir']) ?? Direction.right;

    List<Pos> positions(Object? raw) => [
          for (final e in (raw as List?) ?? const []) ?_pos(e, size),
        ];

    final toolkit = <ToolkitEntry>[];
    for (final e in (map['pieces'] as List?) ?? const []) {
      if (e is! Map) continue;
      final piece = e.cast<String, dynamic>();
      final tool = _tool(piece['type'] as String?, _dir(piece['direction']));
      final count = _int(piece['count']) ?? 1;
      if (tool != null && count > 0) toolkit.add(ToolkitEntry(tool, count));
    }

    final forcedArrows = <ForcedArrow>[];
    final forcedShields = <Pos>[];
    final forcedPauses = <Pos>[];
    for (final e in (map['forcedPieces'] as List?) ?? const []) {
      if (e is! Map) continue;
      final piece = e.cast<String, dynamic>();
      final at = _pos(piece['position'], size);
      if (at == null) continue;
      switch (piece['type']) {
        case 'arrow':
          final d = _dir(piece['direction']);
          if (d != null) forcedArrows.add(ForcedArrow(at.r, at.c, d));
        case 'shield':
          forcedShields.add(at);
        case 'pause':
          forcedPauses.add(at);
      }
    }

    final rotating = <RotatingArrow>[];
    for (final e in (map['rotatingArrows'] as List?) ?? const []) {
      if (e is! Map) continue;
      final a = e.cast<String, dynamic>();
      final at = _pos(a['position'], size);
      final d = _dir(a['direction']);
      if (at != null && d != null) rotating.add(RotatingArrow(at.r, at.c, d));
    }

    // Teleporters arrive as pairs of cells: `[[r,c],[r,c]]`, or — since that
    // shape is doubly nested and so doubly unstorable — as
    // `{"a": {"r":…,"c":…}, "b": {…}}`. See [_pos].
    final teleporters = <TeleporterPair>[];
    for (final e in (map['teleporters'] as List?) ?? const []) {
      final Pos? a;
      final Pos? b;
      if (e is List && e.length >= 2) {
        a = _pos(e[0], size);
        b = _pos(e[1], size);
      } else if (e is Map) {
        a = _pos(e['a'], size);
        b = _pos(e['b'], size);
      } else {
        continue;
      }
      if (a != null && b != null) teleporters.add(TeleporterPair(a, b));
    }

    final movers = <MovingDestroyer>[];
    for (final e in (map['patrols'] as List?) ?? const []) {
      if (e is! Map) continue;
      final p = e.cast<String, dynamic>();
      final at = _pos(p['position'], size);
      if (at == null) continue;
      movers.add(MovingDestroyer(
        at.r,
        at.c,
        horizontal: p['horizontal'] as bool? ?? true,
        dir: (_int(p['dir']) ?? 1) < 0 ? -1 : 1,
      ));
    }

    return LevelData(
      // Challenge boards are never part of the numbered campaign. A negative
      // id keeps them from colliding with a real level anywhere that indexes
      // by number — including the progress store, which must never record one.
      id: -1,
      size: size,
      title: 'Challenge',
      tip: '',
      start: StartSpec(startPos.r, startPos.c, startDir),
      exit: goal,
      toolkit: toolkit,
      walls: positions(map['walls']),
      destroyers: positions(map['destroyers']),
      gaps: positions(map['gaps']),
      forcedArrows: forcedArrows,
      rotatingArrows: rotating,
      forcedShields: forcedShields,
      forcedPauses: forcedPauses,
      teleporters: teleporters,
      movers: movers,
    );
  }
}
