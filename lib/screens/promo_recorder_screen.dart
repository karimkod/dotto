// Renders the promo to a numbered PNG sequence, one file per video frame.
//
// The timeline is already a pure function of time, so recording is not a
// capture at all — it is an evaluation. The screen walks `frozenAt` from 0 to
// the end in exact 1/fps steps and writes what each one draws. Nothing depends
// on how fast this machine happens to render, so the output is identical every
// run and cannot judder.
//
// Deliberately NOT a screen recording of the playing promo: that samples a
// wall clock from another wall clock, and the two never agree.
//
// Run:  flutter run -t lib/main_promo_record.dart -d windows
// Then: ffmpeg -framerate 30 -i frame_%05d.png -c:v libx264 -pix_fmt yuv420p out.mp4

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import 'promo_store_badges.dart';
import 'promo_video_screen.dart';

/// Frames per second of the exported sequence.
const int kFps = 30;

/// Where an Android host writes: the app's own external files directory, which
/// needs no permission and which `adb pull` can reach.
const String _kAndroidFiles =
    '/storage/emulated/0/Android/data/com.karimkod.dotto/files';

class PromoRecorderScreen extends StatefulWidget {
  const PromoRecorderScreen({super.key, required this.outDir});

  /// Where the PNG sequence lands on a desktop host. On Android the app cannot
  /// write to an arbitrary path, so the external files directory is used and
  /// this is ignored — pull it off with `adb pull` afterwards.
  final String outDir;

  @override
  State<PromoRecorderScreen> createState() => _PromoRecorderScreenState();
}

class _PromoRecorderScreenState extends State<PromoRecorderScreen> {
  final GlobalKey _boundary = GlobalKey();

  /// Resolved once, at the start of the run.
  late final String _dir;

  /// The frame currently being drawn. Rendering and capturing are one frame
  /// apart on purpose: the widget has to be laid out and painted before the
  /// boundary has anything to hand over.
  int _frame = 0;
  late final int _total = (kPromoLength * kFps).ceil();

  String _status = 'starting';
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // The app's own external files directory, spelled out rather than fetched
    // through path_provider — this is a build tool, and it should not add a
    // dependency to the shipped app's pubspec to write some PNGs.
    _dir = Platform.isAndroid ? '$_kAndroidFiles/promo_frames' : widget.outDir;
    Directory(_dir).createSync(recursive: true);
    debugPrint('PROMO_REC_DIR $_dir');
    // The wordmark and the body face are fetched at runtime; capture before
    // they land and the first second of the video is set in a fallback font.
    await GoogleFonts.pendingFonts();
    // Same problem, different asset: an undecoded image paints nothing, and
    // decoding is asynchronous, so the end card's badges have to be resident
    // before the first frame is written or they pop in mid-shot.
    if (mounted) {
      await precacheImage(kPlayBadge, context);
      if (mounted) await precacheImage(kAppStoreBadge, context);
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) _capture();
  }

  /// Writes the frame that is currently on screen, then asks for the next one.
  Future<void> _capture() async {
    if (_busy || _done || !mounted) return;
    _busy = true;
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // pixelRatio 1 against the promo's own logical size, so the PNG is
      // exactly kPromoSize and ffmpeg gets no surprises.
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final name = 'frame_${_frame.toString().padLeft(5, '0')}.png';
      File('$_dir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());

      if (_frame % 30 == 0 || _frame == _total - 1) {
        debugPrint('PROMO_REC $_frame/$_total');
      }

      if (_frame >= _total - 1) {
        _done = true;
        debugPrint('PROMO_REC_DONE $_total frames -> $_dir');
        if (mounted) setState(() => _status = 'done: $_total frames');
        return;
      }
      if (!mounted) return;
      setState(() {
        _frame++;
        _status = 'frame $_frame / $_total';
      });
      // Capture again once THIS setState has been painted.
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    } catch (e, st) {
      debugPrint('PROMO_REC_FAIL $e\n$st');
      if (mounted) setState(() => _status = 'failed: $e');
      _done = true;
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _frame / kFps;
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Column(
        children: [
          Expanded(
            child: Center(
              // Scaled down to fit this window, but the boundary inside keeps
              // its true logical size — which is what gets written out.
              child: FittedBox(
                child: RepaintBoundary(
                  key: _boundary,
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.noScaling),
                    child: SizedBox(
                      width: kPromoSize.width,
                      height: kPromoSize.height,
                      child: PromoVideoScreen(frozenAt: t),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
