// The pre-prompt: what the next screen is about, before Google's form arrives.
//
// It offers no choice of its own. UMP asks the actual question and owns the
// answer; this exists so the form does not land on a player cold, which is both
// kinder and the pattern Google recommends. Because it decides nothing, there
// is no way to dismiss it without continuing — the only path forward is the one
// button.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

const _privacyUrl = 'https://reshaped.dev/projects/dotto/privacy';

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onContinue});

  /// Runs the UMP form, then ATT, then moves on.
  final VoidCallback onContinue;

  Future<void> _openPrivacy() async {
    try {
      await launchUrl(Uri.parse(_privacyUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing can open it. Silence rather than an error over a link.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Nothing behind this yet, and nothing decided by leaving it.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        const _DotMark(),
                        const SizedBox(height: 32),
                        Text(
                          'Before we start…',
                          style: AppTheme.title,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Dotto is free and supported by ads. On the next '
                          'screen, you can choose how your data is used.',
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
                BouncyButton(
                  onTap: onContinue,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.ink, width: 3),
                    ),
                    child: const Center(
                      child: Text(
                        'Continue',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _openPrivacy,
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: AppColors.text.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You can change this anytime in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dot, drawn rather than loaded — the same mark as the app icon, so the
/// first screen is recognisably this game's.
class _DotMark extends StatelessWidget {
  const _DotMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [Color(0xFFFFD9A0), AppColors.accent, Color(0xFFF59331)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: AppColors.ink, width: 4),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.28),
            blurRadius: 28,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}
