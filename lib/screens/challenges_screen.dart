// The challenges list: this week's, then everything that has been.
//
// Styled like the rest of the game — cream field, white cards, thick ink
// outlines — rather than as a feed. Challenges are boards, so they should look
// like the boards do.

import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/level.dart';
import '../services/challenge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';
import 'game_screen.dart';

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  @override
  void initState() {
    super.initState();
    // A refresh on open, so a challenge published since launch appears without
    // restarting. The list already on screen is whatever was cached; this
    // replaces it if the fetch succeeds.
    ChallengeService.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _play(Challenge c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          // The board is carried directly rather than looked up by number:
          // challenge levels are not part of the campaign and have no id in it.
          levelOverride: c.level,
          challenge: c,
          level: Level(
            id: -1,
            number: -1,
            title: c.title,
            difficulty: Difficulty.medium,
            status: LevelStatus.unlocked,
          ),
        ),
      ),
    );
    if (mounted) setState(() {}); // completion may have changed
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final current = ChallengeService.currentAt(now);
    final past = ChallengeService.pastAt(now);
    final streak = ChallengeService.streakAt(now);

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
                  Expanded(
                    child: Center(
                      child: Text('Challenges', style: AppTheme.title),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
              if (streak > 0) ...[
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.coral, width: 2),
                    ),
                    child: Text(
                      '🔥 $streak week${streak == 1 ? '' : 's'} in a row',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: current == null && past.isEmpty
                    ? const _Empty()
                    : ListView(
                        children: [
                          if (current != null) ...[
                            const _Heading('This week'),
                            _ChallengeCard(
                              challenge: current,
                              now: now,
                              isCurrent: true,
                              onPlay: () => _play(current),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (past.isNotEmpty) const _Heading('Past'),
                          for (final c in past) ...[
                            _ChallengeCard(
                              challenge: c,
                              now: now,
                              isCurrent: false,
                              onPlay: () => _play(c),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.now,
    required this.isCurrent,
    required this.onPlay,
  });

  final Challenge challenge;
  final DateTime now;
  final bool isCurrent;
  final VoidCallback onPlay;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _range() {
    final s = challenge.startDate;
    final e = challenge.endDate;
    return '${_months[s.month - 1]} ${s.day} – ${_months[e.month - 1]} ${e.day}';
  }

  @override
  Widget build(BuildContext context) {
    final done = ChallengeService.isCompleted(challenge.id);
    final days = challenge.daysRemainingAt(now);

    return BouncyButton(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          // The live one wears the accent so it reads first.
          border: Border.all(
            color: isCurrent ? AppColors.accent : AppColors.ink,
            width: 3,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    challenge.title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (done)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF4CAF50), size: 26)
                else
                  const Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.coral, size: 26),
              ],
            ),
            if (challenge.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                challenge.description,
                style: TextStyle(
                  color: AppColors.text.withValues(alpha: 0.75),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  _range(),
                  style: TextStyle(
                    color: AppColors.text.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (challenge.reward == ChallengeReward.hint)
                  _Pill(
                    // Says what it gives, not that a reward exists.
                    label: done ? '💡 claimed' : '💡 +1 hint',
                    faded: done,
                  ),
              ],
            ),
            if (isCurrent && !done) ...[
              const SizedBox(height: 8),
              Text(
                days == 0 ? 'Ends today' : '$days day${days == 1 ? '' : 's'} left',
                style: const TextStyle(
                  color: AppColors.coral,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.faded = false});
  final String label;
  final bool faded;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: faded ? 0.18 : 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.ink.withValues(alpha: faded ? 0.6 : 1),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗓️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('Challenges coming soon!', style: AppTheme.title),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'A new board to beat every week. Check back shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.text.withValues(alpha: 0.6),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

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
