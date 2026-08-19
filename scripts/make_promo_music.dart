// Writes the promo video's backing track as a WAV.
//
//   dart run scripts/make_promo_music.dart [out.wav]
//
// Synthesised here rather than downloaded so the licence is not a question:
// nothing in this file came from anywhere else, so the track is ours outright
// and no attribution or CC term rides along with the store listing.
//
// The sound is warm and minimal, not retro: a marimba carries the melody over
// a slow synth pad, with a soft piano laying down the chord on the downbeat and
// a felted low pulse keeping time. No square waves, no drum kit. It plays UNDER
// a 30-second promo, so it has to hold a mood without asking to be listened to.
//
// Everything decays. There is no sustained bright content anywhere in the mix,
// which is what keeps it out of the way of the visuals.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int kRate = 44100;

/// Unhurried, but with enough pulse to carry a montage.
const double kBpm = 84;
const double kBeat = 60 / kBpm; // ~0.714s
const double kBar = kBeat * 4; // ~2.857s

/// Long enough to cover the video; ffmpeg trims with -shortest.
const double kSeconds = 34;

double hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

// MIDI numbers, for readability.
const c2 = 36, e2 = 40, f2 = 41, g2 = 43, a2 = 45;
const c3 = 48, d3 = 50, e3 = 52, f3 = 53, g3 = 55, a3 = 57, b3 = 59;
const c4 = 60, d4 = 62, e4 = 64, f4 = 65, g4 = 67, a4 = 69, b4 = 71;
const c5 = 72, d5 = 74, e5 = 76, f5 = 77, g5 = 79, a5 = 81;

late Float64List left;
late Float64List right;

/// Cmaj7 - Em7 - Fmaj7 - G6sus. Open, unresolved, loops without a seam. Each
/// entry is (pad voicing, piano voicing, bass root).
const _chords = <List<List<int>>>[
  [
    [c3, e3, g3, b3], // Cmaj7
    [c4, e4, g4, b4],
    [c2],
  ],
  [
    [e3, g3, b3, d4], // Em7
    [e4, g4, b4, d5],
    [e2],
  ],
  [
    [f3, a3, c4, e4], // Fmaj7
    [f4, a4, c5, e5],
    [f2],
  ],
  [
    [g3, c4, d4, a4], // G6sus, left hanging
    [g4, c5, d5, a5],
    [g2],
  ],
];

void main(List<String> args) {
  final total = (kSeconds * kRate).round();
  left = Float64List(total);
  right = Float64List(total);

  const bars = 12; // 12 * 2.857 = 34.3s

  for (var bar = 0; bar < bars; bar++) {
    final ch = _chords[bar % 4];
    final t0 = bar * kBar;

    // --- pad: the whole bar, slow in, slow out --------------------------
    // Comes up alone under the title card and never leaves.
    final padGain = bar == 0 ? 0.055 : 0.075;
    for (final n in ch[0]) {
      addPad(t0 - 0.25, kBar + 0.5, n, padGain);
    }

    // --- piano: chord on the downbeat, soft and short-pedalled ----------
    if (bar >= 1) {
      for (var i = 0; i < ch[1].length; i++) {
        // A little roll, the way a hand actually lands on a chord.
        addPiano(t0 + i * 0.018, ch[1][i], 0.050);
      }
      // Answer on the "and" of 3, an octave down, quieter.
      addPiano(t0 + kBeat * 2.5, ch[1][0] - 12, 0.030);
    }

    // --- bass: felted low pulse on 1 and 3 ------------------------------
    if (bar >= 1) {
      addSub(t0, ch[2][0], 0.10);
      addSub(t0 + kBeat * 2, ch[2][0], 0.07);
    }
  }

  // --- marimba ---------------------------------------------------------
  // Enters with the first level and carries the tune. Pentatonic, so no
  // interval in it can clash with the pad underneath.
  const melody = <(double, int, double)>[
    // (beat from bar 1, midi, gain)
    (0, g4, 0.13), (1.5, a4, 0.11), (2, c5, 0.13), (3, b4, 0.10),
    (4, g4, 0.12), (5.5, e4, 0.10), (6, g4, 0.12),
    (8, a4, 0.13), (9.5, c5, 0.11), (10, d5, 0.13), (11, c5, 0.10),
    (12, a4, 0.12), (13.5, g4, 0.10), (14, e4, 0.12),
    (16, c5, 0.13), (17.5, d5, 0.11), (18, e5, 0.14), (19, d5, 0.10),
    (20, c5, 0.12), (21.5, a4, 0.10), (22, c5, 0.12),
    (24, d5, 0.13), (25.5, c5, 0.11), (26, a4, 0.13), (27, g4, 0.10),
    (28, e4, 0.12), (29.5, g4, 0.10), (30, a4, 0.12),
    (32, g5, 0.13), (33.5, e5, 0.11), (34, d5, 0.13), (35, c5, 0.11),
    (36, d5, 0.12), (37.5, e5, 0.10), (38, g5, 0.13),
    (40, e5, 0.12), (41.5, d5, 0.10), (42, c5, 0.13), (43, a4, 0.10),
    (44, g4, 0.12),
  ];
  for (final (b, n, g) in melody) {
    addMarimba(kBar + b * kBeat, n, g);
  }

  // Sparse high counter-line, an octave up, from the halfway mark. Adds lift
  // without adding density.
  const counter = <(double, int)>[
    (18.5, g5), (19.5, e5), (26.5, a5), (27.5, g5),
    (34.5, c5 + 12), (35.5, a5), (42.5, g5), (43.5, e5),
  ];
  for (final (b, n) in counter) {
    addMarimba(kBar + b * kBeat, n, 0.055, decay: 0.9);
  }

  // A single soft marimba note right at the top, so the title card does not
  // open in silence.
  addMarimba(0.35, c5, 0.10, decay: 1.6);

  writeWav(args.isEmpty ? 'promo_music.wav' : args.first);
}

