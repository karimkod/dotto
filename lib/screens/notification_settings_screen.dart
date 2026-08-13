// Which notifications Dotto may send.
//
// Three switches, because they are three different bargains: an announcement we
// push, a reminder about something the player owns, and a nudge about something
// about to lapse. Someone can reasonably want the first and not the third.
//
// The preferences are real whether or not the OS is currently allowing
// notifications. If permission is missing the rows are dimmed rather than
// hidden and a line explains where to fix it — hiding them would make the
// screen look broken, and silently keeping a switch "on" that can post nothing
// is a lie the player has no way to see through.

import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_tiles.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late bool _challenges = NotificationService.challengeAlerts;
  late bool _hints = NotificationService.hintReminders;
  late bool _streaks = NotificationService.streakReminders;
  late bool _permitted = NotificationService.permissionGranted;

  @override
  void initState() {
    super.initState();
    // The player may have just come back from the OS settings app having
    // granted permission, so it is re-read rather than trusted from launch.
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final ok = await NotificationService.refreshPermission();
    if (!mounted || ok == _permitted) return;
    setState(() => _permitted = ok);
  }

  /// Open the OS screen where notifications can be turned back on.
  ///
  /// Done per-platform rather than through a package that covers both. The
  /// obvious one, `app_settings`, ships only a Swift Package and no podspec,
  /// and this project's iOS pipeline pins CocoaPods — which does not fail
  /// locally on Windows or Android, only in the macOS CI job, at `pub get`,
  /// before anything is built. Not worth that for one link.
  ///
  /// Both paths are best-effort: the row above already says what is wrong,
  /// which is the part that matters. The link is a shortcut, not the message.
  Future<void> _openSystemSettings() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        // Straight to this app's notification settings, rather than the app
        // info page they would then have to find "Notifications" on.
        const intent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: {'android.provider.extra.APP_PACKAGE': 'com.karimkod.dotto'},
        );
        await intent.launch();
      } else if (Platform.isIOS) {
        // iOS has no notification-specific deep link; this lands on Dotto's own
        // settings page, where Notifications is the first row.
        await launchUrl(Uri.parse('app-settings:'));
      }
    } catch (_) {
      // Nothing on the device can open it.
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
              const SettingsHeader(title: 'Notifications'),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    if (!_permitted) ...[
                      _BlockedNote(onOpen: _openSystemSettings),
                      const SizedBox(height: 16),
                    ],
                    SettingsToggleRow(
                      icon: Icons.emoji_events_rounded,
                      label: 'Challenge alerts',
                      subtitle: 'When a new weekly challenge arrives',
                      value: _challenges,
                      enabled: _permitted,
                      onChanged: (v) {
                        setState(() => _challenges = v);
                        NotificationService.setChallengeAlerts(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SettingsToggleRow(
                      icon: Icons.lightbulb_outline_rounded,
                      label: 'Hint reminders',
                      subtitle: 'When your free hint is ready again',
                      value: _hints,
                      enabled: _permitted,
                      onChanged: (v) {
                        setState(() => _hints = v);
                        NotificationService.setHintReminders(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SettingsToggleRow(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Streak reminders',
                      subtitle: 'Before a challenge expires',
                      value: _streaks,
                      enabled: _permitted,
                      onChanged: (v) {
                        setState(() => _streaks = v);
                        NotificationService.setStreakReminders(v);
                      },
                    ),
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

/// Shown when the OS is not letting anything through. Says where to fix it and
/// offers to go there, rather than leaving the player to find it.
class _BlockedNote extends StatelessWidget {
  const _BlockedNote({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      onTap: onOpen,
      child: Row(
        children: [
          const Icon(Icons.notifications_off_rounded,
              color: AppColors.ink, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Notifications are off',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Enable notifications in your device settings',
                  style: TextStyle(
                    color: AppColors.text.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.open_in_new_rounded,
              color: AppColors.ink, size: 20),
        ],
      ),
    );
  }
}
