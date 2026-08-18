// Settings: sound, haptics, ad preferences, achievements and the outward links.
//
// Styled to the game rather than to Material: cream field, thick ink outlines,
// The brief for this screen described
// Dotto as dark with gold accents, which is not what the app looks like — the
// board, the menu and the icon are all cream with an ink outline (AppColors),
// and a dark settings page would read as another app's screen.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics/analytics_service.dart';
import '../consent/consent_manager.dart';
import '../services/game_services.dart';
import '../services/music_service.dart';
import '../services/notification_service.dart';
import '../settings/haptics.dart';
import '../settings/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';
import 'notification_settings_screen.dart';

/// Where "Rate the app" points. The Android form opens the Play app directly;
/// the https form is the fallback for a device with no Play app installed.
const _playMarketUrl = 'market://details?id=com.karimkod.dotto';
const _playWebUrl =
    'https://play.google.com/store/apps/details?id=com.karimkod.dotto';

/// The App Store id is assigned when the app is first created in App Store
/// Connect. Until it is known, iOS falls back to a search for the app by name —
/// which lands the player in the right place without pretending to a numeric id
/// that would 404.
const _appStoreUrl = 'https://apps.apple.com/search?term=dotto%20puzzle';

const _privacyUrl = 'https://reshaped.dev/projects/dotto/privacy';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _sound = SettingsStore.soundOn;
  late bool _music = MusicService.isEnabled;
  late bool _haptics = SettingsStore.hapticsOn;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // No platform channel (tests, or an unsupported platform). The About
      // block simply shows no version rather than the screen failing.
    }
  }

  Future<void> _open(String url, {String? fallback}) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && fallback != null) {
        await launchUrl(Uri.parse(fallback),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (fallback == null) return;
      try {
        await launchUrl(Uri.parse(fallback),
            mode: LaunchMode.externalApplication);
      } catch (_) {
        // Nothing on the device can open it. Silence beats an error dialog for
        // a link the player can live without.
      }
    }
  }

  /// Re-open Google's consent form so the choice can be changed.
  ///
  /// Straight to the form, with no pre-prompt: a player who went looking for
  /// this has already been told what it is for, and an explainer in front of a
  /// form they asked for is friction.
  ///
  /// No ATT prompt either — iOS allows that once, and a second request returns
  /// the prior answer without showing anything. Changing it means going to iOS
  /// Settings, which is Apple's design, not ours.
  Future<void> _openAdPreferences() async {
    await ConsentManager.reopenForm();
  }

  /// Open the platform achievements screen, prompting for sign-in if needed.
  ///
  /// [GameServices.showAchievements] handles the sign-in itself, so the only
  /// thing left here is what to say when it could not happen — named after the
  /// service the player would actually be signing in to, rather than the
  /// generic phrase that meant nothing on either platform. Only when there is
  /// no account, though: asking a player who just came back from the Play
  /// Games account picker to sign in reads as the sign-in having failed.
  Future<void> _showAchievements() async {
    if (await GameServices.showAchievements()) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          GameServices.signedIn
              ? "Couldn't open achievements. Try again."
              : 'Sign in to ${GameServices.platformName} to view achievements',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// The notifications sub-screen. Awaited so the row's own state — which
  /// depends on OS permission the player may have changed while in there — is
  /// re-read on the way back.
  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
    if (mounted) setState(() {});
  }

  void _rate() {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (isAndroid) {
      _open(_playMarketUrl, fallback: _playWebUrl);
    } else {
      _open(_appStoreUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsHeader(title: 'Settings'),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    SettingsToggleRow(
                      icon: Icons.volume_up_rounded,
                      label: 'Sound',
                      value: _sound,
                      onChanged: (v) {
                        setState(() => _sound = v);
                        SettingsStore.setSound(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SettingsToggleRow(
                      icon: Icons.music_note_rounded,
                      label: 'Music',
                      value: _music,
                      onChanged: (v) {
                        setState(() => _music = v);
                        // Fades out or back in on the spot. Independent of
                        // Sound on purpose: a player who wants the game's
                        // feedback but not a backing track — or the other way
                        // round — has asked for two different things.
                        MusicService.setEnabled(v);
                        Analytics.musicToggled(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SettingsToggleRow(
                      icon: Icons.vibration_rounded,
                      label: 'Haptics',
                      value: _haptics,
                      onChanged: (v) {
                        setState(() => _haptics = v);
                        SettingsStore.setHaptics(v);
                        // Demonstrate what was just switched on.
                        if (v) Haptics.medium();
                      },
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 12),
                      SettingsActionRow(
                        icon: Icons.ads_click_rounded,
                        label: 'Ad preferences',
                        onTap: _openAdPreferences,
                      ),
                    ],
                    // Only where notifications can actually be delivered.
                    if (NotificationService.supported) ...[
                      const SizedBox(height: 12),
                      SettingsActionRow(
                        icon: Icons.notifications_rounded,
                        label: 'Notifications',
                        onTap: _openNotifications,
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Only offered where it can actually open something. Game
                    // Center and Play Games have their own screens; a row that
                    // did nothing would be worse than no row.
                    if (GameServices.supported) ...[
                      SettingsActionRow(
                        icon: Icons.emoji_events_rounded,
                        label: 'Achievements',
                        onTap: _showAchievements,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SettingsActionRow(
                      icon: Icons.star_rounded,
                      label: 'Rate the app',
                      onTap: _rate,
                    ),
                    const SizedBox(height: 12),
                    SettingsActionRow(
                      icon: Icons.privacy_tip_rounded,
                      label: 'Privacy policy',
                      onTap: () => _open(_privacyUrl),
                    ),
                    const SizedBox(height: 32),
                    _About(version: _version),
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

class _About extends StatelessWidget {
  const _About({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Dotto',
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.75),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        if (version.isNotEmpty)
          Text(
            'Version $version',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Made by Reshaped',
          style: TextStyle(
            color: AppColors.text.withValues(alpha: 0.55),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
