import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ads/ad_manager.dart';
import '../ads/ad_pacing.dart';
import '../services/challenge_service.dart';
import '../services/cloud_save_service.dart';
import '../services/free_hint_service.dart';
import '../services/game_services.dart';
import '../settings/haptics.dart';
import '../analytics/analytics_service.dart';
import '../audio/sfx.dart';
import '../data/level_definitions.dart';
import '../data/level_hints.dart';
import '../data/levels.dart';
import '../engine/simulator.dart'
    show
        adjacentWallKeys,
        buildForcedPieces,
        buildMovers,
        buildRotations,
        buildPortalPairs,
        buildTeleportLinks,
        DeathCause,
        MoverState,
        moversCrossed;
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level.dart';
import '../models/challenge.dart';
import '../models/level_data.dart';
import '../progress/progress_store.dart';
import '../theme/app_theme.dart';
import '../utils/dev_mode.dart';
import '../widgets/bouncy_button.dart';
import '../services/notification_service.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/notification_prompt_dialog.dart';
import '../widgets/game_grid.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/top_bar.dart';
import 'level_designer_screen.dart';

/// Milliseconds between dot movement ticks.
const _tickMs = 400;

/// Fixed height reserved for the bottom button area (the hint line + Play, the
/// win pause, or Continue/Back to Menu). Pinning it keeps the grid above from
/// shifting as the footer swaps between these states.
const double _kFooterHeight = 82;

