// The one time Dotto asks about signing in.
//
// It is the last step of onboarding and never comes back: whatever the player
// answers, the offer is marked as made. Someone who skips can still sign in
// from Settings → Achievements, which is the right way round — an optional
// feature that asks every launch stops being optional and starts being a
// nuisance.
//
// Both answers lead to the same place. Declining is not a failure state and is
// not treated as one: no warning, no second ask, no explanation of what they
// are missing.

import 'package:flutter/material.dart';

import '../analytics/analytics_service.dart';
import '../services/game_services.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onDone});

  /// Called once the player has answered, either way.
  final VoidCallback onDone;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  bool _signedIn = false;

  /// The tick that confirms it worked. Short — it is an acknowledgement, not a
  /// celebration.
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void initState() {
    super.initState();
    Analytics.onboardingSignInShown();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Marked before the attempt, not after: a player who reaches the platform's
    // own dialog has been asked, whatever they do with it, and a crash or a
    // force-quit mid-prompt should not mean being asked again next launch.
    GameServices.markSignInPrompted();

    final ok = await GameServices.ensureSignedIn();
    if (!mounted) return;

    if (!ok) {
      // Declined, cancelled, or unavailable. Straight on without comment.
      // The spinner is cleared first: onDone normally navigates away, but if it
      // ever did not, a button left spinning is a dead end.
      setState(() => _busy = false);
      Analytics.onboardingSignInFailed();
      widget.onDone();
      return;
    }
    Analytics.onboardingSignInAccepted();
    setState(() {
      _signedIn = true;
      _busy = false;
    });
    await _tick.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) widget.onDone();
  }

  void _skip() {
    Analytics.onboardingSignInSkipped();
    GameServices.markSignInPrompted();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Leaving without answering would skip the question while leaving it
      // pending, so the only ways out are the two buttons.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Badge(signedIn: _signedIn, tick: _tick),
                        const SizedBox(height: 32),
                        Text(
                          _signedIn ? 'You’re all set' : 'Save your progress',
                          style: AppTheme.title,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _signedIn
                              ? 'Your progress will follow you between devices.'
                              : 'Sign in to save your progress across devices '
                                  'and earn achievements.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.text.withValues(alpha: 0.8),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Both buttons disappear once signed in — the screen is on its
                // way out, and a button that does nothing is worse than none.
                if (!_signedIn) ...[
                  BouncyButton(
                    onTap: _busy ? null : _signIn,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(
                          alpha: _busy ? 0.55 : 1,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.ink, width: 3),
                      ),
                      child: Center(
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation(
                                    AppColors.ink,
                                  ),
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _busy ? null : _skip,
                    child: Text(
                      'Maybe later',
                      style: TextStyle(
                        color: AppColors.text.withValues(alpha: 0.7),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trophy, or the tick that replaces it once signed in.
class _Badge extends StatelessWidget {
  const _Badge({required this.signedIn, required this.tick});

  final bool signedIn;
  final Animation<double> tick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
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
      child: signedIn
          ? ScaleTransition(
              scale: CurvedAnimation(parent: tick, curve: Curves.elasticOut),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF4CAF50), size: 54),
            )
          : const Icon(Icons.emoji_events_rounded,
              color: AppColors.accent, size: 52),
    );
  }
}