/// Marimba: a struck bar. Fundamental plus the two partials that give the
/// instrument its wooden ring (a marimba is tuned so the first overtone sits
/// two octaves above), each decaying faster than the one below it.
void addMarimba(double t0, int midi, double gain, {double decay = 1.15}) {
  final f = hz(midi);
  // Higher bars ring shorter, as real ones do.
  final d = decay * math.pow(2, (60 - midi) / 40).toDouble();
  const partials = [
    (1.0, 1.00, 1.00), // (ratio, amp, decay multiplier)
    (4.0, 0.34, 0.42),
    (10.0, 0.11, 0.22),
  ];
  final start = (t0 * kRate).round();
  final len = ((d * 2.2) * kRate).round();
  final pan = ((midi - 64) / 30).clamp(-1.0, 1.0) * 0.22;

  for (var i = 0; i < len; i++) {
    final idx = start + i;
    if (idx < 0 || idx >= left.length) continue;
    final t = i / kRate;
    // ~3ms strike, so it reads as a mallet and not a click.
    final strike = t < 0.003 ? t / 0.003 : 1.0;
    var s = 0.0;
    for (final (ratio, amp, dm) in partials) {
      s += math.sin(2 * math.pi * f * ratio * t) *
          amp *
          math.exp(-t / (d * dm));
    }
    s *= strike * gain * 0.55;
    _mix(idx, s, pan);
  }
}

/// Pad: four detuned sines per note, slow swell, gentle drift. No harmonics
/// above the fundamental, which is what makes it sit behind everything else.
void addPad(double t0, double dur, int midi, double gain) {
  final f = hz(midi);
  final start = (t0 * kRate).round();
  final len = (dur * kRate).round();
  final attack = dur * 0.35;
  final release = dur * 0.40;
  // Fixed per note so the render is identical every run.
  final rng = math.Random(midi * 7919);
  final detunes = [
    1.0,
    1 + (rng.nextDouble() - 0.5) * 0.004,
    1 + (rng.nextDouble() - 0.5) * 0.006,
    2.0, // a quiet octave for air
  ];
  final amps = [1.0, 0.7, 0.6, 0.18];

  for (var i = 0; i < len; i++) {
    final idx = start + i;
    if (idx < 0 || idx >= left.length) continue;
    final t = i / kRate;
    double env;
    if (t < attack) {
      env = t / attack;
    } else if (t > dur - release) {
      env = (dur - t) / release;
    } else {
      env = 1;
    }
    if (env <= 0) continue;
    // Slow breathing, so a held chord never sounds frozen.
    env *= 0.85 + 0.15 * math.sin(2 * math.pi * 0.11 * (t0 + t));

    var s = 0.0;
    for (var k = 0; k < detunes.length; k++) {
      s += math.sin(2 * math.pi * f * detunes[k] * t) * amps[k];
    }
    _mix(idx, s * env * gain * 0.32, midi.isEven ? 0.18 : -0.18);
  }
}

