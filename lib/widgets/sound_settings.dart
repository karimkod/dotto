// Sound, music and haptics: the switches a player reaches for mid-level.
//
// They lived only on the settings screen, which is a menu away, and the moment
// someone wants the game quiet is usually the moment it is making noise. So the
// same switches also open in a sheet over the board, from the gear in a level's
// header.
//
// One widget behind both places, so they cannot disagree about what a switch
// does — the Music switch fades the track on the spot, the Haptics switch buzzes
// as it comes on — and both read the live setting each time they are shown.

import 'package:flutter/material.dart';

import '../analytics/analytics_service.dart';
import '../services/music_service.dart';
import '../settings/haptics.dart';
import '../settings/settings_store.dart';
import '../theme/app_theme.dart';
import 'settings_tiles.dart';

/// The Sound, Music and Haptics rows, each wired to the setting it changes.
class SoundAndHapticsToggles extends StatefulWidget {
  const SoundAndHapticsToggles({super.key});

  @override
  State<SoundAndHapticsToggles> createState() =>
      _SoundAndHapticsTogglesState();
}

class _SoundAndHapticsTogglesState extends State<SoundAndHapticsToggles> {
  late bool _sound = SettingsStore.soundOn;
  late bool _music = MusicService.isEnabled;
  late bool _haptics = SettingsStore.hapticsOn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            // Fades out or back in on the spot. Independent of Sound on
            // purpose: a player who wants the game's feedback but not a
            // backing track — or the other way round — has asked for two
            // different things.
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
      ],
    );
  }
}

/// The switches in a sheet over whatever is on screen — a level, mostly.
///
/// A sheet rather than the settings screen, for two reasons. It keeps the board
/// in view. And it leaves the level running: under a full-screen page the
/// board's animations stop while the run's clock keeps going, whereas under a
/// sheet a run in progress simply carries on.
Future<void> showSoundSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Sized to its content rather than capped at 9/16 of the screen, which on
    // a short phone is less than three rows and a title.
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    // A phone's width at most: on a tablet or a desktop browser a full-width
    // sheet strings three switches out across the whole window.
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: AppColors.ink, width: 3),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The grab handle: the sheet goes back down the way it came.
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Settings',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 16),
            const SoundAndHapticsToggles(),
          ],
        ),
      ),
    ),
  );
}
