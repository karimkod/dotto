// The player, as Play Games (or Game Center) knows them, with Dotto's numbers
// underneath.
//
// The identity at the top belongs to the platform: the gamer tag and the avatar
// are fetched, never stored here, and there is no Dotto-side profile to edit.
// The stats below belong to the app — ProgressStore and ChallengeService own
// them, this screen only reads. The achievement count is the one number that
// comes from the platform, because it is the only one that survives a reinstall
// or was earned on another device.
//
// Signed out, the whole top half becomes a single offer to sign in, and the
// stats stay: they are the player's own progress either way.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../progress/progress_store.dart';
import '../services/challenge_service.dart';
import '../services/game_services.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// How far the platform has got with the question "who is this player".
///
/// Three states rather than two, because the screen used to have no way to say
/// the third one. A null profile left it drawing the signed-in layout with
/// nothing in it — the word "Player" over a placeholder avatar — which is
/// indistinguishable from a gamer tag that simply has not arrived, offers
/// nothing to do about it, and stays that way for as long as the screen is
/// open.
enum _Identity {
  /// Asked, and not answered yet.
  loading,

  /// Answered with a player.
  loaded,

  /// Answered with nobody, for a player this app believes is signed in.
  ///
  /// A platform that could not be reached, or a session that has outlived the
  /// flag remembering it. Which one is not knowable from here and does not
  /// change what to offer: asking again is the whole remedy either way.
  unavailable,
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// The gamer tag and avatar, once the platform has answered. Null until then,
  /// and null forever when nobody is signed in.
  PlayerProfile? _profile;

  /// Unlocked and total achievements as the platform counts them. Null while it
  /// is being asked, and when it declines to say.
  (int, int)? _achievements;

  /// How the identity fetch is going. Only consulted while signed in — signed
  /// out there is nobody to fetch, and the offer stands in its place.
  _Identity _identity = _Identity.loading;

  /// Whether a sign-in is in flight, so the button can say so and cannot be
  /// tapped twice into two platform dialogs.
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ask the platform for everything it can tell us. Each answer lands on its
  /// own — the avatar is a round trip, the achievement list is a longer one, and
  /// there is no reason for the first to wait on the second.
  ///
  /// The profile answer is recorded whether or not it arrived. A null is a real
  /// answer — "the platform has nobody to describe" — and the screen has to be
  /// able to draw it, which is what it could not do before.
  void _load() {
    _identity = _Identity.loading;
    GameServices.playerProfile().then((profile) {
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _identity = profile == null ? _Identity.unavailable : _Identity.loaded;
      });
    });
    GameServices.achievementProgress().then((counts) {
      if (mounted && counts != null) setState(() => _achievements = counts);
    });
  }

  /// Ask again, from the button the unavailable state offers.
  ///
  /// Worth offering rather than futile: [GameServices.playerProfile] signs in
  /// again on its way through, so a retry is a real second attempt at the
  /// session rather than a second read of the same dead one.
  void _retry() => setState(_load);

  /// The Sign In button. A player action, so this is one of the few places
  /// allowed to raise the platform's own account picker.
  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    final ok = await GameServices.ensureSignedIn();
    if (!mounted) return;
    // Declining is not a failure state and is not reported as one. The screen
    // simply stays as it was, with the offer still standing.
    setState(() {
      _signingIn = false;
      if (ok) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final completed = ProgressStore.completed().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _RoundIcon(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      _Avatar(icon: _profile?.icon),
                      const SizedBox(height: 14),
                      _identityBlock(),
                      const SizedBox(height: 24),
                      _ProgressBar(completed: completed, total: kLevelCount),
                      const SizedBox(height: 20),
                      _StatRow(
                        left: _StatTile(
                          icon: Icons.flag_rounded,
                          tint: AppColors.coral,
                          label: 'Levels',
                          value: '$completed / $kLevelCount',
                        ),
                        right: _StatTile(
                          icon: Icons.emoji_events_rounded,
                          tint: AppColors.star,
                          label: 'Achievements',
                          value: _achievementValue,
                          sub: _achievementSub,
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
                          icon: Icons.lightbulb_rounded,
                          tint: AppColors.star,
                          label: 'Hints used',
                          value: '${ProgressStore.hintsUsed()}',
                          sub: 'all time',
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

  /// What sits under the avatar: the gamer tag, the offer to sign in, or an
  /// admission that the platform did not answer.
  ///
  /// Signed out is decided first and on its own. Whether an identity fetch is
  /// in flight is beside the point for a player with no account — there is
  /// nothing to fetch, and the offer is the only useful thing to show.
  Widget _identityBlock() {
    if (!GameServices.signedIn) {
      return _SignInOffer(busy: _signingIn, onTap: _signIn);
    }
    return switch (_identity) {
      _Identity.loading => const _IdentityLoading(),
      _Identity.loaded => _GamerTag(name: _profile?.name),
      _Identity.unavailable => _IdentityUnavailable(onTap: _retry),
    };
  }

  /// The unlocked count once the platform has given one. Until then the
  /// denominator alone is still true and still worth reading, so the tile shows
  /// the target rather than an empty box that might never fill.
  String get _achievementValue {
    final counts = _achievements;
    if (counts == null) return '${GameServices.achievementCount}';
    return '${counts.$1} / ${counts.$2}';
  }

  String get _achievementSub {
    if (_achievements != null) return 'unlocked';
    return GameServices.signedIn ? 'to unlock' : 'sign in to track';
  }
}

/// The profile picture, or the placeholder that stands in for one.
///
/// Same circle either way: a signed-out player should see the shape of what
/// they are being offered, not a gap where it will go.
class _Avatar extends StatelessWidget {
  const _Avatar({this.icon});

  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: AppColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 4),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: icon == null
            ? const _AvatarFallback()
            : SizedBox.expand(
                child: Image.memory(
                  icon!,
                  fit: BoxFit.cover,
                  // Bytes that decode to nothing useful are a missing picture,
                  // which the placeholder already covers.
                  errorBuilder: (_, _, _) => const _AvatarFallback(),
                ),
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(Icons.person_rounded, color: AppColors.accent, size: 58),
      );
}

/// The gamer tag, with what it is written underneath.
class _GamerTag extends StatelessWidget {
  const _GamerTag({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shrink-to-fit rather than ellipsis: a gamer tag is a name, and a name
        // is worth reading in full even at half the size.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            // The name is a round trip behind the first frame, and the platform
            // may withhold it altogether.
            name ?? 'Player',
            maxLines: 1,
            style: AppTheme.title.copyWith(fontSize: 30),
          ),
        ),
        const SizedBox(height: 2),
        const _PlatformLabel(),
      ],
    );
  }
}