/// Soft piano: fundamental plus a couple of low partials, medium decay, no
/// hammer noise. Rounded rather than bright.
void addPiano(double t0, int midi, double gain) {
  final f = hz(midi);
  final start = (t0 * kRate).round();
  const d = 1.9;
  final len = (d * 1.8 * kRate).round();
  const partials = [(1.0, 1.0, 1.0), (2.0, 0.30, 0.62), (3.0, 0.11, 0.40)];

  for (var i = 0; i < len; i++) {
    final idx = start + i;
    if (idx < 0 || idx >= left.length) continue;
    final t = i / kRate;
    final attack = t < 0.010 ? t / 0.010 : 1.0;
    var s = 0.0;
    for (final (ratio, amp, dm) in partials) {
      s += math.sin(2 * math.pi * f * ratio * t) * amp * math.exp(-t / (d * dm));
    }
    _mix(idx, s * attack * gain * 0.5, 0);
  }
}

/// The low pulse: a sine with a soft knee, felt more than heard.
void addSub(double t0, int midi, double gain) {
  final f = hz(midi);
  final start = (t0 * kRate).round();
  const d = 0.85;
  final len = (d * 2.5 * kRate).round();
  for (var i = 0; i < len; i++) {
    final idx = start + i;
    if (idx < 0 || idx >= left.length) continue;
    final t = i / kRate;
    final attack = t < 0.020 ? t / 0.020 : 1.0;
    final s = (math.sin(2 * math.pi * f * t) +
            0.22 * math.sin(2 * math.pi * f * 2 * t)) *
        math.exp(-t / d) *
        attack *
        gain;
    _mix(idx, s, 0);
  }
}

void _mix(int idx, double s, double pan) {
  left[idx] += s * (1 - (pan > 0 ? pan : 0));
  right[idx] += s * (1 + (pan < 0 ? pan : 0));
}

// --- output ----------------------------------------------------------------

/// Normalises to a comfortable ceiling, applies a fade at both ends and writes
/// 16-bit stereo PCM.
void writeWav(String path) {
  var peak = 0.0;
  for (var i = 0; i < left.length; i++) {
    peak = math.max(peak, math.max(left[i].abs(), right[i].abs()));
  }
  // Leaves headroom: this is a bed, not the main event.
  final scale = peak == 0 ? 1.0 : 0.62 / peak;

  final fadeIn = (1.4 * kRate).round();
  final fadeOut = (2.0 * kRate).round();
  final n = left.length;
  final bytes = BytesBuilder();

  void u32(int v) =>
      bytes.add([v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255]);
  void u16(int v) => bytes.add([v & 255, v >> 8 & 255]);

  bytes.add('RIFF'.codeUnits);
  u32(36 + n * 4);
  bytes.add('WAVE'.codeUnits);
  bytes.add('fmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(2); // stereo
  u32(kRate);
  u32(kRate * 4);
  u16(4);
  u16(16);
  bytes.add('data'.codeUnits);
  u32(n * 4);

  final pcm = Uint8List(n * 4);
  var p = 0;
  for (var i = 0; i < n; i++) {
    var g = scale;
    if (i < fadeIn) g *= i / fadeIn;
    if (i > n - fadeOut) g *= (n - i) / fadeOut;
    for (final ch in [left[i], right[i]]) {
      final v = (ch * g * 32767).clamp(-32768.0, 32767.0).round();
      pcm[p++] = v & 255;
      pcm[p++] = (v >> 8) & 255;
    }
  }
  bytes.add(pcm);

  File(path).writeAsBytesSync(bytes.toBytes());
  stdout.writeln('MUSIC_OK $path  ${(n / kRate).toStringAsFixed(2)}s '
      'peak=${peak.toStringAsFixed(3)}');
}
