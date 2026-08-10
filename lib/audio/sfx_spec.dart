// The sound design, as data — plus a renderer that turns it into WAV bytes.
//
// The web build synthesizes its effects live through Web Audio (see
// sfx_web.dart). Platforms with no Web Audio can't do that, so the same tones
// and noise bursts are rendered offline into assets/sfx/*.wav by
// `flutter test tool/make_sfx_test.dart` and played back from the bundle.
//
// The layer values below mirror sfx_web.dart one for one; that file remains the
// live implementation for web, and this one is what every other platform hears.
// Change a frequency in one and you must change it in the other, or the game
// starts sounding like two different games. Nothing at runtime imports this
// library — it exists for the generator — so it is tree-shaken out of the app.

import 'dart:math' as math;
import 'dart:typed_data';

/// Web Audio's ramps are exponential and never reach zero, so silence is
/// approached rather than hit. Matching its floor keeps the envelopes identical.
const _floor = 0.0001;

const _sampleRate = 44100;

enum SfxKind { tone, noise }

enum SfxWave { sine, square }

/// One voice within an effect. Effects are just a handful of these summed.
class SfxLayer {
  const SfxLayer.tone(
    this.freq, {
    required this.dur,
    this.gain = 0.16,
    this.wave = SfxWave.sine,
    this.freqEnd,
    this.delay = 0,
    this.attack = 0.012,
  })  : kind = SfxKind.tone,
        cutoff = null,
        decay = false;

  /// A "thock": same as a tone but with a near-instant attack, which is what
  /// makes it read as a percussive hit rather than a note.
  const SfxLayer.thock(
    this.freq, {
    required this.dur,
    this.gain = 0.3,
  })  : kind = SfxKind.tone,
        wave = SfxWave.sine,
        freqEnd = null,
        delay = 0,
        attack = 0.003,
        cutoff = null,
        decay = false;

  const SfxLayer.noise({
    required this.dur,
    this.gain = 0.16,
    this.cutoff,
    this.decay = false,
    this.delay = 0,
  })  : kind = SfxKind.noise,
        freq = 0,
        wave = SfxWave.sine,
        freqEnd = null,
        attack = 0;

  final SfxKind kind;
  final double freq;
  final double dur;
  final double gain;
  final SfxWave wave;

  /// When set, the pitch sweeps [freq] → [freqEnd] across [dur].
  final double? freqEnd;
  final double delay;
  final double attack;

  /// Low-pass corner, for noise layers only.
  final double? cutoff;

  /// Whether the noise fades linearly across the buffer before the gain
  /// envelope is applied (a burst rather than a steady hiss).
  final bool decay;
}

/// Every effect the game can play, keyed by the asset basename.
const Map<String, List<SfxLayer>> kSfxSpecs = {
  // Deep, chunky placement hit, with a low body partial under it.
  'place': [
    SfxLayer.thock(400, dur: 0.12, gain: 0.34),
    SfxLayer.thock(180, dur: 0.10, gain: 0.20),
  ],
  'remove': [
    SfxLayer.noise(dur: 0.10, gain: 0.14, cutoff: 1200, decay: true),
  ],
  'tick': [
    SfxLayer.tone(1000, dur: 0.03, gain: 0.05),
  ],
  'arrow': [
    SfxLayer.tone(880, dur: 0.06, gain: 0.16),
    SfxLayer.tone(1200, dur: 0.09, gain: 0.16, delay: 0.05),
  ],
  'pause': [
    SfxLayer.tone(200, dur: 0.20, gain: 0.16),
  ],
  'teleport': [
    SfxLayer.tone(400, dur: 0.15, gain: 0.15, freqEnd: 1600),
  ],
  'die': [
    SfxLayer.noise(dur: 0.20, gain: 0.22, cutoff: 900, decay: true),
  ],
  // Explosion: a punchy low-passed blast, a sub body that drops in pitch, and
  // a short square crack for the transient.
  'boom': [
    SfxLayer.noise(dur: 0.40, gain: 0.38, cutoff: 800, decay: true),
    SfxLayer.tone(150, dur: 0.36, gain: 0.34, freqEnd: 40),
    SfxLayer.tone(220,
        dur: 0.10, gain: 0.20, wave: SfxWave.square, freqEnd: 70),
  ],
  // Shield pickup: a soft rising shimmer.
  'shield': [
    SfxLayer.tone(620, dur: 0.16, gain: 0.13, freqEnd: 1180),
    SfxLayer.tone(940, dur: 0.12, gain: 0.10, delay: 0.06),
  ],
  // C5–E5–G5, arpeggiated.
  'exit': [
    SfxLayer.tone(523.25, dur: 0.10, gain: 0.18),
    SfxLayer.tone(659.25, dur: 0.10, gain: 0.18, delay: 0.10),
    SfxLayer.tone(783.99, dur: 0.13, gain: 0.18, delay: 0.20),
  ],
  // The same chord, struck all at once.
  'level_complete': [
    SfxLayer.tone(523.25, dur: 0.50, gain: 0.12),
    SfxLayer.tone(659.25, dur: 0.50, gain: 0.12),
    SfxLayer.tone(783.99, dur: 0.50, gain: 0.12),
    SfxLayer.tone(1046.50, dur: 0.50, gain: 0.12),
  ],
  'click': [
    SfxLayer.noise(dur: 0.05, gain: 0.12, cutoff: 2200),
  ],
  'tap': [
    SfxLayer.thock(600, dur: 0.05, gain: 0.16),
  ],
};