/// Which service the name above came from. Shared so the loading state can keep
/// it in place while the name itself is still on its way.
class _PlatformLabel extends StatelessWidget {
  const _PlatformLabel();

  @override
  Widget build(BuildContext context) => Text(
        GameServices.platformName.toUpperCase(),
        style: TextStyle(
          color: AppColors.text.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      );
}

/// The gamer tag's place while the platform is still being asked.
///
/// Built to [_GamerTag]'s shape — a line where the name goes, the platform's
/// name under it — so nothing below shifts when the answer lands.
class _IdentityLoading extends StatelessWidget {
  const _IdentityLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 38,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(
                  AppColors.accent.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const _PlatformLabel(),
      ],
    );
  }
}

/// What stands where the gamer tag goes when the platform had nothing to say
/// about a player it is supposed to know.
///
/// Says so plainly and offers the retry, rather than the nameless "Player" over
/// a placeholder avatar this replaced — which looked like a loaded profile
/// belonging to nobody and gave the player nothing to do about it.
///
/// The last line is the important one: everything below on this screen is read
/// from local progress and is entirely unaffected, and a player who has just
/// been told their profile is unavailable should not have to wonder.
class _IdentityUnavailable extends StatelessWidget {
  const _IdentityUnavailable({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _IdentityMessage(
        title: 'Profile unavailable',
        body: "Couldn't reach ${GameServices.platformName} for your gamer tag\n"
            'and avatar. Your progress below is unaffected.',
        action: _PillButton(label: 'Try Again', onTap: onTap),
      );
}

/// The shape both of the screen's non-identities take: a heading, a line
/// explaining it, and one thing to do about it.
class _IdentityMessage extends StatelessWidget {
  const _IdentityMessage({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTheme.title.copyWith(fontSize: 26)),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.75),
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        action,
      ],
    );
  }
}

/// The screen's one button shape: accent fill, ink border, and a spinner in
/// place of its label while what it started is still going.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: busy ? 0.55 : 1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: busy
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(AppColors.ink),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

/// What stands where the gamer tag goes when nobody is signed in.
class _SignInOffer extends StatelessWidget {
  const _SignInOffer({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _IdentityMessage(
        title: 'Not signed in',
        body: 'Sign in to ${GameServices.platformName} for your gamer tag,\n'
            'avatar and achievements.',
        action: _PillButton(label: 'Sign In', busy: busy, onTap: onTap),
      );
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
