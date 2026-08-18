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
  const SignInScreen({super.key, required this.onDone, this.signIn});

  /// Called once the player has answered, either way.
  final VoidCallback onDone;

  /// How to sign in. Defaults to [GameServices.ensureSignedIn], and injectable
  /// only so a test can hold an attempt open: that is the state this screen has
  /// to stay usable in, and there is no other way to put it in it.
  final Future<bool> Function()? signIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  bool _signedIn = false;

  /// Whether the player has been sent on, so it happens once.
  ///
  /// Both answers can now be given during one attempt, because "Maybe later"
  /// stays live while a sign-in is in flight. So a skip and a sign-in that lands
  /// just after it can both reach [SignInScreen.onDone], and `mounted` does not
  /// separate them: onDone replaces the route, and the replaced route is not
  /// disposed until its transition finishes. Calling onDone twice pushes the menu
  /// twice.
  bool _answered = false;

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

  /// Sends the player on, at most once.
  void _finish() {
    if (_answered) return;
    _answered = true;
    widget.onDone();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Marked before the attempt, not after: a player who reaches the platform's
    // own dialog has been asked, whatever they do with it, and a crash or a
    // force-quit mid-prompt should not mean being asked again next launch.
    GameServices.markSignInPrompted();

    final ok = await (widget.signIn ?? GameServices.ensureSignedIn)();
    // `_answered` as well as `mounted`: they may have given up and skipped while
    // this was still running, and that answer stands. Reporting this one too
    // would put two outcomes in the funnel for one screen.
    if (!mounted || _answered) return;

    if (!ok) {
      // Declined, cancelled, or unavailable. Straight on without comment.
      // The spinner is cleared first: onDone normally navigates away, but if it
      // ever did not, a button left spinning is a dead end.
      setState(() => _busy = false);
      Analytics.onboardingSignInFailed();
      _finish();
      return;
    }
    Analytics.onboardingSignInAccepted();
    setState(() {
      _signedIn = true;
      _busy = false;
    });
    await _tick.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) _finish();
  }

  void _skip() {
    if (_answered) return;
    Analytics.onboardingSignInSkipped();
    GameServices.markSignInPrompted();
    _finish();
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
                  // Live during an attempt, unlike the Sign In button above.
                  // This is the only way off a screen that cannot be popped, so
                  // disabling it while waiting on the platform made a sign-in
                  // that never answered into a trap with no exit but a
                  // force-quit. GameServices.ensureSignedIn now has a deadline
                  // too, but 90 seconds of a dead spinner is still a screen
                  // worth being able to leave.
                  TextButton(
                    onPressed: _skip,
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
