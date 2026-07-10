import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/level_solver.dart';
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level.dart';
import '../models/level_data.dart';
import '../theme/app_theme.dart';
import '../widgets/game_grid.dart';
import 'game_screen.dart';

/// The palette cell types the designer can paint.
enum DesignTool { empty, start, exit, wall, destroyer, forced, shield, mover }

/// Rotation cycle for Start / Forced arrow directions.
const _cycle = [
  Direction.right,
  Direction.down,
  Direction.left,
  Direction.up,
];
Direction _rotate(Direction d) => _cycle[(_cycle.indexOf(d) + 1) % 4];

/// A full-screen, dev-only visual level editor. It paints onto the SAME
/// [GameGridPainter] the game uses, can launch the real [GameScreen] to test a
/// level, reports the solver's verdict, exports ready-to-paste Dart for
/// `level_definitions.dart`, and imports a level (Dart or JSON) from the
/// clipboard.
class LevelDesignerScreen extends StatefulWidget {
  const LevelDesignerScreen({
    super.key,
    this.initialLevel,
    this.initialNumber,
    this.initialDifficulty,
  });

  /// When set, the designer opens pre-loaded with this level (edit mode).
  final LevelData? initialLevel;
  final int? initialNumber;
  final Difficulty? initialDifficulty;

  @override
  State<LevelDesignerScreen> createState() => _LevelDesignerScreenState();
}

class _LevelDesignerScreenState extends State<LevelDesignerScreen> {
  int _n = 5;
  int? _startKey;
  Direction _startDir = Direction.right;
  int? _exitKey;
  final Set<int> _walls = {};
  final Set<int> _destroyers = {};
  final Map<int, Direction> _forced = {};
  final Set<int> _shields = {}; // painted shield markers (design only)
  // Moving destroyers keyed by cell. Tapping again cycles the patrol axis.
  final Map<int, MovingDestroyer> _movers = {};

  final Map<ToolType, int> _kit = {
    ToolType.arrowUp: 0,
    ToolType.arrowDown: 0,
    ToolType.arrowLeft: 0,
    ToolType.arrowRight: 0,
    ToolType.shield: 0,
    ToolType.pause: 0,
  };

  DesignTool _tool = DesignTool.wall;
  Direction _paintDir = Direction.right;

  int _number = 16;
  String _title = '';
  Difficulty _difficulty = Difficulty.medium;

  /// Bumped on import so the text fields rebuild with their new initial values.
  int _formRev = 0;

