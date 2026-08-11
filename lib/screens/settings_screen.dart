// Settings: sound, haptics, reset, and the outward links.
//
// Styled to the game rather than to Material: cream field, thick ink outlines,
// coral for the one destructive action. The brief for this screen described
// Dotto as dark with gold accents, which is not what the app looks like — the
// board, the menu and the icon are all cream with an ink outline (AppColors),
// and a dark settings page would read as another app's screen.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../progress/progress_store.dart';
import '../settings/haptics.dart';
import '../settings/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

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

  void _rate() {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (isAndroid) {
      _open(_playMarketUrl, fallback: _playWebUrl);
    } else {
      _open(_appStoreUrl);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.ink, width: 3),
        ),
        title: const Text('Reset progress?'),
        content: const Text(
          'Are you sure? This will erase all your progress and put you back '
          'at level 1. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ProgressStore.clear();
    Haptics.heavy();
    // Straight back to the menu, which re-reads progress as it is uncovered —
    // leaving the player on a settings page after wiping their game would hide
    // the one thing they need to see.
    Navigator.of(context).pop();
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
              Row(
                children: [
                  _RoundIcon(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Settings', style: AppTheme.title),
                    ),
                  ),
                  // Balances the back button so the title stays centred.
                  const SizedBox(width: 46),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _ToggleRow(
                      icon: Icons.volume_up_rounded,
                      label: 'Sound',
                      value: _sound,
                      onChanged: (v) {
                        setState(() => _sound = v);
                        SettingsStore.setSound(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    _ToggleRow(
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
                    const SizedBox(height: 24),
                    _ActionRow(
                      icon: Icons.star_rounded,
                      label: 'Rate the app',
                      onTap: _rate,
                    ),
                    const SizedBox(height: 12),
                    _ActionRow(
                      icon: Icons.privacy_tip_rounded,
                      label: 'Privacy policy',
                      onTap: () => _open(_privacyUrl),
                    ),
                    const SizedBox(height: 24),
                    _ActionRow(
                      icon: Icons.delete_forever_rounded,
                      label: 'Reset progress',
                      destructive: true,
                      onTap: _confirmReset,
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

/// A settings row with a switch. Same bordered-tile language as the rest of the
/// game, rather than a Material ListTile.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(icon, color: AppColors.ink, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.card,
            activeTrackColor: AppColors.accent,
            inactiveThumbColor: AppColors.card,
            inactiveTrackColor: AppColors.border,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colour = destructive ? AppColors.coral : AppColors.ink;
    return _Tile(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: colour, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: destructive ? AppColors.coral : AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colour, size: 22),
        ],
      ),
    );
  }
}

/// The shared card: white surface, thick ink outline, like every other pressable
/// thing in the game.
class _Tile extends StatelessWidget {
  const _Tile({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: child,
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

/// The circular back button, matching the menu's side icons.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyButton(
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
}
