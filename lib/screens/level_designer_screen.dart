import 'dart:convert';

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
enum DesignTool { empty, start, exit, wall, destroyer, forced, shield }

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

  final Map<ToolType, int> _kit = {
    ToolType.arrowUp: 0,
    ToolType.arrowDown: 0,
    ToolType.arrowLeft: 0,
    ToolType.arrowRight: 0,
    ToolType.shield: 0,
  };

  DesignTool _tool = DesignTool.wall;
  Direction _paintDir = Direction.right;

  int _number = 16;
  String _title = '';
  Difficulty _difficulty = Difficulty.medium;

  /// Bumped on import so the text fields rebuild with their new initial values.
  int _formRev = 0;

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
    return null;
  }

  void _clearMovable(int k) {
    _walls.remove(k);
    _destroyers.remove(k);
    _forced.remove(k);
    _shields.remove(k);
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
    final sols = pathSolve(level);
    final minP = pathMinPieces(level);
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
              _sectionLabel('Palette  ·  tap Start/Forced again to rotate'),
              const SizedBox(height: 8),
              _palette(),
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
            revision: _walls.length * 1000 +
                _destroyers.length * 100 +
                _forced.length * 10 +
                _shields.length,
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