/// Web Audio's `exponentialRampToValueAtTime`: geometric interpolation from
/// [from] to [to] over [0, 1] of the ramp.
double _expRamp(double from, double to, double t) =>
    from * math.pow(to / from, t.clamp(0.0, 1.0));

/// Renders one effect to mono 16-bit PCM WAV bytes.
///
/// [seed] fixes the noise so a regenerated asset is byte-identical to the last
/// one — otherwise every run would produce a fresh diff.
Uint8List renderWav(List<SfxLayer> layers, {int seed = 7}) {
  var span = 0.0;
  for (final l in layers) {
    span = math.max(span, l.delay + l.dur);
  }
  // A short tail so the last sample isn't a hard cut into the file's end.
  final total = ((span + 0.03) * _sampleRate).ceil();
  final mix = Float64List(total);
  final rng = math.Random(seed);

  for (final l in layers) {
    final start = (l.delay * _sampleRate).round();
    final len = (l.dur * _sampleRate).round();
    if (len <= 0) continue;

    switch (l.kind) {
      case SfxKind.tone:
        // Phase is integrated rather than computed from t, so a pitch sweep
        // stays continuous instead of stepping.
        var phase = 0.0;
        for (var i = 0; i < len; i++) {
          final t = i / _sampleRate;
          final frac = i / len;
          final f = l.freqEnd == null
              ? l.freq
              : _expRamp(l.freq, l.freqEnd!, frac);
          phase += 2 * math.pi * f / _sampleRate;

          final double env;
          if (l.attack > 0 && t < l.attack) {
            env = _expRamp(_floor, l.gain, t / l.attack);
          } else if (l.dur > l.attack) {
            env = _expRamp(
                l.gain, _floor, (t - l.attack) / (l.dur - l.attack));
          } else {
            env = l.gain;
          }

          final s = l.wave == SfxWave.square
              ? (math.sin(phase) >= 0 ? 1.0 : -1.0)
              : math.sin(phase);
          final at = start + i;
          if (at < total) mix[at] += s * env;
        }

      case SfxKind.noise:
        // One-pole low-pass. Web Audio's biquad rolls off twice as steeply,
        // but on a burst this short the difference is inaudible.
        final alpha = l.cutoff == null
            ? 1.0
            : (1 / _sampleRate) /
                (1 / (2 * math.pi * l.cutoff!) + 1 / _sampleRate);
        var filtered = 0.0;
        for (var i = 0; i < len; i++) {
          final t = i / _sampleRate;
          final shaped =
              (rng.nextDouble() * 2 - 1) * (l.decay ? (1 - i / len) : 1.0);
          filtered += alpha * (shaped - filtered);
          final env = _expRamp(l.gain, _floor, t / l.dur);
          final at = start + i;
          if (at < total) mix[at] += filtered * env;
        }
    }
  }

  final pcm = Int16List(total);
  for (var i = 0; i < total; i++) {
    pcm[i] = (mix[i].clamp(-1.0, 1.0) * 32767).round();
  }
  return _wav(pcm);
}

/// Wraps PCM samples in a canonical 44-byte RIFF/WAVE header.
Uint8List _wav(Int16List pcm) {
  const channels = 1;
  const bits = 16;
  final dataBytes = pcm.length * 2;
  final out = BytesBuilder();
  final header = ByteData(44);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // format: PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * channels * bits ~/ 8, Endian.little);
  header.setUint16(32, channels * bits ~/ 8, Endian.little); // block align
  header.setUint16(34, bits, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);

  out.add(header.buffer.asUint8List());
  out.add(Uint8List.view(pcm.buffer, 0, dataBytes));
  return out.toBytes();
}
