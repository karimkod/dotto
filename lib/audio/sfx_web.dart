// Lightweight Web Audio sound effects — no audio files, all synthesized.

import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

web.AudioContext? _ctx;

web.AudioContext? _ensure() {
  try {
    final c = _ctx ??= web.AudioContext();
    if (c.state == 'suspended') c.resume();
    return c;
  } catch (_) {
    return null;
  }
}

/// A short oscillator tone, optionally sweeping from [freq] to [freqEnd].
void _tone(
  double freq, {
  required double dur,
  String type = 'sine',
  double gain = 0.16,
  double? freqEnd,
  double delay = 0,
}) {
  final ctx = _ensure();
  if (ctx == null) return;
  try {
    final t0 = ctx.currentTime + delay;
    final osc = ctx.createOscillator();
    final g = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    if (freqEnd != null) {
      osc.frequency.exponentialRampToValueAtTime(freqEnd, t0 + dur);
    }
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(t0);
    osc.stop(t0 + dur + 0.03);
  } catch (_) {}
}

/// A short burst of filtered noise (whoosh / poof / click).
void _noise({
  required double dur,
  double gain = 0.16,
  double? cutoff,
  bool decay = false,
}) {
  final ctx = _ensure();
  if (ctx == null) return;
  try {
    final t0 = ctx.currentTime;
    final len = (ctx.sampleRate * dur).round();
    final buffer = ctx.createBuffer(1, len, ctx.sampleRate);
    final data = Float32List(len);
    final rng = math.Random();
    for (var i = 0; i < len; i++) {
      final env = decay ? (1 - i / len) : 1.0;
      data[i] = (rng.nextDouble() * 2 - 1) * env;
    }
    buffer.copyToChannel(data.toJS, 0);

    final src = ctx.createBufferSource();
    src.buffer = buffer;
    final g = ctx.createGain();
    g.gain.setValueAtTime(gain, t0);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);

    if (cutoff != null) {
      final f = ctx.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.value = cutoff;
      src.connect(f);
      f.connect(g);
    } else {
      src.connect(g);
    }
    g.connect(ctx.destination);
    src.start(t0);
    src.stop(t0 + dur + 0.03);
  } catch (_) {}
}

void playPlace() {
  // Deep, chunky "thock": loud attack, fast decay, with a low body partial.
  _toneThock(400, dur: 0.12, gain: 0.34);
  _toneThock(180, dur: 0.10, gain: 0.20);
}

/// Tone with a sharp attack (~3ms) and fast exponential decay.
void _toneThock(double freq, {required double dur, double gain = 0.3}) {
  final ctx = _ensure();
  if (ctx == null) return;
  try {
    final t0 = ctx.currentTime;
    final osc = ctx.createOscillator();
    final g = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(freq, t0);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.003); // sharp attack
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur); // fast decay
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(t0);
    osc.stop(t0 + dur + 0.02);
  } catch (_) {}
}

void playRemove() => _noise(dur: 0.10, gain: 0.14, cutoff: 1200, decay: true);

void playTick() => _tone(1000, dur: 0.03, gain: 0.05);

void playArrow() {
  _tone(880, dur: 0.06, gain: 0.16);
  _tone(1200, dur: 0.09, gain: 0.16, delay: 0.05);
}

void playPause() => _tone(200, dur: 0.20, gain: 0.16);

void playTeleport() =>
    _tone(400, dur: 0.15, gain: 0.15, freqEnd: 1600);

void playDie() => _noise(dur: 0.20, gain: 0.22, cutoff: 900, decay: true);

void playExit() {
  _tone(523.25, dur: 0.10, gain: 0.18); // C5
  _tone(659.25, dur: 0.10, gain: 0.18, delay: 0.10); // E5
  _tone(783.99, dur: 0.13, gain: 0.18, delay: 0.20); // G5
}

void playLevelComplete() {
  // Major chord (C5–E5–G5–C6).
  for (final f in [523.25, 659.25, 783.99, 1046.50]) {
    _tone(f, dur: 0.50, gain: 0.12);
  }
}

void playClick() => _noise(dur: 0.05, gain: 0.12, cutoff: 2200);
