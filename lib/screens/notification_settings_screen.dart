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

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

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

  Future<void> _openSystemSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      // Nothing to open on this platform. The row above still explains what is
      // wrong, which is the part that matters.
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
