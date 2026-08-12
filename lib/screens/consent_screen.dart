// The first thing a new player sees: how their data may be used.
//
// Two ways in. On first launch it is the app's home, with no way past it but a
// choice — no back button, and the system back gesture is blocked, because
// "dismissed without answering" is not a state the ad SDKs can act on. From
// Settings it is an ordinary pushed route the player can leave, since a choice
// already exists to fall back on.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../consent/consent_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

const _privacyUrl = 'https://reshaped.dev/projects/dotto/privacy';

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({
    super.key,
    required this.onChosen,
    this.isUpdate = false,
  });

  /// Called with the choice. On first launch this continues into the game; from
  /// Settings it pops back.
  final ValueChanged<AdConsent> onChosen;

  /// True when reached from Settings, where a choice already exists.
  final bool isUpdate;

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
      // Onboarding cannot be dismissed: there is no game behind it yet, and no
      // answer to act on. In update mode the player already has a choice on
      // file, so leaving is harmless.
      canPop: isUpdate,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                if (isUpdate)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BouncyButton(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              const Border.fromBorderSide(BorderSide(
                            color: AppColors.ink,
                            width: 3,
                          )),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.ink, size: 22),
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        const _DotMark(),
                        const SizedBox(height: 28),
                        Text(
                          isUpdate ? 'Ad preferences' : 'Before we start…',
                          style: AppTheme.title,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Dotto is free and supported by ads. You can choose '
                          'how your data is used:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.text.withValues(alpha: 0.8),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _ChoiceButton(
                          label: 'Personalized Ads',
                          detail: 'Ads matched to your interests.',
                          filled: true,
                          onTap: () => onChosen(AdConsent.personalized),
                        ),
                        const SizedBox(height: 14),
                        _ChoiceButton(
                          label: 'Standard Ads',
                          detail: 'Ads not based on your data. More private.',
                          filled: false,
                          onTap: () => onChosen(AdConsent.standard),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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

/// One of the two choices. Filled is the recommended path, outlined the more
/// private one — both are full-width and the same size, so neither is buried.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.detail,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
          ],
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