/// The core game screen. For levels with a definition it is fully playable;
/// otherwise it shows a "coming soon" placeholder.
///
/// Drag-and-drop is implemented manually with pan gestures on a top-level
/// [GestureDetector] (no [DragTarget]) so all coordinate math is under our
/// control — reliable across platforms including web.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.level,
    this.levelOverride,
    this.challenge,
  });

  final Level level;

  /// When set (the dev level designer, and challenges), the screen plays this
  /// level definition directly instead of looking it up by number. Progress is
  /// not recorded and there is no "next level" — which is exactly what a
  /// challenge wants too, so challenges ride on the same path rather than
  /// needing their own exception in the win handler.
  final LevelData? levelOverride;

  /// Set when this board is a weekly challenge. Completion is recorded against
  /// the challenge instead of the campaign.
  final Challenge? challenge;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  LevelData? _level;

  final Map<int, PlacedElement> _placed = {};

  bool _hintRunning = false;
  Timer? _idleTimer;

  /// Repaints the hint button while the free hint regenerates, so the countdown
  /// on it stays honest. Minute resolution — the label never shows seconds.
  Timer? _hintClock;

  /// Immovable, level-defined arrows (rendered + simulated, never interactive).
  final Map<int, PlacedElement> _forced = {};

  /// Rotating arrows: cell -> current heading. Seeded from the level and
  /// advanced a quarter-turn clockwise each time the dot passes through; reset
  /// to the level's initial headings on Retry.
  final Map<int, Direction> _rotations = {};

  Map<ToolType, int> _kit = {};
  ToolType? _selected;

  GameStatus _status = GameStatus.planning;
  late DotState _dot;

  /// Ordered list of visited cells (most recent last) for the fading trail.
  final List<int> _trail = [];

  /// Why the dot died, shown prominently on the fail overlay.
  DeathCause? _deathCause;

  Timer? _timer;
  late final AnimationController _dotCtrl; // per-step glide + squish
  late final Animation<double> _dotScale; // arrival squish
  late final AnimationController _teleportCtrl; // one phase of a teleport
  late final AnimationController _moverCtrl; // patrol glide (every beat)
  late final AnimationController _spinCtrl; // a rotating arrow's quarter-turn

  /// The rotating arrow currently mid-turn, if any. [_rotations] keeps the
  /// pre-turn heading until the turn lands — the painter swings the glyph off it.
  int? _spinCell;

  /// A rotating arrow that has redirected the dot and now owes its quarter-turn:
  /// (cell, the heading it sent the dot). The turn plays once the dot LEAVES the
  /// cell, so the arrow swings shut behind it rather than under it.
  (int, Direction)? _pendingSpin;

  /// A one-shot arrow the dot has just turned on, which owes its disappearance.
  /// Like the rotating arrow's quarter-turn, it plays once the dot has LEFT the
  /// cell, so the board changes behind the dot rather than under it.
  int? _pendingOneShot;

  /// Teleport animation state. [_teleporting] gates the whole overlay; while it
  /// runs, [_teleportGrowing] is false during the shrink-out at the entrance and
  /// true during the grow-in at the exit. The two ring cells and the pair colour
  /// are fixed for the duration.
  bool _teleporting = false;
  bool _teleportGrowing = false;
  (int, int)? _teleportEntrance;
  (int, int)? _teleportExit;
  Color _teleportColor = const Color(0xFFFF8A65);
  late final AnimationController _glowCtrl; // continuous fx driver
  (int, int) _animFrom = (0, 0);
  (int, int) _animTo = (0, 0);

  // Visual effect state, advanced each frame in [_onFxTick].
  final Map<int, double> _placeAnim = {}; // cell → pop-in progress
  final List<FadingPiece> _removing = []; // shrinking-away pieces
  final Map<int, double> _cellGlow = {}; // cell → glow intensity
  final Map<int, Color> _cellGlowColor = {};
  final Map<int, double> _cellPulse = {}; // cell → neighbor ripple progress
  final List<Explosion> _explosions = []; // destroyer blasts in progress
  final Set<int> _destroyedCells = {}; // destroyers cleared by a shielded dot
  final Set<int> _consumedShields = {}; // shield cells picked up this run
  final Set<int> _spentOneShots = {}; // one-shot arrows used up this run

  /// True once the dot has the protective shield aura (consumed by a destroyer).
  bool _dotShielded = false;

  /// True once the dot has been blown up (hidden during the fatal explosion).
  bool _dotGone = false;

  /// Runtime patrol (moving destroyer) state + their pre-step cells (for glide).
  List<MoverState> _movers = [];
  List<(int, int)> _moverFrom = [];

  // Win celebration: grid fades out, a full celebration screen fades in.
  late final AnimationController _winCtrl;
  bool _celebrationDone = false;

  /// Set when a completed level makes an interstitial due; spent by the next
  /// transition off the celebration screen.
  bool _interstitialDue = false;

  /// What the just-finished challenge paid out, for the celebration line.
  ChallengeReward _challengeReward = ChallengeReward.none;
  String _winMessage = '';

  // Level-2 tutorial: a ghost hand that drags the Up arrow onto the cell.
  late final AnimationController _handCtrl;

  /// Drives the hint button's shake once the player has gone quiet.
  late final AnimationController _wiggleCtrl;
  Timer? _handTimer;
  bool _showHand = false;
  static const _tutorialCell = (2, 2); // solution cell for level 2

  static const _winMessages = [
    'Nailed it!',
    'Perfect!',
    'Well done!',
    'Brilliant!',
    'Smooth!',
    'Nice one!',
  ];

  // "Magnet snap": the dropped ghost flies into the target cell, then pops in.
  late final AnimationController _snapCtrl;
  ToolType? _snapTool; // tool to place when the snap finishes
  PlacedElement? _snapPiece; // moved piece to drop when the snap finishes
  int? _snapKey; // target cell
  Offset? _snapFrom; // drop position (global)
  Offset? _snapTo; // target cell center (global)

  /// Board Stack render key, for global<->local coordinate conversion.
  final GlobalKey _boardKey = GlobalKey();

  /// Root Stack key, for positioning the floating drag ghost.
  final GlobalKey _rootKey = GlobalKey();

  /// One key per toolkit tile, so a pan can be matched to the tile it began on.
  final Map<ToolType, GlobalKey> _toolKeys = {};

  // Manual-drag state.
  ToolType? _dragTool; // tool being dragged from the toolbar (place new)
  PlacedElement? _dragPiece; // a placed piece picked up off the grid (move)
  int? _dragOriginKey; // the cell the picked-up piece came from
  Offset? _dragGlobal; // current pointer position (global)

  // Live placement preview (valid empty cell under the pointer).
  (int, int)? _hoverCell;
  ToolType? _hoverTool;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _moverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..value = 1;
    // Brief squish: stays at 1.0, then pops to 1.15 and settles on arrival.
    _dotScale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.15).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 22,
      ),
    ]).animate(_dotCtrl);
    // Always-running driver for the dot's glow pulse and cell effect decay.
    _teleportCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    // One quarter-turn of a rotating arrow — the beat is held while it plays.
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _glowCtrl.addListener(_onFxTick);
    // Quick magnet-snap of the dropped ghost into the cell.
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _snapCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishSnap();
    });
    _winCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _winCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _celebrationDone = true);
      }
    });
    // ~3 loops of the tutorial hand, then a fade.
    _handCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
    // One full shake per cycle, at the ~0.5s period the wobble wants.
    _wiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _handCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showHand = false);
      }
    });
    _level = widget.levelOverride ?? levelDataFor(widget.level.number);
    if (_level != null) {
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      for (final e in _level!.toolkit) {
        _toolKeys[e.type] = GlobalKey();
      }
      // Fixed arrows, shields and pauses alike. Note _canPlace/_canDropAt do
      // NOT gate on this map — they ask the level, which also knows about the
      // rotating arrows that never reach _forced. See _occupied.
      _forced.addAll(buildForcedPieces(_level!));
      _rotations.addAll(buildRotations(_level!));
      _selected = _level!.toolkit.isNotEmpty ? _level!.toolkit.first.type : null;
      _resetDot();
      if (widget.levelOverride == null) {
        _levelStartedAt = DateTime.now();
        Analytics.levelStart(_level!.id, worldOf(_level!.id));
      }
      // The free hint is a daily allowance now, held by FreeHintService, so
      // there is nothing per-level to reset. The idle clock still starts here:
      // a player who opens a level and never touches it is who the nudge is for.
      _noteActivity();
      _startHintClock();
      // Level 2 teaches drag-and-drop: show the hint hand after a beat.
      if (_level!.id == 2) {
        _handTimer = Timer(const Duration(seconds: 2), _startHand);
      }
    }
  }

  void _startHand() {
    if (!mounted || _placed.isNotEmpty || _status != GameStatus.planning) return;
    setState(() => _showHand = true);
    _handCtrl.forward(from: 0);
  }

  // ----- analytics -----

  /// When this visit to the level began, for the completion time. Reset by
  /// Retry as well as by loading a level, so the number means "how long the
  /// winning attempt took" rather than how long the app has been open.
  DateTime _levelStartedAt = DateTime.now();
  int _attempts = 0;
  int _hintsThisLevel = 0;

  void _reportWin() {
    final id = _level!.id;
    final world = worldOf(id);
    Analytics.levelComplete(
      id,
      world,
      timeSeconds: DateTime.now().difference(_levelStartedAt).inSeconds,
      hintsUsed: _hintsThisLevel,
    );

    final completed = ProgressStore.completed();
    Analytics.setProgress(
      levelsCompleted: completed.length,
      currentWorld: world,
    );
    // The first level of a world is what opens it, so finishing the one before
    // it is the moment the next world becomes reachable.
    if (id < kLevelCount && worldOf(id + 1) != world) {
      Analytics.worldUnlocked(worldOf(id + 1));
    }
    if (completed.length >= kLevelCount) Analytics.gameCompleted();

    CloudSaveService.save();
    GameServices.onLevelCompleted(
      world: world,
      worldFinished: isWorldComplete(world, completed),
      totalCompleted: completed.length,
      levelCount: kLevelCount,
      lifetimeHints: ProgressStore.hintsUsed(),
    );
  }

  void _reportFail() {
    // Counted for every board, including challenges and designer previews —
    // the fail overlay decides whether to offer a hint from this, and a
    // challenge player gets stuck exactly like anyone else. Only the analytics
    // event is campaign-only.
    _attempts++;
    if (widget.levelOverride != null) return;
    Analytics.levelFail(_level!.id, worldOf(_level!.id), _attempts);
  }

  /// Whether the fail overlay should offer a hint.
  ///
  /// Never on the first fail: losing once is how the level teaches itself, and
  /// an offer of help before the player has thought about it reads as the game
  /// assuming they cannot do it.
  ///
  /// The availability test is against the *recorded solution*, not the current
  /// board. By the time a run has failed the player has usually placed every
  /// piece they own, so the kit is empty and [_nextHint] finds nothing — asking
  /// it here would hide the offer in precisely the situation it exists for.
  /// [_onFailHintPressed] clears the board first, which puts the pieces back.
  bool get _offerHintOnFail =>
      _attempts >= 2 &&
      _level != null &&
      recordedSolution(_level!.id).isNotEmpty;

  // ----- hints -----

  /// How long a player can sit doing nothing before the hint button starts
  /// asking for attention.
  static const _idleBeforeWiggle = Duration(seconds: 30);

  /// The next placement to give away: the first one in the recorded solution
  /// the player has not made, and still has the piece for.
  ///
  /// Skipping cells that are already occupied means a hint never fights the
  /// player for a square — but it also means the hint only completes a winning
  /// board if what is already down is right. A hint is a nudge toward the
  /// recorded solution, not a promise that the current board can still reach it.
  HintPlacement? _nextHint() {
    final level = _level;
    if (level == null) return null;
    for (final p in recordedSolution(level.id)) {
      if (_occupied(p.r, p.c)) continue;
      if ((_kit[p.element.tool] ?? 0) <= 0) continue;
      return p;
    }
    return null;
  }

  bool get _hintAvailable =>
      _status == GameStatus.planning && !_hintRunning && _nextHint() != null;

  /// Restart the idle clock and call off any wiggle. Every player action that
  /// counts as "still thinking about this level" routes through here.
  void _noteActivity() {
    _idleTimer?.cancel();
    if (_wiggleCtrl.isAnimating) {
      _wiggleCtrl.stop();
      _wiggleCtrl.value = 0;
    }
    if (!mounted || _status != GameStatus.planning) return;
    _idleTimer = Timer(_idleBeforeWiggle, () {
      // Nothing to point at, or nothing to point with: stay still rather than
      // wave at a button that cannot help.
      if (!mounted || !_hintAvailable) return;
      _wiggleCtrl.repeat();
    });
  }

  /// Hints the player can spend right now: the daily one if it has come back,
  /// plus anything won from challenges.
  int get _hintsInHand =>
      (FreeHintService.available ? 1 : 0) + ChallengeService.bonusHints;

  /// "14h 32m" while the daily hint regenerates, empty when one is ready.
  String get _freeHintCountdown => FreeHintService.remainingLabel(
        DateTime.now(),
      );

  /// Tick the button once a minute while the countdown is showing, and stop as
  /// soon as it is not — a timer running behind a static label is just battery.
  void _startHintClock() {
    _hintClock?.cancel();
    if (FreeHintService.available) return;
    _hintClock = Timer.periodic(const Duration(minutes: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {});
      if (FreeHintService.available) t.cancel();
    });
  }

  Future<void> _onHintPressed() async {
    if (!_hintAvailable) return;
    _noteActivity();
    if (await _payForHint()) await _revealHint();
  }

  /// Take payment for one hint, in the order that costs the player least.
  ///
  /// Free hint, then anything won from a challenge, then an ad. Returns whether
  /// a hint was actually paid for — false means the player declined the ad or
  /// none could be served, and nothing should be revealed.
  ///
  /// Shared with the fail overlay so both routes charge identically; two copies
  /// of this would eventually disagree about who pays what.
  Future<bool> _payForHint() async {
    final id = _level!.id;
    final world = worldOf(id);
    if (FreeHintService.spend()) {
      // Start the countdown ticking so the button stops claiming a hint it no
      // longer has.
      setState(_startHintClock);
      // Queue the "it's back" reminder for the moment it actually returns. Not
      // awaited: the hint has already been spent and the player is waiting to
      // see it, so scheduling must not sit in front of that.
      unawaited(NotificationService.scheduleHintReady(DateTime.now()));
      _noteHintTaken(id, world, 'free');
      return true;
    }
    // Hints won from challenges are spent before an ad is ever offered — a
    // player who earned one should not be asked to watch a video to use it.
    if (ChallengeService.spendBonusHint()) {
      setState(() {});
      _noteHintTaken(id, world, 'bonus');
      return true;
    }
    if (await _offerAd() && mounted) {
      _noteHintTaken(id, world, 'ad');
      return true;
    }
    return false;
  }

  /// "Use Hint" on the fail overlay.
  ///
  /// The board is cleared first, then the piece is placed onto it. Clearing is
  /// what makes this work at all: a failed run usually has every piece already
  /// down, and a hint has nowhere to go until they are back in the kit. It also
  /// gives the player a clean board with one square settled, which is a better
  /// place to think from than a wrong arrangement with a correction bolted on.
  ///
  /// Declining the ad leaves them on the overlay with Try Again — nothing is
  /// cleared, so refusing costs them nothing.
  Future<void> _onFailHintPressed() async {
    if (_hintRunning) return;
    if (!await _payForHint()) return;
    if (!mounted) return;
    _clearAll(); // returns every placed piece to the kit and resets the dot
    await _revealHint();
  }

  void _noteHintTaken(int levelId, int worldId, String type) {
    _hintsThisLevel++;
    ProgressStore.bumpHintsUsed();
    Analytics.hintUsed(levelId, worldId, type);
    Analytics.setHintsUsedTotal(ProgressStore.hintsUsed());
    GameServices.onHintUsed(ProgressStore.hintsUsed());
    CloudSaveService.save();
  }

  /// Ask for the hint back in exchange for an ad, and return whether it was
  /// earned.
  ///
  /// The confirmation comes first: a video that starts the instant a button is
  /// pressed feels like a trap. Only after the player agrees is the ad shown.
  ///
  /// When no ad can be served — offline, no fill, the SDK never started, or
  /// running on web where there is no AdMob at all — the hint is given anyway.
  /// The alternative is a player stuck behind an ad that will never arrive,
  /// which punishes them for a failure that is entirely ours.
  Future<bool> _offerAd() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.ink, width: 3),
        ),
        title: const Text('Watch an ad for a hint?'),
        content: const Text(
          'Your free hint for this level is used up. Watch a short video to '
          'reveal another piece.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Watch'),
          ),
        ],
      ),
    );
    if (agreed != true) return false;

    final id = _level!.id;
    final world = worldOf(id);
    // No ad to show — the hint is granted, but nothing is reported as watched,
    // so the ad funnel keeps meaning what it says.
    if (!AdManager.supported || !AdManager.rewardedReady) return true;

    Analytics.rewardedAdShown(id);
    final earned = await AdManager.showRewarded();
    if (earned) {
      Analytics.hintAdWatched(id, world);
    } else {
      Analytics.hintAdDismissed(id, world);
    }
    return earned;
  }

  /// Pulse the target cell in gold, then drop the piece on it.
  Future<void> _revealHint() async {
    final hint = _nextHint();
    if (hint == null) return;
    final key = _idx(hint.r, hint.c);
    setState(() => _hintRunning = true);
    Sfx.shield(); // the rising shimmer — reads as "look here"

    // Three beats of gold before the piece lands, so the eye arrives at the
    // cell ahead of the placement instead of chasing it.
    for (var i = 0; i < 3; i++) {
      _glow(key, AppColors.accent, 1.0);
      _cellPulse[key] = 0;
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted || _status != GameStatus.planning) {
        if (mounted) setState(() => _hintRunning = false);
        return;
      }
      // The player may have filled the cell while the pulse ran.
      if (_occupied(hint.r, hint.c)) {
        setState(() => _hintRunning = false);
        return;
      }
    }
    setState(() => _hintRunning = false);
    // Goes through the same funnel as a drop, so the kit count, the pop-in and
    // the neighbour ripple all behave exactly as if the player had placed it.
    _commitPlace(key, hint.element, decrementKit: true);
  }

  /// The hint button: a lightbulb with either the free-hint count or a video
  /// icon, wobbling once the player has been still for a while.
  ///
  /// It greys out rather than disappearing when there is nothing left to
  /// reveal — a control that vanishes mid-level reads as a bug.
  Widget _buildHintButton() {
    final enabled = _hintAvailable;
    return AnimatedBuilder(
      animation: _wiggleCtrl,
      builder: (context, child) {
        // A full sine cycle per repeat: ±5° and, importantly, exactly zero at
        // value 0 — so a stopped controller leaves the button upright rather
        // than parked at one end of the shake.
        final swing = math.sin(_wiggleCtrl.value * 2 * math.pi) * 0.09;
        return Transform.rotate(
          key: const ValueKey('hint-wiggle'),
          angle: swing,
          child: child,
        );
      },
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: BorderedTile(
          background: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: enabled ? _onHintPressed : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 5),
              // Three states, in the order the player meets them: how many
              // hints they have, how long until the next free one, or the ad
              // that is the only way to get one sooner.
              if (_hintsInHand > 0)
                // "×1", not a bare "1" — it reads as a quantity the way the
                // toolkit tiles do, and does not collide with their counts.
                // Free and challenge-won hints are one number: the player has
                // no reason to care which kind gets spent first.
                Text('×$_hintsInHand',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800))
              else if (_freeHintCountdown.isNotEmpty)
                Text(_freeHintCountdown,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800))
              else
                const Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Stop the tutorial hand for good once the player interacts.
  void _stopHand() {
    _handTimer?.cancel();
    _handTimer = null;
    if (_showHand) {
      _handCtrl.stop();
      setState(() => _showHand = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _handTimer?.cancel();
    _idleTimer?.cancel();
    _hintClock?.cancel();
    _wiggleCtrl.dispose();
    _dotCtrl.dispose();
    _teleportCtrl.dispose();
    _spinCtrl.dispose();
    _moverCtrl.dispose();
    _glowCtrl.dispose();
    _snapCtrl.dispose();
    _winCtrl.dispose();
    _handCtrl.dispose();
    super.dispose();
  }

  int _idx(int r, int c) => r * _level!.size + c;

  /// The cell's type accounting for chain-exploded cells (cleared walls and
  /// destroyers read as empty/passable).
  CellType _effBase(int r, int c) => _destroyedCells.contains(_idx(r, c))
      ? CellType.empty
      : _level!.baseTypeAt(r, c);

  int get _revision => _placed.length * 10000 + _trail.length;

  /// Number of toolkit pieces not yet placed (0 once the kit is fully used).
  int get _remainingPieces => _kit.values.fold(0, (sum, c) => sum + c);

  /// Advance per-frame visual effects (called on every [_glowCtrl] tick).
  void _onFxTick() {
    const dt = 1 / 60;
    if (_placeAnim.isNotEmpty) {
      final done = <int>[];
      _placeAnim.updateAll((k, v) => v + dt / 0.60); // ~600ms leisurely bounce
      _placeAnim.forEach((k, v) {
        if (v >= 1) done.add(k);
      });
      for (final k in done) {
        _placeAnim.remove(k);
      }
    }
    if (_cellPulse.isNotEmpty) {
      final done = <int>[];
      _cellPulse.updateAll((k, v) => v + dt / 0.40); // ~400ms ripple
      _cellPulse.forEach((k, v) {
        if (v >= 1) done.add(k);
      });
      for (final k in done) {
        _cellPulse.remove(k);
      }
    }
    if (_removing.isNotEmpty) {
      for (final f in _removing) {
        f.progress += dt / 0.15;
      }
      _removing.removeWhere((f) => f.progress >= 1);
    }
    if (_cellGlow.isNotEmpty) {
      final gone = <int>[];
      _cellGlow.updateAll((k, v) => v - 0.022); // ~500ms lingering flash
      _cellGlow.forEach((k, v) {
        if (v <= 0) gone.add(k);
      });
      for (final k in gone) {
        _cellGlow.remove(k);
        _cellGlowColor.remove(k);
      }
    }
    if (_explosions.isNotEmpty) {
      // ~0.5s blast. The board AnimatedBuilder repaints every frame (glowTick),
      // so mutating progress here is enough — no setState needed.
      _explosions.removeWhere((e) {
        e.t += dt / 0.5;
        return e.t >= 1;
      });
    }
  }

  void _glow(int key, Color color, [double intensity = 0.85]) {
    _cellGlow[key] = intensity;
    _cellGlowColor[key] = color;
  }

  /// Kick a ripple pulse on the cells orthogonally adjacent to [key].
  void _rippleNeighbors(int key) {
    final n = _level!.size;
    final r = key ~/ n;
    final c = key % n;
    for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final nr = r + dr, nc = c + dc;
      if (nr >= 0 && nr < n && nc >= 0 && nc < n) {
        _cellPulse[nr * n + nc] = 0;
      }
    }
  }

  // ----- dot / animation -----

  void _resetDot() {
    _timer?.cancel();
    _timer = null;
    _teleportCtrl.stop();
    _teleporting = false;
    _spinCtrl.stop();
    _spinCtrl.value = 0;
    _spinCell = null;
    _pendingSpin = null;
    _pendingOneShot = null;
    final s = _level!.start;
    _status = GameStatus.planning;
    _dot = DotState(r: s.r, c: s.c, dir: s.dir);
    _trail
      ..clear()
      ..add(_idx(s.r, s.c));
    _cellGlow.clear();
    _cellGlowColor.clear();
    _cellPulse.clear();
    _removing.clear();
    _explosions.clear();
    _destroyedCells.clear();
    _consumedShields.clear();
    _spentOneShots.clear();
    // Rotating arrows spin back to their level-defined starting headings.
    _rotations
      ..clear()
      ..addAll(buildRotations(_level!));
    _dotShielded = false;
    _dotGone = false;
    _movers = buildMovers(_level!);
    _moverFrom = [for (final m in _movers) (m.row, m.col)];
    _moverCtrl.value = 1;
    _winCtrl.value = 0;
    _celebrationDone = false;
    _animFrom = (s.r, s.c);
    _animTo = (s.r, s.c);
    _dotCtrl.value = 1;
  }

  void _glide(int fromR, int fromC, int toR, int toC) {
    _animFrom = (fromR, fromC);
    _animTo = (toR, toC);
    _dotCtrl.forward(from: 0);
  }

  void _jump(int r, int c) {
    _animFrom = (r, c);
    _animTo = (r, c);
    _dotCtrl.value = 1;
  }

  // ----- coordinate helpers -----

  /// The board cell under a global position, or null if off-grid.
  (int, int)? _cellAt(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    final side = box.size.width;
    if (local.dx < 0 || local.dy < 0 || local.dx >= side || local.dy >= side) {
      return null;
    }
    return GridGeometry(side, _level!.size).cellAt(local);
  }

  /// The toolkit tool whose tile contains a global position, or null.
  ToolType? _toolAt(Offset global) {
    for (final entry in _toolKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return entry.key;
    }
    return null;
  }

  /// The piece occupying [key] — a player piece or a fixed (forced) arrow.
  PlacedElement? _pieceAt(int key) => _spentOneShots.contains(key)
      ? null
      : (_placed[key] ?? _forced[key]);

  /// True when [cell] already holds something the player cannot displace: their
  /// own piece, or anything the LEVEL pins there.
  ///
  /// The pinned test goes through [LevelData.hasForcedPieceAt] rather than
  /// _forced, because _forced comes from buildForcedPieces() and that does not
  /// carry rotating arrows — their live headings live in _rotations instead. Ask
  /// the level, and every kind of pinned piece is covered at once.
  bool _occupied(int r, int c) =>
      _placed.containsKey(_idx(r, c)) ||
      _forced.containsKey(_idx(r, c)) ||
      _level!.hasForcedPieceAt(r, c);

  bool _canPlace((int, int) cell, ToolType tool) {
    if (_status != GameStatus.planning) return false;
    final (r, c) = cell;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return false;
    if (_occupied(r, c)) return false;
    return (_kit[tool] ?? 0) > 0;
  }

  /// The tool currently in hand, whether dragged from the toolbar (place new)
  /// or picked up off the grid (move).
  ToolType? get _activeDragTool => _dragTool ?? _dragPiece?.tool;

  /// Whether the in-hand drag can drop on [cell]. The picked-up piece's origin
  /// cell is already empty (removed on pick-up), so dropping back is allowed.
  bool _canDropAt((int, int) cell) {
    if (_status != GameStatus.planning) return false;
    final (r, c) = cell;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return false;
    if (_occupied(r, c)) return false;
    // Toolkit drag needs stock; a picked-up piece is already in hand.
    if (_dragTool != null) return (_kit[_dragTool] ?? 0) > 0;
    return _dragPiece != null;
  }

  /// Recompute the placement preview for a pointer position (no setState).
  void _refreshHover(Offset global) {
    final cell = _activeDragTool == null ? null : _cellAt(global);
    final valid = cell != null && _canDropAt(cell);
    _hoverCell = valid ? cell : null;
    _hoverTool = valid ? _activeDragTool : null;
  }

  // ----- tap (fallback) -----

  void _onTapUp(TapUpDetails d) {
    if (_status != GameStatus.planning) return;
    final g = d.globalPosition;

    // Tap on a toolkit tile → select it.
    final tool = _toolAt(g);
    if (tool != null) {
      setState(() => _selected = tool);
      return;
    }

    final cell = _cellAt(g);
    if (cell == null) return;
    final key = _idx(cell.$1, cell.$2);

    // Tap a placed piece → remove it.
    if (_placed.containsKey(key)) {
      _removeAt(key);
      return;
    }

    // Tap an empty cell → place the selected tool.
    final sel = _selected;
    if (sel != null && _canPlace(cell, sel)) {
      _placeTool(cell, sel);
    }
  }

  // ----- manual drag -----

  void _onPanStart(DragStartDetails d) {
    if (_status != GameStatus.planning) return;
    _stopHand();
    final g = d.globalPosition;

    // Start dragging a tool out of the toolbar.
    final tool = _toolAt(g);
    if (tool != null && (_kit[tool] ?? 0) > 0) {
      setState(() {
        _dragTool = tool;
        _selected = tool;
        _dragGlobal = g;
        _refreshHover(g);
      });
      return;
    }

    // Otherwise, pick up a placed piece to move it (removed from its cell
    // during the drag; returned/relocated/removed on drop).
    final cell = _cellAt(g);
    if (cell != null) {
      final key = _idx(cell.$1, cell.$2);
      final piece = _placed[key];
      if (piece != null) {
        setState(() {
          _placed.remove(key);
          _dragPiece = piece;
          _dragOriginKey = key;
          _dragGlobal = g;
          _refreshHover(g);
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragTool == null && _dragPiece == null) return;
    setState(() {
      _dragGlobal = d.globalPosition;
      _refreshHover(d.globalPosition);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    // Use the end position directly (robust even if no update fired).
    final g = d.globalPosition;
    final cell = _cellAt(g);

    if (_dragTool != null) {
      // Toolkit drag → snap then place if valid.
      if (cell != null && _canDropAt(cell)) {
        _startSnap(tool: _dragTool!, cell: cell, from: g);
        return;
      }
    } else if (_dragPiece != null) {
      final piece = _dragPiece!;
      if (cell != null && _canDropAt(cell)) {
        _startSnap(piece: piece, cell: cell, from: g);
        return;
      } else if (cell == null) {
        // Dropped off the grid → remove, returning it to the toolkit.
        setState(() => _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1);
        Sfx.remove();
        Haptics.light();
      } else {
        // Dropped on an occupied/invalid cell → return to its origin.
        setState(() => _placed[_dragOriginKey!] = piece);
      }
    }
    _clearDrag();
  }

  void _clearDrag() {
    setState(() {
      _dragTool = null;
      _dragPiece = null;
      _dragOriginKey = null;
      _dragGlobal = null;
      _hoverCell = null;
      _hoverTool = null;
    });
  }

  Offset? _cellCenterGlobal((int, int) cell) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final geo = GridGeometry(box.size.width, _level!.size);
    return box.localToGlobal(geo.center(cell.$1, cell.$2));
  }

  /// Begin the magnet-snap: the ghost flies from [from] into [cell], and the
  /// piece is committed (with the weighty pop) when the snap completes.
  void _startSnap({
    ToolType? tool,
    PlacedElement? piece,
    required (int, int) cell,
    required Offset from,
  }) {
    final key = _idx(cell.$1, cell.$2);
    final to = _cellCenterGlobal(cell);
    setState(() {
      _snapTool = tool;
      _snapPiece = piece;
      _snapKey = key;
      _snapFrom = from;
      _snapTo = to ?? from;
      // The snap ghost takes over; clear the active drag.
      _dragTool = null;
      _dragPiece = null;
      _dragOriginKey = null;
      _dragGlobal = null;
      _hoverCell = null;
      _hoverTool = null;
    });
    if (to == null) {
      _finishSnap();
    } else {
      _snapCtrl.forward(from: 0);
    }
  }

  void _finishSnap() {
    final key = _snapKey;
    final tool = _snapTool;
    final piece = _snapPiece;
    if (key != null) {
      if (tool != null) {
        _commitPlace(key, _newPiece(tool), decrementKit: true);
      } else if (piece != null) {
        _commitPlace(key, piece, decrementKit: false);
      }
    }
    setState(() {
      _snapTool = null;
      _snapPiece = null;
      _snapKey = null;
      _snapFrom = null;
      _snapTo = null;
    });
  }

  /// Drop a piece onto a cell with the full landing reaction.
  void _commitPlace(int key, PlacedElement el, {required bool decrementKit}) {
    // A new placement (decrementKit) reserves stock from the kit. The kit is not
    // decremented until the magnet-snap lands, so a second placement — a quick
    // tap, or another drop — can slip past _canPlace/_canDropAt while the first
    // snap is still mid-flight. Re-check the invariants HERE, the single point
    // every placement funnels through, so the count can never go negative and no
    // cell is committed twice:
    //   * out of stock  → refuse (would drive the counter to -1);
    //   * cell taken     → refuse (a race already committed a piece here).
    if (decrementKit &&
        ((_kit[el.tool] ?? 0) <= 0 ||
            _occupied(key ~/ _level!.size, key % _level!.size))) {
      _stopHand();
      return;
    }
    _stopHand();
    _noteActivity();
    setState(() {
      _placed[key] = el;
      if (decrementKit) {
        final left = _kit[el.tool] ?? 0;
        _kit[el.tool] = left > 0 ? left - 1 : 0; // clamp: never below zero
      }
      _placeAnim[key] = 0; // weighty pop-in
      _glow(key, toolGlowColor(el.tool), 1.0); // bright flash
      _rippleNeighbors(key); // neighbors react
    });
    Sfx.place();
    Haptics.medium();
  }

  void _placeTool((int, int) cell, ToolType tool) {
    _commitPlace(_idx(cell.$1, cell.$2), _newPiece(tool), decrementKit: true);
  }

  void _removeAt(int key) {
    final piece = _placed[key];
    if (piece == null) return;
    _noteActivity();
    setState(() {
      _placed.remove(key);
      _placeAnim.remove(key);
      _removing.add(FadingPiece(key, piece.tool, piece.direction)); // shrink-out
      _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1;
      if (piece.type == PlacedType.teleporter) _reindexPortals();
    });
    Sfx.remove();
    Haptics.light();
  }

  /// Teleporters already on the board, which is also the index the next one
  /// gets — so placements alternate entrance, exit, entrance, exit…
  int get _portalsPlaced =>
      _placed.values.where((p) => p.type == PlacedType.teleporter).length;

  /// True when the next teleporter dropped will be an ENTRANCE. Drives the
  /// toolkit tile's icon so the player can see which end they are holding.
  bool get _nextPortalIsEntrance => _portalsPlaced.isEven;

  /// Close the gap after a portal is taken back, so indices stay 0..n-1 and
  /// pairs do not silently re-partner.
  void _reindexPortals() {
    final portals = _placed.entries
        .where((e) => e.value.type == PlacedType.teleporter)
        .toList()
      ..sort((a, b) =>
          (a.value.portalIndex ?? 0).compareTo(b.value.portalIndex ?? 0));
    for (var i = 0; i < portals.length; i++) {
      _placed[portals[i].key] = portals[i].value.withPortalIndex(i);
    }
  }

  /// A fresh piece for [tool]. Teleporters get the next placement index, which
  /// carries entrance/exit, pair and partner all at once.
  PlacedElement _newPiece(ToolType tool) {
    final el = PlacedElement(
        type: tool.placedType, tool: tool, direction: tool.direction);
    return tool.placedType == PlacedType.teleporter
        ? el.withPortalIndex(_portalsPlaced)
        : el;
  }

  // ----- run loop -----

  void _play() {
    if (_status == GameStatus.running) return;
    setState(() {
      _resetDot();
      _status = GameStatus.running;
    });
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  List<MoverState> _moversAt(int r, int c) =>
      _movers.where((m) => m.row == r && m.col == c).toList();

  /// Patrols that hit the dot as it moved from (fromR,fromC) to (toR,toC):
  /// those ending on its cell, plus those that traded places with it. Crossing
  /// counts as a hit — otherwise the two slide through each other, which looks
  /// on screen like the dot surviving a direct strike. [_moverFrom] is captured
  /// before the step and kept index-aligned by [_removeMover].
  List<MoverState> _moversHitting(int toR, int toC, int fromR, int fromC) {
    final out = <MoverState>[];
    for (var i = 0; i < _movers.length; i++) {
      final m = _movers[i];
      if (m.row == toR && m.col == toC) {
        out.add(m);
        continue;
      }
      if (i < _moverFrom.length &&
          moversCrossed(
            dotFromR: fromR,
            dotFromC: fromC,
            dotToR: toR,
            dotToC: toC,
            moverFromR: _moverFrom[i].$1,
            moverFromC: _moverFrom[i].$2,
            moverToR: m.row,
            moverToC: m.col,
          )) {
        out.add(m);
      }
    }
    return out;
  }

  /// Remove a patrol from the active list, keeping [_moverFrom] index-aligned
  /// with [_movers] so the surviving patrols keep gliding from their OWN
  /// previous cell (not a shifted neighbour's) after one is destroyed.
  void _removeMover(MoverState m) {
    final i = _movers.indexOf(m);
    if (i < 0) return;
    _movers.removeAt(i);
    if (i < _moverFrom.length) _moverFrom.removeAt(i);
  }

  /// The dot (carrying a shield) destroys the patrol(s) on its cell: spend the
  /// aura, remove the mover(s), blow each one up and chain-explode its adjacent
  /// walls. The dot survives.
  void _shieldDestroyMovers(List<MoverState> hit) {
    setState(() {
      _dotShielded = false;
      for (final m in hit) {
        _removeMover(m);
      }
    });
    for (final m in hit) {
      final key = _idx(m.row, m.col);
      _explode(key, fatal: false);
      for (final w in adjacentWallKeys(_level!, key)) {
        if (_destroyedCells.contains(w)) continue;
        _explodeWall(w);
      }
    }
  }

  /// Waits until the dot's and the patrols' one-beat glide animations settle, so
  /// nothing explodes while the dot (or a patrol) is still mid-glide, "in the
  /// air." Returns once both controllers have reached the end of the current
  /// beat's animation.
  Future<void> _settleGlides() async {
    try {
      await Future.wait([
        if (_dotCtrl.isAnimating) _dotCtrl.forward().orCancel,
        if (_moverCtrl.isAnimating) _moverCtrl.forward().orCancel,
      ]);
    } catch (_) {
      // A ticker was canceled (widget disposed / run reset) — nothing to do.
    }
  }

  /// A FATAL hit — a static mine or a patrol. The blast waits for the glide to
  /// finish so the dot visually REACHES the cell before it bursts, instead of
  /// exploding mid-glide. Any colliding patrol(s) blow up with it and leave the
  /// board (they share [cell] with the dot, so the blast covers them).
  Future<void> _fatalHit(int cell, DeathCause cause,
      {List<MoverState> hit = const []}) async {
    _timer?.cancel(); // stop further beats while the glides settle
    _timer = null;
    await _settleGlides();
    if (!mounted || _status != GameStatus.running) return;
    if (hit.isNotEmpty) {
      setState(() {
        for (final m in hit) {
          _removeMover(m);
        }
      });
    }
    _explode(cell, fatal: true);
    _failExploded(cause);
  }

  /// Runs a SURVIVING shielded blow-up (destroyer/patrol chain explosion) only
  /// after the dot's glide finishes, so the boom lands as the dot reaches the
  /// cell. The beat timer is HELD during the glide so no later beat runs on the
  /// pre-blast board (which would move the dot into the still-solid wall); the
  /// run resumes once the chain — clearing walls, spending the shield — resolves.
  Future<void> _afterGlide(void Function() blast) async {
    _timer?.cancel();
    _timer = null;
    await _settleGlides();
    if (!mounted || _status != GameStatus.running) return;
    blast();
    // The blast can end the run (a teleport landing on the exit wins), so only
    // resume beats if it did not.
    if (!mounted || _status != GameStatus.running) return;
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  void _beat() {
    if (_status != GameStatus.running) return;
    final size = _level!.size;

    // 1. Patrols advance simultaneously with the dot — collisions are checked
    // only after BOTH have moved (below), so a patrol the dot is leaving as it
    // arrives doesn't kill it.
    if (_movers.isNotEmpty) {
      setState(() {
        _moverFrom = [for (final m in _movers) (m.row, m.col)];
        for (final m in _movers) {
          m.step(_destroyedCells);
        }
      });
      _moverCtrl.forward(from: 0);
    }

    if (_dot.pause > 0) {
      setState(() => _dot.pause--);
      // The dot held still — a patrol that ends on it collides. A shield blows
      // the patrol away; otherwise the dot is caught.
      final hit = _moversAt(_dot.r, _dot.c);
      if (hit.isNotEmpty) {
        if (_dotShielded) {
          // Let the patrol finish gliding onto the dot before the blast.
          _afterGlide(() => _shieldDestroyMovers(hit));
        } else {
          _fatalHit(_idx(_dot.r, _dot.c), DeathCause.patrol, hit: hit);
        }
      }
      return;
    }

    final (dr, dc) = _dot.dir.delta;
    final nr = _dot.r + dr;
    final nc = _dot.c + dc;

    if (nr < 0 || nr >= size || nc < 0 || nc >= size) {
      _fail(DeathCause.edge);
      return;
    }
    if (_effBase(nr, nc) == CellType.wall) {
      _fail(DeathCause.wall);
      return;
    }

    final fromR = _dot.r, fromC = _dot.c;
    final newKey = _idx(nr, nc);
    setState(() {
      _dot.r = nr;
      _dot.c = nc;
      _trail.add(newKey);
      _glow(newKey, AppColors.accent, 0.7); // warm cell highlight on entry
    });
    _glide(fromR, fromC, nr, nc);
    Sfx.tick();

    // The dot has just started moving off its previous cell. If that cell was a
    // rotating arrow, its quarter-turn plays NOW — behind the departing dot, and
    // without holding the beat, so the run never waits on it.
    final owed = _pendingSpin;
    if (owed != null && owed.$1 == _idx(fromR, fromC)) {
      _pendingSpin = null;
      _spinRotorBehindDot(owed.$1, owed.$2);
    }

    // Same timing for a one-shot arrow: the dot has cleared the cell, so the
    // arrow can now go. Marking it spent here (rather than on arrival) is what
    // keeps it drawn under the dot through the turn.
    final used = _pendingOneShot;
    if (used != null && used == _idx(fromR, fromC)) {
      _pendingOneShot = null;
      final piece = _placed[used] ?? _forced[used];
      if (piece != null && _spentOneShots.add(used)) {
        setState(() {
          _removing.add(FadingPiece(used, piece.tool, piece.direction));
        });
      }
    }

    // Both have moved — a patrol catches the dot by sharing its FINAL cell or by
    // trading places with it. A shield blows the patrol away and the dot
    // survives; otherwise it's caught.
    final hitMovers = _moversHitting(nr, nc, fromR, fromC);
    if (hitMovers.isNotEmpty) {
      if (_dotShielded) {
        // Survive: blow the patrol away once the dot has glided into the cell,
        // then resolve that cell as normal. Surviving a patrol does NOT skip
        // what is on the floor underneath it — an arrow there still turns the
        // dot, a pause still holds it. (The patrol's cell is plain empty floor,
        // so unlike a static mine the player can place a piece on it.)
        _afterGlide(() {
          _shieldDestroyMovers(hitMovers);
          _resolveCell(newKey, nr, nc);
        });
        return; // the dot moves on next beat
      }
      // Let the dot and the patrol finish gliding into the shared cell first.
      _fatalHit(newKey, DeathCause.patrol, hit: hitMovers);
      return;
    }

    _resolveCell(newKey, nr, nc);
  }

  /// Resolve whatever the dot has landed on: hazards underfoot, the start-cell
  /// redirect, any placed piece, and the exit. Mirrors the tail of
  /// [simulateDetailed] in the same order, and is reached both by a clean
  /// arrival and by surviving a patrol on this cell with a shield.
  ///
  /// A patrol never stands on a static mine (mines are solid to patrols), so the
  /// mine branch below cannot re-enter [_afterGlide] when called from a blast.
  void _resolveCell(int newKey, int nr, int nc) {
    final base = _effBase(nr, nc);
    if (base == CellType.gap) {
      _die(DeathCause.gap);
      return;
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (_dotShielded) {
        // The shield absorbs the blow: the destroyer explodes, every adjacent
        // wall is demolished (chain explosion), and the dot survives. Wait for
        // the dot to glide onto the cell so the boom lands on contact.
        _afterGlide(() => _chainExplode(newKey));
        return; // survive this tick; the dot moves on next beat
      }
      // Wait for the dot to reach the mine before it bursts (no mid-air blast).
      _fatalHit(newKey, DeathCause.destroyer);
      return;
    }

    // The start cell acts as a permanent forced arrow on every visit.
    if (base == CellType.start) {
      setState(() {
        _dot.dir = _level!.start.dir;
        _glow(newKey, const Color(0xFF1E88E5), 1.0);
      });
      Sfx.arrow();
    }

    // A rotating arrow redirects the dot to its current heading and then owes a
    // quarter-turn clockwise. The dot leaves immediately — the turn plays behind
    // it, fired by [_beat] as the departing glide starts, so the beat is never
    // held and the run reads as "redirected, gone, and the arrow swings shut."
    final rot = _rotations[newKey];
    if (rot != null) {
      setState(() {
        _dot.dir = rot;
        _glow(newKey, const Color(0xFF1E88E5), 1.0); // arrow flash
      });
      Sfx.arrow();
      _pendingSpin = (newKey, rot);
    }

    final piece = _pieceAt(newKey);
    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          setState(() {
            _dot.dir = piece.direction!;
            _glow(newKey, const Color(0xFF1E88E5), 1.0); // arrow activation flash
            // A one-shot turns the dot once and then leaves the board. The
            // disappearance is owed, not done: it plays from _beat once the dot
            // has moved off, so the arrow is still under the dot as it turns and
            // fades behind it. The placement stays in _placed so Retry puts it
            // back.
            if (piece.tool.isOneShot) _pendingOneShot = newKey;
          });
          Sfx.arrow();
        case PlacedType.pause:
          setState(() {
            _dot.pause = 2;
            _glow(newKey, const Color(0xFFBA68C8), 1.0);
          });
          Sfx.pause();
        case PlacedType.shield:
          // Collected once per run: revisiting the (now-empty) cell grants
          // nothing. The placement stays in _placed so Retry restores it.
          if (_consumedShields.add(newKey)) {
            setState(() {
              _dotShielded = true; // gain the protective aura (one at a time)
              _glow(newKey, kShieldColor, 1.0);
              // The shield leaves the grid with a shrink-out as it's picked up.
              // (_revision changes each beat as the trail grows, so the grid
              // repaints without the now-hidden shield.)
              _removing.add(FadingPiece(newKey, piece.tool, piece.direction));
            });
            Sfx.shield();
          }
        case PlacedType.teleporter:
          // The whole jump — glide in, animate, land — is driven by _runTeleport,
          // which holds the beat timer for its full duration.
          _runTeleport(newKey);
          return; // the exit check below would run on the pre-jump cell
      }
    }

    if (_level!.baseTypeAt(_dot.r, _dot.c) == CellType.exit) {
      _win();
    }
  }

  /// Swing a rotating arrow through its quarter-turn while the dot travels on.
  /// Purely visual bookkeeping: it does NOT touch the beat timer, so the run
  /// keeps stepping and the arrow turns behind the dot. [from] is the heading it
  /// sent the dot; the new heading is committed as the turn lands.
  ///
  /// Called from [_beat] the moment the dot starts gliding off the arrow, so the
  /// turn can never be drawn while the dot is still standing on it.
  Future<void> _spinRotorBehindDot(int cell, Direction from) async {
    // One controller serves every rotor, so a turn still in flight elsewhere is
    // landed first rather than dropped half-done. At a 400ms beat and a 260ms
    // turn this cannot currently happen — it keeps a faster beat honest.
    final busy = _spinCell;
    if (busy != null && busy != cell) {
      _rotations[busy] = _rotations[busy]!.rotatedCW;
    }
    setState(() => _spinCell = cell);
    try {
      await _spinCtrl.forward(from: 0).orCancel;
    } catch (_) {
      return; // disposed, or Retry reset the board mid-turn
    }
    if (!mounted) return;
    // The glyph has arrived on the next heading — make it official.
    setState(() {
      _rotations[cell] = from.rotatedCW;
      if (_spinCell == cell) _spinCell = null;
    });
  }

  /// The pair colour of the portal at [cell], for the ring pulses. Falls back to
  /// the generic warm portal tint if the cell somehow isn't a portal.
  Color _portalColor(int cell) {
    final pairs = buildPortalPairs(_level!, {..._forced, ..._placed});
    final p = pairs[cell];
    if (p == null) return const Color(0xFFFF8A65);
    return GameGridPainter
        .telePairColors[p % GameGridPainter.telePairColors.length]
        .$2;
  }

  /// Drive a teleport end to end: settle the glide INTO the portal, play the
  /// shrink-out / jump / grow-in animation, then either win or resume beats. The
  /// beat timer is held for the whole sequence so nothing steps mid-animation.
  Future<void> _runTeleport(int fromKey) async {
    _timer?.cancel();
    _timer = null;
    await _settleGlides(); // finish gliding onto the entrance cell first
    if (!mounted || _status != GameStatus.running) return;

    final size = _level!.size;
    final links = buildTeleportLinks(_level!, {..._forced, ..._placed});
    final dest = links[fromKey];
    if (dest == null) {
      // An unpaired portal is inert — just carry on beating.
      _timer = Timer.periodic(
          const Duration(milliseconds: _tickMs), (_) => _beat());
      return;
    }

    Sfx.teleport();
    setState(() {
      _teleporting = true;
      _teleportGrowing = false;
      _teleportEntrance = (fromKey ~/ size, fromKey % size);
      _teleportExit = (dest ~/ size, dest % size);
      _teleportColor = _portalColor(fromKey);
    });

    // Shrink + fade out at the entrance (its ring expands over the same window).
    try {
      await _teleportCtrl.forward(from: 0).orCancel;
    } catch (_) {
      return; // disposed / reset mid-teleport
    }
    if (!mounted || _status != GameStatus.running) {
      setState(() => _teleporting = false);
      return;
    }

    // Relocate while invisible.
    setState(() {
      _dot.r = dest ~/ size;
      _dot.c = dest % size;
      _trail.add(dest);
      _teleportGrowing = true;
    });
    _jump(_dot.r, _dot.c);

    // A brief hidden hold between the two halves.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || _status != GameStatus.running) {
      setState(() => _teleporting = false);
      return;
    }

    // Grow + fade in at the exit (its ring expands over this window).
    try {
      await _teleportCtrl.forward(from: 0).orCancel;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _teleporting = false);
    if (_status != GameStatus.running) return;

    // The dot has materialised at the exit — it now faces that cell's hazards,
    // exactly as a normal arrival does. Its OWN piece is not applied (that would
    // bounce a pair back and forth), but a patrol, a gap or a mine underfoot
    // still resolves: die, or survive on a shield and chain-explode.
    final destKey = _idx(_dot.r, _dot.c);
    final hit = _moversAt(_dot.r, _dot.c);
    if (hit.isNotEmpty) {
      if (_dotShielded) {
        _shieldDestroyMovers(hit);
      } else {
        _fatalHit(destKey, DeathCause.patrol, hit: hit);
        return;
      }
    }
    final base = _effBase(_dot.r, _dot.c);
    if (base == CellType.gap) {
      _die(DeathCause.gap);
      return;
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (_dotShielded) {
        _chainExplode(destKey);
      } else {
        _fatalHit(destKey, DeathCause.destroyer);
        return;
      }
    }

    if (_level!.baseTypeAt(_dot.r, _dot.c) == CellType.exit) {
      _win();
      return;
    }
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  /// Ball scale multiplier and opacity for the current teleport phase (1, 1 when
  /// not teleporting): shrinking to nothing on the way out, growing back on the
  /// way in.
  (double scale, double opacity) get _teleportBallTransform {
    if (!_teleporting) return (1, 1);
    final v = _teleportCtrl.value;
    return _teleportGrowing
        ? (Curves.easeOutBack.transform(v).clamp(0.0, 1.2), v)
        : (1 - Curves.easeInCubic.transform(v), 1 - v);
  }

  void _win() {
    _timer?.cancel();
    _timer = null;
    Sfx.exit();
    // Record completion → unlocks the next level (skipped for designer tests).
    if (widget.levelOverride == null) {
      ProgressStore.markCompleted(_level!.id);
      _reportWin();
      // Decided here, spent at the transition. Counting on the win means one
      // completion advances the cadence exactly once, whichever way the player
      // then leaves the level — or if they never leave it at all.
      _interstitialDue = AdPacing.noteLevelCompleted(
        levelId: _level!.id,
        usedHint: _hintsThisLevel > 0,
      );
    }
    // A challenge is recorded against itself, never against the campaign — it
    // rides the levelOverride path above, so nothing here touches progress.
    final challenge = widget.challenge;
    if (challenge != null) {
      final reward = ChallengeService.complete(challenge);
      _challengeReward = reward;
      // The streak is no longer at risk, so the warning queued for later this
      // week would arrive telling them to do something they have just done.
      unawaited(NotificationService.cancelStreakAtRisk());
    }
    // Brief beat with the dot at the exit, then the grid fades to celebration.
    setState(() {
      _status = GameStatus.won;
      _celebrationDone = false;
      _winMessage = widget.challenge != null
          ? 'Challenge complete!'
          : _winMessages[math.Random().nextInt(_winMessages.length)];
    });
    _winCtrl.forward(from: 0);
    // Rising chime as the celebration screen comes in (after the ~0.5s pause).
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) Sfx.levelComplete();
    });
    _maybeAskAboutNotifications();
  }

  /// Ask about notifications, once, on the back of a win.
  ///
  /// A win is the one moment the player has just been given something and is
  /// pleased about it, which is the only honest time to ask for a permission.
  /// It waits for the celebration to arrive first — a dialog on top of the win
  /// animation would cover the thing being celebrated.
  ///
  /// [NotificationPromptDialog.maybeShow] decides whether it is due, so this is
  /// safe to call on every win; only the first one gets a dialog.
  void _maybeAskAboutNotifications() {
    // The designer's own test runs are not a player finishing a level.
    if (widget.levelOverride != null) return;
    if (!NotificationService.shouldPrompt) return;
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      unawaited(NotificationPromptDialog.maybeShow(context));
    });
  }

  /// Show the between-levels interstitial if one is due.
  ///
  /// Called from the transitions off the celebration screen rather than when
  /// the celebration ends, so the ad never lands on top of the win — the player
  /// gets their moment, and the break happens as they move on, which is where
  /// they expect a pause anyway.
  ///
  /// Silent on failure, in every sense: no ad loaded, no fill, no SDK, nothing
  /// reported. The player just moves on.
  Future<void> _maybeShowInterstitial() async {
    if (!_interstitialDue) return;
    _interstitialDue = false; // consumed either way — never retried later
    final id = _level!.id;
    if (await AdManager.showInterstitial()) {
      Analytics.interstitialShown(id, 'between_levels');
    }
  }

  /// Load the next level in place (no trip back to the menu).
  Future<void> _goToNextLevel() async {
    final next = _level!.id + 1;
    final data = levelDataFor(next);
    if (data == null) return;
    await _maybeShowInterstitial();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          level: Level(
            id: next,
            number: next,
            title: data.title,
            difficulty: Difficulty.easy,
            status: LevelStatus.unlocked,
          ),
        ),
      ),
    );
  }

  void _die(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    Sfx.die();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _reportFail();
      setState(() => _status = GameStatus.lost);
    });
  }

  /// Spawn a destroyer explosion at [cell]: a cell flash, flying fragments, a
  /// "boom" and a heavy haptic. When [fatal] the dot is hidden (it poofs into
  /// the blast); otherwise (a shielded survival) the dot keeps moving.
  void _explode(int cell, {required bool fatal}) {
    final rng = math.Random();
    const colors = [
      Color(0xFFEF5350), // red
      Color(0xFFFF8A65), // orange
      Color(0xFFFFD54F), // yellow
    ];
    final frags = <Frag>[
      for (var i = 0; i < 14; i++)
        Frag(
          i / 14 * 2 * math.pi + rng.nextDouble() * 0.5,
          0.6 + rng.nextDouble() * 1.0,
          colors[rng.nextInt(colors.length)],
          0.7 + rng.nextDouble() * 0.8,
        ),
    ];
    setState(() {
      _explosions.add(Explosion(cell, frags));
      _destroyedCells.add(cell); // the destroyer is gone after the blast
      _glow(cell, const Color(0xFFEF5350), 1.0); // bright red cell flash
      if (fatal) _dotGone = true;
    });
    Sfx.boom();
    Haptics.heavy();
  }

  /// A shielded hit: blow up the destroyer AND chain-explode every wall beside
  /// it (each shattering with gray fragments), opening a path. The dot survives.
  void _chainExplode(int destroyerKey) {
    setState(() => _dotShielded = false);
    _explode(destroyerKey, fatal: false);
    for (final w in adjacentWallKeys(_level!, destroyerKey)) {
      if (_destroyedCells.contains(w)) continue;
      _explodeWall(w);
    }
  }

  /// A wall shattering: gray fragments fly out and the cell is cleared. Silent —
  /// the destroyer's boom covers the whole blast.
  void _explodeWall(int cell) {
    final rng = math.Random();
    const colors = [
      Color(0xFF78909C),
      Color(0xFF90A4AE),
      Color(0xFFB0BEC5),
    ];
    final frags = <Frag>[
      for (var i = 0; i < 12; i++)
        Frag(
          i / 12 * 2 * math.pi + rng.nextDouble() * 0.5,
          0.5 + rng.nextDouble() * 0.9,
          colors[rng.nextInt(colors.length)],
          0.7 + rng.nextDouble() * 0.8,
        ),
    ];
    setState(() {
      _explosions.add(
          Explosion(cell, frags, tint: const Color(0xFF90A4AE)));
      _destroyedCells.add(cell);
      _glow(cell, const Color(0xFF90A4AE), 0.9);
    });
  }

  /// Death by destroyer: stops the run and shows the fail card AFTER the ~0.5s
  /// explosion has played out.
  void _failExploded(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      _reportFail();
      setState(() => _status = GameStatus.lost);
    });
  }

  void _fail(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    _reportFail();
    setState(() => _status = GameStatus.lost);
  }

  /// Reset the dot but keep placed pieces (used by "Retry").
  void _retry() => setState(_resetDot);

  /// Remove every placed piece and restore the toolkit (used by "Reset").
  void _clearAll() {
    setState(() {
      _placed.clear();
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      _resetDot();
    });
  }

  /// Confirm before clearing the board.
  void _confirmReset() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.ink, width: 3),
        ),
        title: const Text(
          'Reset all pieces?',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 18),
        ),
        content: const Text(
          'This removes everything you placed on the board.',
          style: TextStyle(color: AppColors.textSoft),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(
                    color: AppColors.textSoft, fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(ctx).pop();
              _clearAll();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.ink, width: 2.5),
              ),
              child: const Text(
                'Reset',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    if (_level == null) return _buildPlaceholder();

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Report the touch-down position to onPanStart (not the post-slop
        // position) so a drag is matched to the tile it actually started on.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _onTapUp,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          key: _rootKey,
          children: [
            const Positioned.fill(child: CustomPaint(painter: _BgGridPainter())),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    Expanded(child: _buildPlayArea()),
                    const SizedBox(height: 16),
                    // Hide the toolkit during the win celebration.
                    if (_status == GameStatus.won)
                      const SizedBox(height: 64)
                    else if (_level!.toolkit.isEmpty)
                      _buildEmptyKitHint()
                    else
                      GameToolbar(
                        tools: _level!.toolkit.map((e) => e.type).toList(),
                        counts: _kit,
                        selected: _selected,
                        enabled: _status != GameStatus.running,
                        tileKeys: _toolKeys,
                        draggingTool: _dragTool,
                        portalNextIsEntrance: _nextPortalIsEntrance,
                        onSelect: (t) => setState(() => _selected = t),
                        onReset: _confirmReset,
                      ),
                    const SizedBox(height: 16),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
            // Fail still uses a small overlay; win celebrates on the grid.
            if (_status == GameStatus.lost) _buildOverlay(),
            // Drag/snap ghost (rebuilds during the snap flight via _snapCtrl).
            AnimatedBuilder(
              animation: _snapCtrl,
              builder: (_, _) => _buildGhost(),
            ),
            if (_showHand)
              AnimatedBuilder(
                animation: _handCtrl,
                builder: (_, _) => _buildTutorialHand(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        BorderedTile(
          width: 46,
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back_rounded,
              color: AppColors.ink, size: 24),
        ),
        const Spacer(),
        Text(
          'Level ${_level!.id}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        // Dev-only: edit this level in the designer.
        if (isDevMode) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openInDesigner,
            child: const Icon(Icons.edit_rounded,
                color: AppColors.textSoft, size: 20),
          ),
        ],
        const Spacer(),
        _buildHintButton(),
        // The playtest feedback box. Gated harder than the designer beside it:
        // debug builds only, so it is absent from the public web build as well
        // as from the store one.
        if (isFeedbackEnabled) ...[
          const SizedBox(width: 8),
          BorderedTile(
            width: 44,
            onTap: _showFeedbackDialog,
            child: const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.ink, size: 20),
          ),
        ],
      ],
    );
  }

  void _showFeedbackDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => FeedbackDialog(level: _level!.id),
    );
  }

  /// Dev-only: open this level in the designer, pre-loaded for editing.
  void _openInDesigner() {
    // The designer has two doors — the menu's "+" and this pencil — and both
    // report, so the event counts entries rather than one particular button.
    Analytics.levelDesignerOpened();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LevelDesignerScreen(
        initialLevel: _level,
        initialNumber: _level!.id,
        initialDifficulty: widget.level.difficulty,
      ),
    ));
  }

  Widget _buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          final geo = GridGeometry(side, _level!.size);
          final previewKey = _hoverCell == null
              ? null
              : _idx(_hoverCell!.$1, _hoverCell!.$2);

          // KeyedSubtree exposes a stable test key while the inner Stack keeps
          // the GlobalKey used for coordinate conversion.
          return KeyedSubtree(
            key: const ValueKey('gameBoard'),
            child: Stack(
              key: _boardKey,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_glowCtrl, _winCtrl, _spinCtrl]),
                    builder: (_, _) => CustomPaint(
                      size: Size.square(side),
                      painter: GameGridPainter(
                        level: _level!,
                        // Picked-up shields vanish from the grid (the shrink-out
                        // is drawn via `removing`); the placement itself stays
                        // in _placed / _forced so Retry restores it. A collected
                        // shield can be a placed OR a fixed one, so both maps are
                        // filtered by _consumedShields.
                        placed: _consumedShields.isEmpty &&
                                _spentOneShots.isEmpty
                            ? _placed
                            : {
                                for (final e in _placed.entries)
                                  if (!_consumedShields.contains(e.key) &&
                                      !_spentOneShots.contains(e.key))
                                    e.key: e.value,
                              },
                        trail: _trail,
                        revision: _revision,
                        placeAnim: _placeAnim,
                        removing: _removing,
                        forced: _consumedShields.isEmpty
                            ? _forced
                            : {
                                for (final e in _forced.entries)
                                  if (!_consumedShields.contains(e.key))
                                    e.key: e.value,
                              },
                        rotations: _rotations,
                        spinCell: _spinCell,
                        spinProgress: _spinCtrl.value,
                        cellGlow: _cellGlow,
                        cellGlowColor: _cellGlowColor,
                        cellPulse: _cellPulse,
                        explosions: _explosions,
                        destroyedCells: _destroyedCells,
                        glowTick: _glowCtrl.value,
                        showStartHint: _status == GameStatus.planning,
                        winProgress:
                            _status == GameStatus.won ? _winCtrl.value : 0.0,
                        previewKey: previewKey,
                        previewTool: _hoverTool,
                      ),
                    ),
                  ),
                ),
                // Expanding ring pulses at the entrance and exit portals.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _teleportCtrl,
                      builder: (_, _) => CustomPaint(
                        size: Size.square(side),
                        painter: _TeleportRingPainter(
                          geo: geo,
                          active: _teleporting,
                          growing: _teleportGrowing,
                          progress: _teleportCtrl.value,
                          entrance: _teleportEntrance,
                          exit: _teleportExit,
                          color: _teleportColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_dotCtrl, _glowCtrl, _teleportCtrl]),
                    builder: (_, _) {
                      // Hidden once the dot has been blown up by a destroyer.
                      if (_dotGone) return const SizedBox.shrink();
                      final from = geo.center(_animFrom.$1, _animFrom.$2);
                      final to = geo.center(_animTo.$1, _animTo.$2);
                      final t = Curves.easeInOutCubic.transform(_dotCtrl.value);
                      final pos = Offset.lerp(from, to, t)!;
                      final d = geo.cell * 0.46;
                      // Subtle continuous glow pulse (0..1).
                      final glow =
                          0.5 + 0.5 * math.sin(_glowCtrl.value * 2 * math.pi);
                      final (telScale, telOpacity) = _teleportBallTransform;
                      return Transform.translate(
                        offset: Offset(pos.dx - d / 2, pos.dy - d / 2),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Opacity(
                            opacity: telOpacity.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: _dotScale.value * telScale,
                              child: _Dot(
                                size: d,
                                paused: _dot.pause > 0,
                                glow: glow,
                                shielded: _dotShielded,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Moving destroyers: red mines gliding between cells, visible
                // while planning AND running so the player can read the patrol.
                if (_movers.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_moverCtrl, _glowCtrl]),
                        builder: (_, _) => CustomPaint(
                          size: Size.square(side),
                          painter: _MoverPainter(
                            movers: _movers,
                            from: _moverFrom,
                            t: Curves.easeInOut.transform(_moverCtrl.value),
                            geo: geo,
                            glowTick: _glowCtrl.value,
                            // Show the patrol path/axis only while planning —
                            // during play the motion itself makes it obvious.
                            planning: _status == GameStatus.planning,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The Expanded play region: the interactive board, or — after a win — the
  /// rippling board with a translucent celebration overlay fading in on top.
  Widget _buildPlayArea() {
    if (_status != GameStatus.won) {
      return Center(child: _buildBoard());
    }
    return AnimatedBuilder(
      animation: _winCtrl,
      builder: (_, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Grid stays visible and ripples (painter winProgress).
            Center(child: _buildBoard()),
            Positioned.fill(
              child: IgnorePointer(child: _buildCelebrationOverlay(_winCtrl.value)),
            ),
          ],
        );
      },
    );
  }

  /// Translucent cream overlay (~72%) over the still-visible grid, with the
  /// bouncy congratulatory message, a star badge and the level number.
  Widget _buildCelebrationOverlay(double v) {
    // The overlay starts fading in after the grid ripple has begun (~0.5s).
    final overlayFade = ((v - 0.23) / 0.22).clamp(0.0, 1.0);
    // Checkmark self-draws over ~0.8s (circle then tick).
    final checkProgress = ((v - 0.30) / 0.40).clamp(0.0, 1.0);
    final msgT = ((v - 0.36) / 0.34).clamp(0.0, 1.0);
    final msgScale = msgT == 0 ? 0.0 : Curves.elasticOut.transform(msgT);
    final msgOpacity = (msgT / 0.25).clamp(0.0, 1.0);
    final subT = ((v - 0.50) / 0.30).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Cream wash — grid still faintly visible behind it.
        ColoredBox(
          color: AppColors.background.withValues(alpha: 0.72 * overlayFade),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SuccessCheck(progress: checkProgress),
              const SizedBox(height: 26),
              Transform.scale(
                scale: msgScale,
                child: Opacity(
                  opacity: msgOpacity,
                  child: Text(
                    _winMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: AppColors.coral,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              if (_challengeReward == ChallengeReward.hint) ...[
                const SizedBox(height: 12),
                Opacity(
                  opacity: msgOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.ink, width: 3),
                    ),
                    child: const Text(
                      '💡 +1 hint',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Opacity(
                opacity: subT,
                child: Text(
                  'Level ${_level!.id}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSoft,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Level-2 tutorial: a semi-transparent hand that repeatedly drags a ghost
  /// Up arrow from the toolbar onto the target cell, then fades out.
  Widget _buildTutorialHand() {
    final toolBox =
        _toolKeys[ToolType.arrowUp]?.currentContext?.findRenderObject()
            as RenderBox?;
    final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (toolBox == null || rootBox == null || boardBox == null) {
      return const SizedBox.shrink();
    }

    final src = rootBox.globalToLocal(toolBox
        .localToGlobal(Offset(toolBox.size.width / 2, toolBox.size.height / 2)));
    final geo = GridGeometry(boardBox.size.width, _level!.size);
    final dst = rootBox.globalToLocal(
        boardBox.localToGlobal(geo.center(_tutorialCell.$1, _tutorialCell.$2)));
    final cell = geo.cell;

    const cycles = 3;
    final v = _handCtrl.value;
    final overallFade = 1 - ((v - 0.9) / 0.1).clamp(0.0, 1.0);
    final cv = (v * cycles) % 1.0;

    // Position: glide src→dst over the first half of each cycle.
    final moveT = ((cv - 0.05) / 0.5).clamp(0.0, 1.0);
    final pos = Offset.lerp(src, dst, Curves.easeInOut.transform(moveT))!;
    // A little press when it lands.
    final press = (cv >= 0.56 && cv < 0.70) ? 0.86 : 1.0;
    // Per-cycle visibility: appear, hold, fade before resetting to src.
    double cycleOpacity;
    if (cv < 0.05) {
      cycleOpacity = cv / 0.05;
    } else if (cv < 0.70) {
      cycleOpacity = 1;
    } else if (cv < 0.86) {
      cycleOpacity = 1 - (cv - 0.70) / 0.16;
    } else {
      cycleOpacity = 0;
    }
    final opacity = (0.55 * cycleOpacity * overallFade).clamp(0.0, 1.0);
    if (opacity <= 0.01) return const SizedBox.shrink();

    final size = cell * 0.92;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: press,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The arrow being carried.
                  Positioned.fill(
                    child: DragGhost(tool: ToolType.arrowUp, size: size),
                  ),
                  // The pointing hand, just below the piece.
                  Positioned(
                    right: -size * 0.28,
                    bottom: -size * 0.5,
                    child: Text('👆', style: TextStyle(fontSize: size * 0.7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The floating ghost element — slightly larger than a cell while dragging
  /// (so it feels like a lifted piece), and flying into the cell during the
  /// magnet-snap before the piece pops in.
  Widget _buildGhost() {
    // Determine drag/snap state first — when neither is active (e.g. during
    // the win celebration, when the board is removed) bail out before touching
    // the board key, whose element may be inactive.
    ToolType? tool;
    Offset? globalPos;
    double scale;
    if ((_dragTool != null || _dragPiece != null) && _dragGlobal != null) {
      tool = _activeDragTool;
      globalPos = _dragGlobal;
      scale = 1.2; // lifted piece, larger than the cell
    } else if (_snapKey != null && _snapFrom != null && _snapTo != null) {
      tool = _snapTool ?? _snapPiece?.tool;
      final t = Curves.easeOut.transform(_snapCtrl.value);
      globalPos = Offset.lerp(_snapFrom, _snapTo, t);
      scale = 1.2 - 0.2 * t; // settle to cell size on arrival
    } else {
      return const SizedBox.shrink();
    }
    if (tool == null || globalPos == null) return const SizedBox.shrink();

    final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null) return const SizedBox.shrink();
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final cell = boardBox == null
        ? 58.0
        : GridGeometry(boardBox.size.width, _level!.size).cell;

    final local = rootBox.globalToLocal(globalPos);
    final size = cell * scale;
    return Positioned(
      left: local.dx - size / 2,
      top: local.dy - size / 2,
      child: IgnorePointer(child: DragGhost(tool: tool, size: size)),
    );
  }

  /// Shown instead of the toolbar on levels with no pieces to place.
  Widget _buildEmptyKitHint() {
    return SizedBox(
      height: 64,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('👇', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Press Play!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textSoft,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToMenu() async {
    await _maybeShowInterstitial();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// The bottom button area, always occupying [_kFooterHeight] so the grid above
  /// never jumps when the footer swaps between Play, the win pause, and Continue.
  /// Content is bottom-aligned so the button keeps the same baseline throughout.
  Widget _buildFooter() {
    return SizedBox(
      height: _kFooterHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _footerContent(),
      ),
    );
  }

  Widget _footerContent() {
    if (_status == GameStatus.won) {
      // During the celebration, keep the spot empty; fade Continue in after.
      if (!_celebrationDone) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (_, t, child) => Opacity(opacity: t, child: child),
        child: _buildContinueCluster(),
      );
    }

    final running = _status == GameStatus.running;
    // Every piece must be placed before Play is enabled (no effect on the
    // no-toolkit Level 1, whose kit is already empty).
    final remaining = _remainingPieces;
    final canPlay = remaining == 0;
    // The hint line is always present (its space is reserved) so the Play button
    // never shifts; only the message changes.
    final hint = running
        ? 'Go!'
        : (canPlay ? 'Ready! Hit Play' : 'Place all elements ($remaining left)');
    final hintColor =
        (canPlay && !running) ? AppColors.completed : AppColors.textSoft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hint,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: hintColor,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _PillButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            filled: true,
            onTap: (running || !canPlay) ? null : _play,
          ),
        ),
      ],
    );
  }

  /// Post-celebration control: a single Continue (or Back to Menu on the last
  /// level). One clean action — no Replay / Menu.
  Widget _buildContinueCluster() {
    final hasNext =
        widget.levelOverride == null && levelDataFor(_level!.id + 1) != null;
    return SizedBox(
      width: double.infinity,
      child: _PillButton(
        label: hasNext ? 'Continue' : 'Back to Menu',
        icon: hasNext ? Icons.play_arrow_rounded : null,
        filled: true,
        large: true,
        onTap: hasNext ? _goToNextLevel : _goToMenu,
      ),
    );
  }

  /// Headline and accent color for each death cause, so the fail overlay tells
  /// the player exactly why the dot died. The matching icon is drawn by
  /// [_FailIconPainter] in the board's thick-outline style.
  static ({String label, Color color}) _deathInfo(DeathCause? cause) {
    switch (cause) {
      case DeathCause.edge:
        return (label: 'Ran off the edge!', color: Color(0xFFF59E0B));
      case DeathCause.wall:
        return (label: 'Hit a wall!', color: Color(0xFF607D8B));
      case DeathCause.destroyer:
        return (label: 'Destroyed!', color: Color(0xFFEF5350));
      case DeathCause.patrol:
        return (label: 'Caught by patrol!', color: Color(0xFFE53935));
      case DeathCause.gap:
        return (label: 'Fell in a gap!', color: Color(0xFF6D4C41));
      case null:
        return (label: 'Try Again', color: AppColors.ink);
    }
  }

  /// Fail-only overlay — shows WHY the dot died, then "Try Again". Wins
  /// celebrate on the grid instead.
  Widget _buildOverlay() {
    final info = _deathInfo(_deathCause);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.32),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.ink, width: 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The hazard that killed the dot, drawn in the board's icon style.
              SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(painter: _FailIconPainter(_deathCause)),
              ),
              const SizedBox(height: 10),
              // The death reason — prominent, in its matching color.
              Text(
                info.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: info.color,
                ),
              ),
              if (_deathCause != null) ...[
                const SizedBox(height: 4),
                Text(
                  _offerHintOnFail ? 'Almost! Want a hand?' : 'Almost!',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSoft,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Offered from the second fail, and only when a hint would
              // actually place something. It leads, because at this point it is
              // the more useful of the two.
              if (_offerHintOnFail) ...[
                _PillButton(
                  label: 'Use Hint',
                  icon: Icons.lightbulb_rounded,
                  filled: true,
                  onTap: _onFailHintPressed,
                ),
                const SizedBox(height: 10),
                _PillButton(
                  label: 'Try Again',
                  icon: Icons.refresh_rounded,
                  filled: false,
                  onTap: _retry,
                ),
              ] else
                _PillButton(
                  label: 'Try Again',
                  icon: Icons.refresh_rounded,
                  filled: true,
                  onTap: _retry,
                ),
              const SizedBox(height: 10),
              _PillButton(
                label: 'Clear & Edit',
                filled: false,
                onTap: _clearAll,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _BgGridPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      BorderedTile(
                        width: 46,
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.ink, size: 24),
                      ),
                      const Spacer(),
                      Text('Level ${widget.level.number}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                      const Spacer(),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.construction_rounded,
                              size: 72, color: AppColors.accent),
                          SizedBox(height: 16),
                          Text('Coming soon',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSoft,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated dot, with a subtle pulsing glow ([glow] in 0..1). When
/// [shielded] it wears a glowing cyan protective aura.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.paused,
    this.glow = 0.5,
    this.shielded = false,
  });

  final double size;
  final bool paused;
  final double glow;
  final bool shielded;

  static const _shield = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    final base = paused ? 0.12 : 0.40;
    final span = paused ? 0.10 : 0.30;
    final alpha = base + span * glow;
    final blur = (paused ? 5.0 : 9.0) + 7.0 * glow;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [Color(0xFFFFD89B), AppColors.accent],
          stops: [0.0, 0.85],
        ),
        border: Border.all(color: AppColors.ink, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: alpha),
            blurRadius: blur,
            spreadRadius: 1 + 1.5 * glow,
          ),
        ],
      ),
    );

    if (!shielded) return dot;

    // Protective cyan bubble around the dot, breathing with the glow pulse.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -size * 0.30,
            right: -size * 0.30,
            top: -size * 0.30,
            bottom: -size * 0.30,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _shield.withValues(alpha: 0.12 + 0.06 * glow),
                border: Border.all(
                  color: _shield.withValues(alpha: 0.85),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _shield.withValues(alpha: 0.35 + 0.25 * glow),
                    blurRadius: 10 + 8 * glow,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          dot,
        ],
      ),
    );
  }
}

/// Thick-bordered pill button matching the menu style.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.filled,
    this.icon,
    this.onTap,
    this.large = false,
  });

  final String label;
  final bool filled;
  final IconData? icon;
  final VoidCallback? onTap;

  /// A bigger, more prominent variant (used for the primary "Next Level").
  final bool large;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final height = large ? 60.0 : 54.0;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: BouncyButton(
        enabled: !disabled,
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        rippleColor: filled ? Colors.white : AppColors.coral,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: filled ? AppColors.coral : AppColors.card,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: large ? 19 : 17,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : AppColors.ink,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon,
                    color: filled ? Colors.white : AppColors.ink,
                    size: large ? 28 : 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Classic "success checkmark": a ring draws itself, then a tick draws inside.
/// [progress] (0..1) is driven by the win controller — circle over the first
/// half, checkmark over the second.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: CustomPaint(
        painter: _CheckPainter(
          Curves.easeInOut.transform(progress.clamp(0.0, 1.0)),
          AppColors.coral,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // Phase 1 (0–0.5): the ring draws itself from the top, clockwise.
    final circleP = (progress / 0.5).clamp(0.0, 1.0);
    if (circleP > 0) {
      final rect = Rect.fromCircle(
        center: Offset(s / 2, s / 2),
        radius: s / 2 - 4,
      );
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * circleP, false, paint);
    }

    // Phase 2 (0.5–1.0): the short leg, then the long leg.
    final checkP = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
    if (checkP > 0) {
      final p1 = Offset(0.30 * s, 0.52 * s);
      final corner = Offset(0.44 * s, 0.66 * s);
      final p3 = Offset(0.72 * s, 0.37 * s);
      final shortP = (checkP / 0.45).clamp(0.0, 1.0);
      canvas.drawLine(p1, Offset.lerp(p1, corner, shortP)!, paint);
      if (checkP > 0.45) {
        final longP = ((checkP - 0.45) / 0.55).clamp(0.0, 1.0);
        canvas.drawLine(corner, Offset.lerp(corner, p3, longP)!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// Faint background grid, matching the menu screen.
class _BgGridPainter extends CustomPainter {
  static const _cell = 28.0;

  const _BgGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BgGridPainter oldDelegate) => false;
}

/// Draws the moving destroyers as red-tinted mines, gliding from their previous
/// cell to their current cell over one beat ([t] 0→1). Used as an overlay above
/// the board so movers animate independently of the grid repaint.
/// Draws the expanding, fading ring at whichever portal is active this phase:
/// the entrance while the ball shrinks out, the exit while it grows in. The
/// ring uses the pair's colour.
class _TeleportRingPainter extends CustomPainter {
  _TeleportRingPainter({
    required this.geo,
    required this.active,
    required this.growing,
    required this.progress,
    required this.entrance,
    required this.exit,
    required this.color,
  });

  final GridGeometry geo;
  final bool active;
  final bool growing;
  final double progress; // 0..1 within the current phase
  final (int, int)? entrance;
  final (int, int)? exit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final cell = growing ? exit : entrance;
    if (cell == null) return;
    final center = geo.center(cell.$1, cell.$2);
    final t = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    // Grow from the portal out past the cell edge, fading as it goes.
    final radius = geo.cell * (0.18 + 0.42 * t);
    final alpha = (1 - t) * 0.9;
    if (alpha <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = geo.cell * 0.10 * (1 - 0.5 * t)
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _TeleportRingPainter old) =>
      active != old.active ||
      growing != old.growing ||
      progress != old.progress ||
      entrance != old.entrance ||
      exit != old.exit ||
      color != old.color;
}

class _MoverPainter extends CustomPainter {
  _MoverPainter({
    required this.movers,
    required this.from,
    required this.t,
    required this.geo,
    required this.glowTick,
    this.planning = false,
  });

  final List<MoverState> movers;
  final List<(int, int)> from;
  final double t;
  final GridGeometry geo;
  final double glowTick;

  /// While planning, draw each mover's patrol path + axis so the player can read
  /// "this mine moves left-right / up-down" before pressing Play.
  final bool planning;

  static const _red = Color(0xFFE53935);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < movers.length; i++) {
      final m = movers[i];
      if (planning) _paintPatrolHint(canvas, m);
      final prev = i < from.length ? from[i] : (m.row, m.col);
      final a = geo.center(prev.$1, prev.$2);
      final b = geo.center(m.row, m.col);
      final c = Offset.lerp(a, b, t)!;
      // Red danger halo so a moving mine reads differently from a static one.
      final pulse = 0.5 + 0.5 * math.sin(glowTick * 2 * math.pi);
      canvas.drawCircle(
        c,
        geo.cell * (0.34 + 0.05 * pulse),
        Paint()
          ..color = _red.withValues(alpha: 0.22 + 0.12 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paintMineIcon(canvas, c, geo.cell, glowTick);
    }
  }

  /// The dot's start-direction hint (game_grid `_paintStartHint`) mirrored in
  /// red for a moving destroyer: a few fading dots tracing the initial patrol
  /// path plus a small pulsing arrowhead just outside the cell, pointing the way
  /// the mine starts moving. Same size, pulse and positioning as the dot's hint.
  void _paintPatrolHint(Canvas canvas, MoverState m) {
    final r = m.row, c = m.col;
    final dr = m.horizontal ? 0 : m.dir;
    final dc = m.horizontal ? m.dir : 0;
    final center = geo.center(r, c);
    final dir = Offset(dc.toDouble(), dr.toDouble());
    final perp = Offset(-dir.dy, dir.dx);
    final cell = geo.cell;
    // Very gentle opacity breathe only (no scale pulse).
    final breathe = 0.85 + 0.15 * (0.5 + 0.5 * math.sin(glowTick * 2 * math.pi));

    // Lead dots tracing the initial path — small and faint.
    for (var k = 1; k <= 3; k++) {
      final nr = r + dr * k;
      final nc = c + dc * k;
      if (nr < 0 || nr >= geo.n || nc < 0 || nc >= geo.n) break;
      final p = geo.center(nr, nc);
      final fade = 1 - (k - 1) / 3.0; // 1 → .67 → .33
      canvas.drawCircle(
        p,
        cell * 0.07 * fade,
        Paint()..color = _red.withValues(alpha: 0.22 * fade * breathe),
      );
    }

    // Small, soft arrowhead on the leading edge — a hint, not a focal point.
    // Gentle breathing scale 1.0 → 1.15 → 1.0 over the (~1.4s) glow cycle.
    final scale = 1.0 + 0.075 * (1 - math.cos(glowTick * 2 * math.pi));
    final anchor = center + dir * (cell * 0.5 + cell * 0.04);
    final tip = anchor + dir * (cell * 0.19 * scale);
    final b1 = anchor + perp * (cell * 0.15 * scale);
    final b2 = anchor - perp * (cell * 0.15 * scale);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()..color = _red.withValues(alpha: 0.50 * breathe),
    );
  }

  @override
  bool shouldRepaint(covariant _MoverPainter old) =>
      old.t != t ||
      old.glowTick != glowTick ||
      old.movers != movers ||
      old.planning != planning;
}

/// Draws the fail-overlay icon for each [DeathCause] in the board's thick-
/// outline, rounded-cell style — reusing the very hazards seen on the grid (the
/// spiky mine, the gray wall block, the dashed gap) so the player connects the
/// death to the thing that caused it.
class _FailIconPainter extends CustomPainter {
  _FailIconPainter(this.cause);

  final DeathCause? cause;

  // Grid-matched cell colors (see game_grid `_C` / `_paintBase`).
  static const _wallFill = Color(0xFF78909C);
  static const _wallBorder = Color(0xFF5C6B73);
  static const _mineFill = Color(0xFFEF5350);
  static const _mineBorder = Color(0xFFC62828);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final pad = s * 0.08;
    final box = Rect.fromLTWH(pad, pad, s - pad * 2, s - pad * 2);

    switch (cause) {
      case DeathCause.destroyer:
        _cell(canvas, box, _mineFill, _mineBorder);
        paintMineIcon(canvas, c, s * 1.35, 0);
      case DeathCause.patrol:
        _cell(canvas, box, _mineFill, _mineBorder);
        paintMineIcon(canvas, c, s * 1.25, 0);
        _patrolArrows(canvas, c, s); // a moving mine — patrol axis badge
      case DeathCause.wall:
        _cell(canvas, box, _wallFill, _wallBorder);
        _crack(canvas, box);
      case DeathCause.gap:
        _cell(canvas, box, AppColors.background, AppColors.textSoft,
            dashed: true);
        _downArrow(canvas, c, s, const Color(0xFF6D4C41));
      case DeathCause.edge:
      case null:
        _edge(canvas, box, s);
    }
  }

  /// A rounded, thick-outlined cell — the board's signature look.
  void _cell(Canvas canvas, Rect rect, Color fill, Color border,
      {bool dashed = false}) {
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.22));
    canvas.drawRRect(rrect, Paint()..color = fill);
    final bp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.075
      ..strokeJoin = StrokeJoin.round
      ..color = border;
    if (dashed) {
      _dashRRect(canvas, rrect, bp);
    } else {
      canvas.drawRRect(rrect, bp);
    }
  }

  void _dashRRect(Canvas canvas, RRect rrect, Paint p) {
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  /// A jagged lightning crack across a wall block.
  void _crack(Canvas canvas, Rect box) {
    final w = box.width, h = box.height;
    final p = Path()
      ..moveTo(box.left + w * 0.52, box.top + h * 0.16)
      ..lineTo(box.left + w * 0.38, box.top + h * 0.46)
      ..lineTo(box.left + w * 0.56, box.top + h * 0.52)
      ..lineTo(box.left + w * 0.40, box.top + h * 0.86);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.width * 0.09
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF37474F),
    );
  }

  /// A small red double-headed horizontal arrow under the mine — "this one
  /// moves" (the patrol axis), echoing the planning-phase hint.
  void _patrolArrows(Canvas canvas, Offset c, double s) {
    final y = c.dy + s * 0.30;
    final half = s * 0.26;
    final p = Paint()
      ..color = _mineBorder
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final left = Offset(c.dx - half, y);
    final right = Offset(c.dx + half, y);
    canvas.drawLine(left, right, p);
    final head = s * 0.10;
    canvas.drawLine(left, left + Offset(head, -head), p);
    canvas.drawLine(left, left + Offset(head, head), p);
    canvas.drawLine(right, right + Offset(-head, -head), p);
    canvas.drawLine(right, right + Offset(-head, head), p);
  }

  /// A downward arrow falling into the (dashed) gap.
  void _downArrow(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final top = Offset(c.dx, c.dy - s * 0.22);
    final tip = Offset(c.dx, c.dy + s * 0.20);
    canvas.drawLine(top, tip, p);
    final head = s * 0.16;
    canvas.drawLine(tip, tip + Offset(-head, -head), p);
    canvas.drawLine(tip, tip + Offset(head, -head), p);
  }

  /// The dot leaving the board: a ball inside the cell and an arrow piercing out
  /// through the right edge.
  void _edge(Canvas canvas, Rect box, double s) {
    // Cell sits on the left, leaving room for the arrow to exit on the right.
    final cellRect =
        Rect.fromLTWH(box.left, box.top, box.width * 0.66, box.height);
    _cell(canvas, cellRect, AppColors.card, AppColors.ink);

    final cy = cellRect.center.dy;
    // The dot.
    canvas.drawCircle(
      Offset(cellRect.left + cellRect.width * 0.40, cy),
      s * 0.11,
      Paint()..color = AppColors.accent,
    );
    // Arrow shaft + head crossing the cell's right wall and exiting.
    const amber = Color(0xFFF59E0B);
    final p = Paint()
      ..color = amber
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final shaftStart = Offset(cellRect.right - s * 0.06, cy);
    final tip = Offset(box.right + s * 0.04, cy);
    canvas.drawLine(shaftStart, tip, p);
    final head = s * 0.14;
    canvas.drawLine(tip, tip + Offset(-head, -head), p);
    canvas.drawLine(tip, tip + Offset(-head, head), p);
  }

  @override
  bool shouldRepaint(covariant _FailIconPainter old) => old.cause != cause;
}
