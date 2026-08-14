// The player's own numbers: how far up the path they are, what they have spent
// getting there, and how the weekly challenges have gone.
//
// Read-only by design. Everything on it is already stored somewhere else —
// ProgressStore, ChallengeService, FreeHintService — and this screen owns none
// of it. It is the one place the profile tile in the top bar has ever led.

import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../progress/progress_store.dart';
import '../services/challenge_service.dart';
import '../services/free_hint_service.dart';
import '../services/game_services.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// The gamer tag, once the platform has answered. Null until then, and null
  /// forever when nobody is signed in — the title falls back either way, so
  /// there is nothing to wait on before the first frame.
  String? _name;

  @override
  void initState() {
    super.initState();
    GameServices.playerName().then((name) {
      if (mounted && name != null) setState(() => _name = name);
    });
  }

  /// The world the player is currently working through: the world of the next
  /// level to play, or the last world once every level is done.
  int get _currentWorld {
    final levels = buildInitialLevels();
    final next = levels.firstWhere(
      (l) => l.isUnlocked,
      orElse: () => levels.last,
    );
    return worldOf(next.number);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final completed = ProgressStore.completed().length;
    final inHand = ChallengeService.hintsInHand;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _RoundIcon(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(child: _Header(name: _name)),
                  const SizedBox(width: 46),
                ],
              ),
              const SizedBox(height: 22),
              _ProgressBar(completed: completed, total: kLevelCount),
              const SizedBox(height: 22),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _StatRow(
                        left: _StatTile(
                          icon: Icons.flag_rounded,
                          tint: AppColors.coral,
                          label: 'Levels',
                          value: '$completed / $kLevelCount',
                        ),
                        right: _StatTile(
                          icon: Icons.map_rounded,
                          tint: AppColors.accent,
                          label: 'World',
                          value: '$_currentWorld',
                          sub: 'of 7',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatRow(
                        left: _StatTile(
                          icon: Icons.lightbulb_rounded,
                          tint: AppColors.star,
                          label: 'Hints used',
                          value: '${ProgressStore.hintsUsed()}',
                          sub: 'all time',
                        ),
                        right: _StatTile(
                          icon: Icons.local_fire_department_rounded,
                          tint: AppColors.coral,
                          label: 'Streak',
                          value: '${ChallengeService.streakAt(now)}',
                          sub: 'weeks in a row',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatRow(
                        left: _StatTile(
                          icon: Icons.calendar_today_rounded,
                          tint: AppColors.accent,
                          label: 'Challenges',
                          value: '${ChallengeService.completedCount}',
                          sub: 'completed',
                        ),
                        right: _StatTile(
                          icon: Icons.auto_awesome_rounded,
                          tint: AppColors.star,
                          label: 'Hints ready',
                          value: '$inHand',
                          // When the hand is empty, the useful number is not
                          // the zero — it is when it stops being zero.
                          sub: inHand == 0
                              ? _nextHintLabel(now)
                              : 'of ${ChallengeService.maxHints}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _nextHintLabel(DateTime now) {
    final left = FreeHintService.remainingLabel(now);
    return left.isEmpty ? 'ready soon' : 'back in $left';
  }
}

/// The screen title: the gamer tag when there is one, with the fallback title
/// demoted to a caption underneath so the screen still says what it is.
class _Header extends StatelessWidget {
  const _Header({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final title = name ?? 'Your Progress';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shrink-to-fit rather than ellipsis: a gamer tag is a name, and a name
        // is worth reading in full even at half the size.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: AppTheme.title.copyWith(fontSize: 32),
          ),
        ),
        if (name != null) ...[
          const SizedBox(height: 2),
          Text(
            'YOUR PROGRESS',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

/// The campaign in one line: how much of the path is behind them.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.playGradient),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(fraction * 100).round()}% complete',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

/// Two tiles side by side, equal width and equal height.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        ),
      );
}

/// One statistic: a tinted icon, the number, and what the number is.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.ink, size: 19),
          ),
          const SizedBox(height: 10),
          // Scaled down rather than wrapped: "42 / 110" belongs on one line.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: const TextStyle(
                color: AppColors.textSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/// The back button, matching the one on the challenges screen.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BouncyButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: Icon(icon, color: AppColors.ink, size: 22),
        ),
      );
}