  // ----- "Find Toolkit" search state -----
  bool _finding = false;
  String? _findResult;
  bool _findOk = false;
  Map<ToolType, int>? _foundKit;
  // Ordered candidate toolkits (smallest first) + cursor into them, so
  // "Try Another" resumes where the last search stopped.
  List<Map<ToolType, int>> _candidates = const [];
  int _candCursor = 0;
  // Search constraints — skip any toolkit that doesn't match.
  bool _cMustShield = false;
  bool _cMustPause = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLevel != null) {
      _loadFromLevel(
        widget.initialLevel!,
        widget.initialNumber ?? widget.initialLevel!.id,
        widget.initialDifficulty ?? Difficulty.medium,
      );
    } else {
      _resetGrid(5);
    }
  }

  /// Populate the editor from an existing level definition (edit mode).
  void _loadFromLevel(LevelData lvl, int number, Difficulty diff) {
    _resetGrid(lvl.size);
    _number = number;
    _title = lvl.title;
    _difficulty = diff;
    _startKey = _key(lvl.start.r, lvl.start.c);
    _startDir = lvl.start.dir;
    _exitKey = _key(lvl.exit.r, lvl.exit.c);
    for (final w in lvl.walls) {
      _walls.add(_key(w.r, w.c));
    }
    for (final d in lvl.destroyers) {
      _destroyers.add(_key(d.r, d.c));
    }
    for (final f in lvl.forcedArrows) {
      _forced[_key(f.r, f.c)] = f.dir;
    }
    for (final m in lvl.movers) {
      _movers[_key(m.r, m.c)] = m;
    }
    for (final k in _kit.keys.toList()) {
      _kit[k] = 0;
    }
    for (final e in lvl.toolkit) {
      if (_kit.containsKey(e.type)) _kit[e.type] = e.count;
    }
    _formRev++;
  }

  int _row(int k) => k ~/ _n;
  int _col(int k) => k % _n;
  int _key(int r, int c) => r * _n + c;

  void _resetGrid(int n) {
    _n = n;
    _walls.clear();
    _destroyers.clear();
    _forced.clear();
    _shields.clear();
    _movers.clear();
    _startKey = _key(n - 1, 0); // bottom-left, heading right
    _startDir = Direction.right;
    _exitKey = _key(0, n - 1); // top-right
  }

  String? _occupant(int k) {
    if (_startKey == k) return 'start';
    if (_exitKey == k) return 'exit';
    if (_walls.contains(k)) return 'wall';
    if (_destroyers.contains(k)) return 'destroyer';
    if (_forced.containsKey(k)) return 'forced';
    if (_shields.contains(k)) return 'shield';
    if (_movers.containsKey(k)) return 'mover';
    return null;
  }

  void _clearMovable(int k) {
    _walls.remove(k);
    _destroyers.remove(k);
    _forced.remove(k);
    _shields.remove(k);
    _movers.remove(k);
  }

  void _paintCell(int r, int c) {
    final k = _key(r, c);
    final occ = _occupant(k);
    setState(() {
      switch (_tool) {
        case DesignTool.empty:
          if (occ == 'start' || occ == 'exit') return; // can't erase those
          _clearMovable(k);
        case DesignTool.start:
          if (occ == 'start') {
            _startDir = _rotate(_startDir);
            _paintDir = _startDir;
          } else if (occ != 'exit') {
            _clearMovable(k);
            _startKey = k;
            _startDir = _paintDir;
          }
        case DesignTool.exit:
          if (occ != 'exit' && occ != 'start') {
            _clearMovable(k);
            _exitKey = k;
          }
        case DesignTool.forced:
          if (occ == 'forced') {
            _forced[k] = _rotate(_forced[k]!);
            _paintDir = _forced[k]!;
          } else if (occ != 'start' && occ != 'exit') {
            _clearMovable(k);
            _forced[k] = _paintDir;
          }
        case DesignTool.wall:
          if (occ != 'start' && occ != 'exit') {
            _clearMovable(k);
            _walls.add(k);
          }
        case DesignTool.destroyer:
          if (occ != 'start' && occ != 'exit') {
            _clearMovable(k);
            _destroyers.add(k);
          }
        case DesignTool.shield:
          if (occ != 'start' && occ != 'exit') {
            _clearMovable(k);
            _shields.add(k);
          }
        case DesignTool.mover:
          if (occ == 'mover') {
            // Cycle: horizontal dir+1 → horizontal dir-1 → vertical dir+1 →
            // vertical dir-1 → (back to start).
            final m = _movers[k]!;
            final r = _row(k), c = _col(k);
            if (m.horizontal && m.dir == 1) {
              _movers[k] = MovingDestroyer(r, c, horizontal: true, dir: -1);
            } else if (m.horizontal && m.dir == -1) {
              _movers[k] = MovingDestroyer(r, c, horizontal: false, dir: 1);
            } else if (!m.horizontal && m.dir == 1) {
              _movers[k] = MovingDestroyer(r, c, horizontal: false, dir: -1);
            } else {
              _movers[k] = MovingDestroyer(r, c, horizontal: true, dir: 1);
            }
          } else if (occ != 'start' && occ != 'exit') {
            _clearMovable(k);
            _movers[k] =
                MovingDestroyer(_row(k), _col(k), horizontal: true, dir: 1);
          }
      }
    });
  }

  // ----- build a LevelData from the current editor state -----
  LevelData _buildLevel() => LevelData(
        id: _number,
        size: _n,
        title: _title,
        tip: '',
        start: StartSpec(_row(_startKey!), _col(_startKey!), _startDir),
        exit: Pos(_row(_exitKey!), _col(_exitKey!)),
        walls: _walls.map((k) => Pos(_row(k), _col(k))).toList(),
        destroyers: _destroyers.map((k) => Pos(_row(k), _col(k))).toList(),
        forcedArrows: _forced.entries
            .map((e) => ForcedArrow(_row(e.key), _col(e.key), e.value))
            .toList(),
        movers: _movers.values.toList(),
        toolkit: [
          for (final e in _kit.entries)
            if (e.value > 0) ToolkitEntry(e.key, e.value),
        ],
      );

  Map<int, PlacedElement> _forcedPieces() => {
        for (final e in _forced.entries)
          e.key: PlacedElement(
            type: PlacedType.arrow,
            tool: e.value.arrowTool,
            direction: e.value,
          ),
      };

  /// Painted shield markers, rendered through the painter's `placed` map.
  Map<int, PlacedElement> _shieldPieces() => {
        for (final k in _shields)
          k: const PlacedElement(
            type: PlacedType.shield,
            tool: ToolType.shield,
            direction: null,
          ),
      };

  // ----- export: ready-to-paste Dart for level_definitions.dart -----
  String _toDart() {
    String poss(Iterable<int> ks) =>
        ks.map((k) => 'Pos(${_row(k)}, ${_col(k)})').join(', ');
    final b = StringBuffer();
    b.writeln(
        '// Level $_number — ${_title.isEmpty ? 'Untitled' : _title}  (difficulty: ${_difficulty.name})');
    b.writeln('$_number: LevelData(');
    b.writeln('  id: $_number,');
    b.writeln('  size: $_n,');
    b.writeln("  title: '${_title.replaceAll("'", r"\'")}',");
    b.writeln("  tip: '',");
    b.writeln(
        '  start: StartSpec(${_row(_startKey!)}, ${_col(_startKey!)}, Direction.${_startDir.name}),');
    b.writeln('  exit: Pos(${_row(_exitKey!)}, ${_col(_exitKey!)}),');
    b.writeln('  walls: [${poss(_walls)}],');
    b.writeln('  destroyers: [${poss(_destroyers)}],');
    final fa = _forced.entries
        .map((e) =>
            'ForcedArrow(${_row(e.key)}, ${_col(e.key)}, Direction.${e.value.name})')
        .join(', ');
    b.writeln('  forcedArrows: [$fa],');
    if (_movers.isNotEmpty) {
      final md = _movers.values
          .map((m) =>
              'MovingDestroyer(${m.r}, ${m.c}, horizontal: ${m.horizontal}, dir: ${m.dir})')
          .join(', ');
      b.writeln('  movers: [$md],');
    }
    final kit = [
      for (final e in _kit.entries)
        if (e.value > 0) '    ToolkitEntry(ToolType.${e.key.name}, ${e.value}),',
    ];
    if (kit.isEmpty) {
      b.writeln('  toolkit: [],');
    } else {
      b.writeln('  toolkit: [');
      for (final l in kit) {
        b.writeln(l);
      }
      b.writeln('  ],');
    }
    b.writeln('),');
    return b.toString();
  }

  void _export() {
    if (_startKey == null || _exitKey == null) {
      _snack('Need a Start and an Exit.');
      return;
    }
    Clipboard.setData(ClipboardData(text: _toDart()));
    final extra = _shields.isNotEmpty
        ? '  (${_shields.length} painted shield marker(s) excluded — use the toolkit shield count)'
        : '';
    _snack('Copied!$extra');
  }

  // ----- import from clipboard (accepts the Dart we export, or JSON) -----
  Future<void> _import() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _snack('Clipboard is empty');
      return;
    }
    if (_applyJson(text) || _applyDart(text)) {
      _snack('Imported level $_number');
    } else {
      _snack('Could not parse clipboard (expected level Dart or JSON)');
    }
  }

  bool _applyJson(String text) {
    Map<String, dynamic> data;
    try {
      final d = jsonDecode(text);
      if (d is! Map<String, dynamic>) return false;
      data = d;
    } catch (_) {
      return false;
    }
    if (!data.containsKey('start') || !data.containsKey('gridSize')) return false;
    setState(() {
      _resetGrid(((data['gridSize'] as num?)?.toInt() ?? 5).clamp(3, 9));
      _number = (data['number'] as num?)?.toInt() ?? _number;
      _title = (data['title'] as String?) ?? '';
      _difficulty = Difficulty.values.firstWhere(
          (d) => d.name == (data['difficulty'] as String?),
          orElse: () => Difficulty.medium);
      final s = data['start'] as Map<String, dynamic>?;
      if (s != null) _startKey = _key(s['row'] as int, s['col'] as int);
      _startDir = _dir(data['startDir'] as String?) ?? Direction.right;
      final ex = data['exit'] as Map<String, dynamic>?;
      if (ex != null) _exitKey = _key(ex['row'] as int, ex['col'] as int);
      for (final w in (data['walls'] as List? ?? [])) {
        _walls.add(_key(w['row'] as int, w['col'] as int));
      }
      for (final d in (data['destroyers'] as List? ?? [])) {
        _destroyers.add(_key(d['row'] as int, d['col'] as int));
      }
      for (final f in (data['forcedArrows'] as List? ?? [])) {
        _forced[_key(f['row'] as int, f['col'] as int)] =
            _dir(f['dir'] as String?) ?? Direction.right;
      }
      final tk = (data['toolkit'] as Map<String, dynamic>?) ?? {};
      _kit[ToolType.arrowUp] = (tk['up'] as num?)?.toInt() ?? 0;
      _kit[ToolType.arrowDown] = (tk['down'] as num?)?.toInt() ?? 0;
      _kit[ToolType.arrowLeft] = (tk['left'] as num?)?.toInt() ?? 0;
      _kit[ToolType.arrowRight] = (tk['right'] as num?)?.toInt() ?? 0;
      _kit[ToolType.shield] = (tk['shield'] as num?)?.toInt() ?? 0;
      _formRev++;
    });
    return true;
  }

  /// Parse the Dart `LevelData(...)` snippet we export (also tolerates the
  /// real level_definitions.dart entries).
  bool _applyDart(String text) {
    final sizeM = RegExp(r'(?:size|gridSize)\s*:\s*(\d+)').firstMatch(text);
    final startM = RegExp(
            r'StartSpec\(\s*(?:Pos\(\s*)?(\d+)\s*,\s*(\d+)\s*\)?\s*,\s*Direction\.(\w+)')
        .firstMatch(text);
    final exitM =
        RegExp(r'exit\s*:\s*Pos\(\s*(\d+)\s*,\s*(\d+)\s*\)').firstMatch(text);
    if (sizeM == null || startM == null || exitM == null) return false;
    setState(() {
      _resetGrid(int.parse(sizeM.group(1)!).clamp(3, 9));
      final numM = RegExp(r'(\d+)\s*:\s*LevelData').firstMatch(text);
      if (numM != null) _number = int.parse(numM.group(1)!);
      final titleM = RegExp(r"title\s*:\s*'((?:[^'\\]|\\.)*)'").firstMatch(text);
      if (titleM != null) _title = titleM.group(1)!.replaceAll(r"\'", "'");
      final diffM = RegExp(r'difficulty\s*:\s*(\w+)').firstMatch(text);
      if (diffM != null) {
        _difficulty = Difficulty.values.firstWhere(
            (d) => d.name == diffM.group(1),
            orElse: () => _difficulty);
      }
      _startKey = _key(int.parse(startM.group(1)!), int.parse(startM.group(2)!));
      _startDir = _dir(startM.group(3)) ?? Direction.right;
      _exitKey = _key(int.parse(exitM.group(1)!), int.parse(exitM.group(2)!));
      void posList(String label, Set<int> into) {
        final m = RegExp('$label' r'\s*:\s*\[([^\]]*)\]').firstMatch(text);
        if (m == null) return;
        for (final pm
            in RegExp(r'Pos\(\s*(\d+)\s*,\s*(\d+)\s*\)').allMatches(m.group(1)!)) {
          into.add(_key(int.parse(pm.group(1)!), int.parse(pm.group(2)!)));
        }
      }

      posList('walls', _walls);
      posList('destroyers', _destroyers);
      final fm =
          RegExp(r'forcedArrows\s*:\s*\[([^\]]*)\]').firstMatch(text);
      if (fm != null) {
        for (final am in RegExp(
                r'ForcedArrow\(\s*(?:Pos\(\s*)?(\d+)\s*,\s*(\d+)\s*\)?\s*,\s*Direction\.(\w+)')
            .allMatches(fm.group(1)!)) {
          _forced[_key(int.parse(am.group(1)!), int.parse(am.group(2)!))] =
              _dir(am.group(3)) ?? Direction.right;
        }
      }
      final mm = RegExp(r'movers\s*:\s*\[([^\]]*)\]').firstMatch(text);
      if (mm != null) {
        for (final dm in RegExp(
                r'MovingDestroyer\(\s*(\d+)\s*,\s*(\d+)\s*,\s*horizontal:\s*(true|false)\s*(?:,\s*dir:\s*(-?\d+))?')
            .allMatches(mm.group(1)!)) {
          final r = int.parse(dm.group(1)!);
          final c = int.parse(dm.group(2)!);
          _movers[_key(r, c)] = MovingDestroyer(
            r,
            c,
            horizontal: dm.group(3) == 'true',
            dir: dm.group(4) != null ? int.parse(dm.group(4)!) : 1,
          );
        }
      }
      for (final k in _kit.keys.toList()) {
        _kit[k] = 0;
      }
      for (final em in RegExp(r'ToolkitEntry\(\s*ToolType\.(\w+)\s*,\s*(\d+)\s*\)')
          .allMatches(text)) {
        final matches = ToolType.values.where((t) => t.name == em.group(1));
        if (matches.isNotEmpty && _kit.containsKey(matches.first)) {
          _kit[matches.first] = int.parse(em.group(2)!);
        }
      }
      _formRev++;
    });
    return true;
  }

  Direction? _dir(String? s) {
    if (s == null) return null;
    for (final d in Direction.values) {
      if (d.name == s) return d;
    }
    return null;
  }

  // ----- test / solve -----
  void _test() {
    if (_startKey == null || _exitKey == null) {
      _snack('Need a Start and an Exit.');
      return;
    }
    final level = _buildLevel();
    // Moving destroyers make timing matter — only the brute solver is reliable.
    final usesBrute = level.movers.isNotEmpty;
    final sols = usesBrute ? solveAll(level) : pathSolve(level);
    final minP = usesBrute
        ? (sols.isEmpty
            ? -1
            : sols.map((m) => m.length).reduce((a, b) => a < b ? a : b))
        : pathMinPieces(level);
    final total = toolkitTotal(level);
    final solvable = sols.isNotEmpty;
    final tight = minP == total;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Solver report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stat('Solvable', solvable ? 'YES' : 'NO',
                solvable ? AppColors.completed : AppColors.coral),
            _stat('Solutions', '${sols.length}${sols.length >= 256 ? "+" : ""}',
                AppColors.ink),
            _stat('Pieces used', '$minP / $total (toolkit)', AppColors.ink),
            _stat('Tight', tight ? 'YES (no waste)' : 'NO (a piece is unused)',
                tight ? AppColors.completed : AppColors.coral),
            if (_shields.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Painted shields are design markers only — not part of the '
                  'solved level. Use the toolkit shield count for play.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSoft),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _playTest(level);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play it'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(color: AppColors.textSoft))),
            Text(value,
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );

  void _playTest(LevelData level) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(
        level: Level(
          id: _number,
          number: _number,
          title: _title.isEmpty ? 'Test' : _title,
          difficulty: _difficulty,
          status: LevelStatus.unlocked,
        ),
        levelOverride: level,
      ),
    ));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----- Find Toolkit -----

  /// Every toolkit worth trying for the current layout, ordered smallest-first
  /// (fewer pieces = a harder, more elegant puzzle): arrow-only kits before
  /// those that add a shield/pause. Capped at 5 arrows, 2 shields, 2 pauses.
  List<Map<ToolType, int>> _candidateToolkits() {
    const arrows = [
      ToolType.arrowUp,
      ToolType.arrowDown,
      ToolType.arrowLeft,
      ToolType.arrowRight,
    ];
    // Every multiset of 0..5 arrows across the four directions.
    final arrowSets = <Map<ToolType, int>>[];
    void build(int startIdx, int remaining, Map<ToolType, int> acc) {
      arrowSets.add(Map.of(acc));
      if (remaining == 0) return;
      for (var i = startIdx; i < arrows.length; i++) {
        acc[arrows[i]] = (acc[arrows[i]] ?? 0) + 1;
        build(i, remaining - 1, acc);
        acc[arrows[i]] = acc[arrows[i]]! - 1;
        if (acc[arrows[i]] == 0) acc.remove(arrows[i]);
      }
    }

    build(0, 5, {});
    final out = <Map<ToolType, int>>[];
    for (final a in arrowSets) {
      for (var s = 0; s <= 2; s++) {
        for (var p = 0; p <= 2; p++) {
          final total = a.values.fold(0, (x, y) => x + y) + s + p;
          if (total < 1) continue;
          final kit = Map<ToolType, int>.of(a);
          if (s > 0) kit[ToolType.shield] = s;
          if (p > 0) kit[ToolType.pause] = p;
          out.add(kit);
        }
      }
    }
    int total(Map<ToolType, int> k) => k.values.fold(0, (x, y) => x + y);
    int specials(Map<ToolType, int> k) =>
        (k[ToolType.shield] ?? 0) + (k[ToolType.pause] ?? 0);
    out.sort((a, b) {
      final t = total(a).compareTo(total(b));
      if (t != 0) return t; // smallest kits first
      return specials(a).compareTo(specials(b)); // arrows-only before shield/pause
    });
    return out;
  }

  /// The current layout with a different toolkit swapped in.
  LevelData _withToolkit(LevelData base, Map<ToolType, int> kit) => LevelData(
        id: base.id,
        size: base.size,
        title: base.title,
        tip: base.tip,
        start: base.start,
        exit: base.exit,
        walls: base.walls,
        destroyers: base.destroyers,
        forcedArrows: base.forcedArrows,
        movers: base.movers,
        toolkit: [for (final e in kit.entries) ToolkitEntry(e.key, e.value)],
      );

  String _kitLabel(Map<ToolType, int> kit) {
    const order = [
      ToolType.arrowUp,
      ToolType.arrowDown,
      ToolType.arrowLeft,
      ToolType.arrowRight,
      ToolType.shield,
      ToolType.pause,
    ];
    String name(ToolType t) => switch (t) {
          ToolType.arrowUp => 'Up',
          ToolType.arrowDown => 'Down',
          ToolType.arrowLeft => 'Left',
          ToolType.arrowRight => 'Right',
          ToolType.shield => 'Shield',
          ToolType.pause => 'Pause',
          _ => t.name,
        };
    final parts = [
      for (final t in order)
        if ((kit[t] ?? 0) > 0) '${kit[t]}× ${name(t)}',
    ];
    return parts.join(' + ');
  }

  /// Search toolkit combinations (smallest first) for the FIRST that makes the
  /// current layout solvable AND tight. [again] resumes after the last hit so
  /// "Try Another" surfaces the next valid toolkit. Runs async with yields so
  /// the spinner animates; a per-solve cost guard keeps it responsive.
  Future<void> _findToolkit({bool again = false}) async {
    if (_finding) return;
    if (_startKey == null || _exitKey == null) {
      _snack('Need a Start and an Exit.');
      return;
    }
    setState(() {
      _finding = true;
      _findResult = null;
      _findOk = false;
      if (!again) {
        _foundKit = null;
        _candidates = _candidateToolkits();
        _candCursor = 0;
      }
    });
    final base = _buildLevel(); // layout fixed; toolkit varies
    final placeable = placeableCells(base).length;
    Map<ToolType, int>? found;
    var solutions = 0;
    var i = _candCursor;
    for (; i < _candidates.length; i++) {
      if (i % 8 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (!mounted) return;
      }
      final kit = _candidates[i];
      // Constraint filter: skip toolkits that don't match the user's requirements.
      if (_cMustShield && (kit[ToolType.shield] ?? 0) == 0) continue;
      if (_cMustPause && (kit[ToolType.pause] ?? 0) == 0) continue;
      final total = kit.values.fold(0, (a, b) => a + b);
      final level = _withToolkit(base, kit);
      // The fast path solver handles static, pause-free layouts; timing hazards
      // (movers) or pauses need the brute solver, bounded so it stays responsive.
      final usePath =
          base.movers.isEmpty && !kit.containsKey(ToolType.pause);
      final int minP;
      final int count;
      if (usePath) {
        final sols = pathSolve(level);
        if (sols.isEmpty) continue;
        count = sols.length;
        minP = pathMinPieces(level);
      } else {
        if (placeable == 0 || math.pow(placeable, total) > 5e5) continue;
        final sols = solveAll(level);
        if (sols.isEmpty) continue;
        count = sols.length;
        minP = sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
      }
      if (minP == total) {
        found = kit;
        solutions = count;
        i++; // resume past this one next time
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _finding = false;
      _candCursor = i;
      _foundKit = found;
      _findOk = found != null;
      _findResult = found != null
          ? 'Found: ${_kitLabel(found)}  →  $solutions solution(s), TIGHT'
          : (again
              ? 'No more valid toolkits for this layout.'
              : 'No valid toolkit found for this layout.');
    });
  }

  /// Apply the found toolkit to the level's toolkit counters.
  void _acceptToolkit() {
    final kit = _foundKit;
    if (kit == null) return;
    setState(() {
      for (final k in _kit.keys.toList()) {
        _kit[k] = kit[k] ?? 0;
      }
    });
    _snack('Toolkit set — tweak with the counters, then Test or Export.');
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.ink,
        title: const Text('Level Designer',
            style: TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _metaRow(),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AspectRatio(aspectRatio: 1, child: _board()),
                ),
              ),
              const SizedBox(height: 14),
              _sectionLabel(
                  'Palette  ·  tap Start/Forced to rotate, Patrol to cycle '
                  'axis + direction'),
              const SizedBox(height: 8),
              _palette(),
              const SizedBox(height: 16),
              _findToolkitPanel(),
              const SizedBox(height: 16),
              _sectionLabel('Toolkit (given to player)'),
              const SizedBox(height: 8),
              _toolkitEditor(),
              const SizedBox(height: 18),
              _buttons(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(s,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: AppColors.textSoft));

  // ----- Find Toolkit panel -----
  Widget _findToolkitPanel() {
    final ready = _startKey != null && _exitKey != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded, color: AppColors.ink, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Find Toolkit',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              FilledButton.icon(
                onPressed: (ready && !_finding) ? () => _findToolkit() : null,
                icon: _finding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search_rounded),
                label: Text(_finding ? 'Searching…' : 'Find Toolkit'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Design the layout above, then let the solver find the smallest '
            'toolkit that makes it solvable and tight.',
            style: const TextStyle(fontSize: 11, color: AppColors.textSoft),
          ),
          const SizedBox(height: 8),
          _sectionLabel('Constraints'),
          const SizedBox(height: 4),
          // Changing any constraint restarts the search from the top.
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _constraintCheck('Must include Shield', _cMustShield,
                  (v) => setState(() {
                        _cMustShield = v;
                        _resetFindCursor();
                      })),
              _constraintCheck('Must include Pause', _cMustPause,
                  (v) => setState(() {
                        _cMustPause = v;
                        _resetFindCursor();
                      })),
            ],
          ),
          if (_findResult != null) ...[
            const SizedBox(height: 10),
            Text(
              _findResult!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _findOk ? AppColors.completed : AppColors.coral,
              ),
            ),
          ],
          if (_findOk && !_finding) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _acceptToolkit,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _findToolkit(again: true),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Try Another'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Restart the "Try Another" search and clear the last result — used whenever
  /// a constraint changes so the next Find respects the new filter from the top.
  void _resetFindCursor() {
    _candCursor = 0;
    _foundKit = null;
    _findOk = false;
    _findResult = null;
  }

  Widget _constraintCheck(
      String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => onChanged(v ?? false),
          ),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _metaRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _labeled(
          'Size',
          DropdownButton<int>(
            value: _n,
            items: [for (var i = 3; i <= 9; i++) i]
                .map((i) =>
                    DropdownMenuItem(value: i, child: Text('$i × $i')))
                .toList(),
            onChanged: (v) => setState(() => _resetGrid(v!)),
          ),
        ),
        _labeled(
          'Level #',
          SizedBox(
            width: 64,
            child: TextFormField(
              key: ValueKey('num$_formRev'),
              initialValue: '$_number',
              keyboardType: TextInputType.number,
              onChanged: (v) => _number = int.tryParse(v) ?? _number,
            ),
          ),
        ),
        _labeled(
          'Title',
          SizedBox(
            width: 160,
            child: TextFormField(
              key: ValueKey('title$_formRev'),
              initialValue: _title,
              decoration: const InputDecoration(hintText: 'Title'),
              onChanged: (v) => _title = v,
            ),
          ),
        ),
        _labeled(
          'Difficulty',
          DropdownButton<Difficulty>(
            value: _difficulty,
            items: Difficulty.values
                .map((d) =>
                    DropdownMenuItem(value: d, child: Text(d.label)))
                .toList(),
            onChanged: (v) => setState(() => _difficulty = v!),
          ),
        ),
      ],
    );
  }

  Widget _labeled(String label, Widget child) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.6,
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w700)),
          child,
        ],
      );

  Widget _board() {
    final level = _buildLevel();
    return LayoutBuilder(builder: (ctx, con) {
      final side = con.maxWidth;
      return GestureDetector(
        key: const ValueKey('designerBoard'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final cell = GridGeometry(side, _n).cellAt(d.localPosition);
          if (cell != null) _paintCell(cell.$1, cell.$2);
        },
        child: CustomPaint(
          size: Size.square(side),
          painter: GameGridPainter(
            level: level,
            placed: {..._shieldPieces()},
            forced: _forcedPieces(),
            trail: const [],
            movers: _movers.values.toList(),
            revision: _walls.length * 1000 +
                _destroyers.length * 100 +
                _forced.length * 10 +
                _shields.length +
                _movers.length * 10000,
            placeAnim: const {},
            removing: const [],
            cellGlow: const {},
            cellGlowColor: const {},
            cellPulse: const {},
            explosions: const [],
            destroyedCells: const {},
            glowTick: 0,
            showStartHint: true,
            winProgress: 0,
          ),
        ),
      );
    });
  }

  Widget _palette() {
    const items = [
      (DesignTool.empty, 'Empty', Icons.cleaning_services_rounded),
      (DesignTool.start, 'Start', Icons.play_arrow_rounded),
      (DesignTool.exit, 'Exit', Icons.flag_rounded),
      (DesignTool.wall, 'Wall', Icons.crop_square_rounded),
      (DesignTool.destroyer, 'Destroyer', Icons.dangerous_rounded),
      (DesignTool.forced, 'Forced', Icons.double_arrow_rounded),
      (DesignTool.shield, 'Shield', Icons.shield_rounded),
      (DesignTool.mover, 'Patrol', Icons.sync_alt_rounded),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (tool, label, icon) in items)
          _paletteChip(tool, label, icon),
      ],
    );
  }

  static const _palColors = {
    DesignTool.empty: Color(0xFF9A958C),
    DesignTool.start: Color(0xFF81C784),
    DesignTool.exit: Color(0xFFFFD54F),
    DesignTool.wall: Color(0xFF78909C),
    DesignTool.destroyer: Color(0xFFEF5350),
    DesignTool.forced: Color(0xFF607D8B),
    DesignTool.shield: Color(0xFF38BDF8),
    DesignTool.mover: Color(0xFFE53935),
  };

  Widget _paletteChip(DesignTool tool, String label, IconData icon) {
    final sel = _tool == tool;
    final color = _palColors[tool]!;
    return GestureDetector(
      onTap: () => setState(() => _tool = tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? color.withValues(alpha: 0.18) : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? AppColors.ink : AppColors.border,
            width: sel ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _toolkitEditor() {
    const tools = [
      (ToolType.arrowUp, '↑ Up'),
      (ToolType.arrowDown, '↓ Down'),
      (ToolType.arrowLeft, '← Left'),
      (ToolType.arrowRight, '→ Right'),
      (ToolType.shield, '◯ Shield'),
      (ToolType.pause, '⏸ Pause'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (type, label) in tools) _counter(type, label),
      ],
    );
  }

  Widget _counter(ToolType type, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(width: 8),
          _stepBtn('–', () {
            setState(() => _kit[type] = (_kit[type]! - 1).clamp(0, 99));
          }),
          SizedBox(
            width: 22,
            child: Text('${_kit[type]}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          _stepBtn('+', () {
            setState(() => _kit[type] = (_kit[type]! + 1).clamp(0, 99));
          }),
        ],
      ),
    );
  }

  Widget _stepBtn(String s, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(s,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
        ),
      );

  Widget _buttons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: _test,
          icon: const Icon(Icons.science_rounded),
          label: const Text('Test'),
        ),
        OutlinedButton.icon(
          onPressed: _export,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Export Dart'),
        ),
        OutlinedButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.paste_rounded),
          label: const Text('Import'),
        ),
      ],
    );
  }
}
