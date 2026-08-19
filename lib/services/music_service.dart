// Background music: the promo track, looping quietly under the whole game.
//
// The asset is assets/audio/background_music.mp3, cut from the 34-second promo
// render (promo/dotto_promo_music.wav, itself synthesised by
// scripts/make_promo_music.dart). The cut is not arbitrary — it is what makes
// the loop hold up. The track runs at 84 BPM, so a bar is 2.857s and the chord
// progression is four bars long; a loop that is not a whole number of chord
// cycles lands back on the wrong harmony every time round. So the asset is
// bars 1-9: eight bars, two full cycles, starting after the render's 1.4s
// fade-in and ending well before its 2.0s fade-out. The last half second is a
// crossfade wrapping the natural continuation of bar 9 over the start of bar 1,
// which is what removes the seam — a marimba still ringing at the loop point
// carries across it instead of being cut off.
//
// MP3 rather than OGG, which is the smaller file: Apple's media stack cannot
// decode Ogg Vorbis, so an .ogg here would be silence on every iPhone and in
// Safari. MP3 plays on Android, iOS and every browser. It costs a few tens of
// milliseconds of encoder padding at the loop point, which on a pad-led track
// at a third of full volume is not something a player can hear.
//
// Everything below is fire-and-forget, for the same reason the sound effects
// are: music is decoration, and a device that will not play it should cost the
// player nothing.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MusicService {
  MusicService._();

  static const _enabledKey = 'music_enabled';

  /// Relative to assets/, which is where [AssetSource] starts looking.
  static const _asset = 'audio/background_music.mp3';

  /// Background music, and background is the word: loud enough to be felt
  /// under the sound effects, never loud enough to compete with them.
  static const double defaultVolume = 0.3;

  /// Long enough that starting and stopping reads as the music arriving and
  /// leaving rather than being switched.
  static const Duration _fadeDuration = Duration(milliseconds: 700);
  static const Duration _fadeStep = Duration(milliseconds: 35);

  /// `flutter test` has no plugin host, so every call would throw
  /// MissingPluginException. The widget tests pump the menu and the game
  /// screen, both of which ask for music, so the subsystem stands down under
  /// test exactly as the sound effects do — the preference still changes, it
  /// just drives nothing.
  static final bool _muted = Platform.environment.containsKey('FLUTTER_TEST');

  static SharedPreferences? _prefs;
  static bool _enabled = true;
  static double _ceiling = defaultVolume;

  /// Whether a screen has asked for music. Separate from [_enabled] because
  /// they answer different questions: this one is "should there be music
  /// here", the preference is "does the player want music at all". Turning the
  /// setting off and on again has to bring the music back, which it can only
  /// do if the screen's request survived being switched off.
  static bool _wanted = false;

  /// Whether the app is in the background. Also true while a full-screen ad is
  /// up, since those arrive as a lifecycle pause.
  static bool _backgrounded = false;

  static AudioPlayer? _player;
  static Future<void>? _loading;

  static Timer? _fadeTimer;
  static Completer<void>? _fading;

  /// The volume actually applied to the player, which a fade moves between 0
  /// and [_ceiling]. Kept here so a fade interrupted halfway can be picked up
  /// from where it was rather than jumping.
  static double _level = 0;

  /// Whether the player wants music. Defaults to on, like sound and haptics.
  static bool get isEnabled => _enabled;

  /// The ceiling a fade-in climbs to.
  static double get volume => _ceiling;

  /// Load the preference and start decoding the track. Call once before
  /// `runApp`; the splash covers the decode, so the menu's first [play] has
  /// nothing left to wait for.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      // No storage available. On by default, and the choice will not outlive
      // the session.
    }
    if (_muted || !_enabled) return;
    unawaited(_ready());
  }

  /// Ask for music. Idempotent, so every screen that wants it can simply say
  /// so without checking whether it is already playing.
  static void play() {
    _wanted = true;
    _sync();
  }

  /// Hold playback but keep the request, so [resume] can bring it back.
  static void pause() {
    _backgrounded = true;
    _sync();
  }

  static void resume() {
    _backgrounded = false;
    _sync();
  }

  /// Withdraw the request entirely. The next [play] starts the track over.
  static void stop() {
    _wanted = false;
    _sync(rewind: true);
  }

  /// Change the ceiling. Takes effect immediately if music is playing.
  static void setVolume(double volume) {
    _ceiling = volume.clamp(0.0, 1.0);
    if (_muted || !_audible) return;
    unawaited(_fadeTo(_ceiling));
  }

  /// Record the player's choice and act on it at once — a setting that needs
  /// a screen change to take effect reads as broken.
  static void setEnabled(bool on) {
    if (_enabled == on) return;
    _enabled = on;
    final prefs = _prefs;
    if (prefs != null) {
      // Fire and forget: the setting already took effect, so a failed write
      // costs the next launch rather than this tap.
      unawaited(prefs.setBool(_enabledKey, on).catchError((_) => false));
    }
    // Rewound when switched off, so switching it back on opens on the phrase
    // the track starts with rather than halfway through a bar.
    _sync(rewind: !on);
  }

  /// Whether music should be sounding right now.
  static bool get _audible => _wanted && _enabled && !_backgrounded;

  /// Brings the player in line with [_audible].
  static void _sync({bool rewind = false}) {
    if (_muted) return;
    unawaited(_audible ? _begin() : _quieten(rewind: rewind));
  }

  static Future<void> _begin() async {
    final player = await _ready();
    // The state can flip while the asset is decoding — a player who opens the
    // menu and immediately backgrounds the app gets here with nothing left to
    // do.
    if (player == null || !_audible) return;
    try {
      await player.setVolume(_level);
      await player.resume();
    } catch (_) {
      return;
    }
    await _fadeTo(_ceiling);
  }

  static Future<void> _quieten({required bool rewind}) async {
    final player = _player;
    if (player == null) return;
    await _fadeTo(0);
    // Another call may have asked for music back while the fade ran.
    if (_audible) return;
    try {
      // Paused rather than stopped: the source stays decoded, so coming back
      // from the background is a resume rather than another load.
      await player.pause();
      if (rewind) await player.seek(Duration.zero);
    } catch (_) {
      // Nothing to recover — the music is already inaudible.
    }
  }

  /// The player, once its source is loaded, or null if it cannot be.
  static Future<AudioPlayer?> _ready() async {
    if (_player != null) return _player;
    final inFlight = _loading;
    if (inFlight != null) {
      await inFlight;
      return _player;
    }
    await (_loading = _load());
    return _player;
  }

  static Future<void> _load() async {
    try {
      // The plugin's default audio context, deliberately: this is the one
      // player in the app that asks Android for audio focus, so it is the one
      // that yields to a phone call. The sound effects opt out of focus
      // entirely — see lib/audio/sfx_io.dart for why sharing it does not work.
      final player = AudioPlayer(playerId: 'music');
      // Native looping, so the seam is not at the mercy of a Dart timer.
      await player.setReleaseMode(ReleaseMode.loop);
      // Silent until a fade brings it up; otherwise the first frame of the
      // track lands at full volume before the fade's first step runs.
      await player.setVolume(0);
      await player.setSource(AssetSource(_asset));
      _player = player;
    } catch (_) {
      // _loading stays set, so a device that cannot decode this is asked once
      // and never again.
    }
  }

  /// Slides the volume to [goal], completing when it lands — or as soon as
  /// another fade takes over, so a caller waiting on this is never stranded.
  static Future<void> _fadeTo(double goal) {
    _cancelFade();
    final player = _player;
    if (player == null || (goal - _level).abs() < 0.005) {
      _level = goal;
      return Future.value();
    }
    final from = _level;
    final delta = goal - from;
    final steps =
        (_fadeDuration.inMilliseconds / _fadeStep.inMilliseconds).round();
    final done = _fading = Completer<void>();
    var step = 0;
    _fadeTimer = Timer.periodic(_fadeStep, (timer) {
      step++;
      final t = (step / steps).clamp(0.0, 1.0);
      _level = from + delta * t;
      unawaited(player.setVolume(_level).catchError((_) {}));
      if (t < 1) return;
      timer.cancel();
      _fadeTimer = null;
      _fading = null;
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  static void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final pending = _fading;
    _fading = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}
