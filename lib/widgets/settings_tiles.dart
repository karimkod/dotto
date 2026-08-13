// The settings visual language, in one place.
//
// Cream card, thick ink outline, the same pressable feel as everything else in
// the game rather than a Material ListTile. Extracted from settings_screen when
// the notifications sub-screen needed the identical rows: two copies of this
// would drift, and a settings page that looks subtly unlike the one it was
// opened from reads as a different app.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bouncy_button.dart';

/// A settings row with a switch.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional second line, for a row that needs a word of explanation.
  final String? subtitle;

  /// A row that is shown but cannot be changed — the preference is still real,
  /// it just cannot take effect yet. Dimmed rather than hidden, so turning the
  /// blocker off does not make a row appear from nowhere.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SettingsTile(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Row(
          children: [
            Icon(icon, color: AppColors.ink, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppColors.text.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: AppColors.card,
              activeTrackColor: AppColors.accent,
              inactiveThumbColor: AppColors.card,
              inactiveTrackColor: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

/// A settings row that opens something.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const colour = AppColors.ink;
    return SettingsTile(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: colour, size: 22),
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
          const Icon(Icons.chevron_right_rounded, color: colour, size: 22),
        ],
      ),
    );
  }
}

/// The shared card behind both rows.
class SettingsTile extends StatelessWidget {
  const SettingsTile({super.key, required this.child, required this.onTap});

  final Widget child;

  /// Null for a row that is currently inert.
  final VoidCallback? onTap;

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

/// The circular back button, matching the menu's side icons.
class SettingsRoundIcon extends StatelessWidget {
  const SettingsRoundIcon({
    super.key,
    required this.icon,
    required this.onTap,
  });

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

/// A settings screen's header: back button and a centred title.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SettingsRoundIcon(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(child: Center(child: Text(title, style: AppTheme.title))),
        // Balances the back button so the title stays centred.
        const SizedBox(width: 46),
      ],
    );
  }
}
