// The ask before the ask.
//
// The system permission dialog can be shown once. If it is refused, the only
// way back is the OS settings app, which almost nobody visits — so the real
// decision is made here, where a refusal costs nothing and the question can be
// put in terms of what the player gets.
//
// Shown after a first level is finished rather than at launch: at launch the
// player has no idea what Dotto is, and "can we notify you" from a stranger is
// a no. It appears once, ever, whichever way it is answered.

import 'package:flutter/material.dart';

import '../analytics/analytics_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_button.dart';

class NotificationPromptDialog extends StatefulWidget {
  const NotificationPromptDialog({super.key});

  /// Show it, if it should be shown. Returns whether permission was granted.
  ///
  /// The gate lives here rather than at the call site so there is one answer to
  /// "should this appear", and a second call site later cannot get it wrong.
  static Future<bool> maybeShow(BuildContext context) async {
    if (!NotificationService.shouldPrompt) return false;
    // Marked before the dialog rather than after. Anything can interrupt a
    // dialog — a call, a force-quit, the app being backgrounded and killed —
    // and none of it should turn "asked once" into "asked every time".
    NotificationService.markPrompted();
    Analytics.notificationPromptShown();
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotificationPromptDialog(),
    );
    return granted ?? false;
  }

  @override
  State<NotificationPromptDialog> createState() =>
      _NotificationPromptDialogState();
}

class _NotificationPromptDialogState extends State<NotificationPromptDialog> {
  bool _busy = false;

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    final granted = await NotificationService.requestPermission();
    // Reported against what the OS said, not which button was tapped — the
    // system dialog sits behind this one and can still be refused.
    if (granted) {
      Analytics.notificationPromptAccepted();
    } else {
      Analytics.notificationPromptDenied();
    }
    if (!mounted) return;
    Navigator.of(context).pop(granted);
  }

  void _notNow() {
    Analytics.notificationPromptDenied();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ink, width: 3),
              ),
              child: const Icon(Icons.notifications_active_rounded,
                  color: AppColors.accent, size: 38),
            ),
            const SizedBox(height: 20),
            Text('Stay in the loop!',
                style: AppTheme.title, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Get notified when new challenges drop and your hint is ready',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text.withValues(alpha: 0.8),
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            BouncyButton(
              onTap: _busy ? null : _enable,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color:
                      AppColors.accent.withValues(alpha: _busy ? 0.55 : 1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.ink, width: 3),
                ),
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation(AppColors.ink),
                          ),
                        )
                      : const Text(
                          'Enable Notifications',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _busy ? null : _notNow,
              child: Text(
                'Not now',
                style: TextStyle(
                  color: AppColors.text.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
