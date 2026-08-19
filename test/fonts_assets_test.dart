// Fonts are bundled rather than downloaded: main.dart sets
// `GoogleFonts.config.allowRuntimeFetching = false`, and google_fonts then
// resolves a family by scanning the asset manifest for a file whose name ends in
// `<Family>-<Variant>`. Two things follow, and both are why this file exists.
//
// The filenames are load-bearing. `Nunito-SemiBold.ttf` is not a description, it
// is the lookup key, so renaming or dropping one is not a cosmetic regression.
//
// And the failure is loud in the wrong place. google_fonts attaches no error
// handler to the future that loads a font, so when a variant is not in the
// bundle its exception escapes to the runZonedGuarded in main() and is filed as
// a fatal crash, while the text itself paints in the fallback face and looks
// fine. Nothing in a widget test notices. These checks are what stands between
// adding `fontWeight: FontWeight.w300` to a TextStyle and a release that crash
// reports on its first frame.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dotto/theme/app_theme.dart';

/// google_fonts' weight-to-filename mapping, from
/// `GoogleFontsVariant.toApiFilenamePart()`. Duplicated because the package
/// exports only its generated `GoogleFonts` class, not this table.
const _weightPart = <int, String>{
  100: 'Thin',
  200: 'ExtraLight',
  300: 'Light',
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
};

/// The weights Material 3's `englishLike` text theme resolves to: w400 for the
/// display, headline, title-large and body styles, w500 for the rest. AppTheme
/// passes that theme through `GoogleFonts.nunitoTextTheme`, so Nunito has to
/// cover them even though nothing in lib/ names them.
const _themeWeights = {400, 500};

/// Every `.dart` file under lib/, concatenated. Cheap enough to reread per test.
String _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n');

/// `GoogleFonts.poppins(` and `GoogleFonts.nunitoTextTheme(` both name a family;
/// `GoogleFonts.config` is not a call and does not match, and
/// `GoogleFonts.pendingFonts()` names no family either — it awaits whatever
/// the surrounding screen already asked for (the promo tooling calls it, and
/// so does this file).
Set<String> _familiesUsed(String src) => RegExp(r'GoogleFonts\.([a-z][A-Za-z0-9]*)\(')
    .allMatches(src)
    .map((m) => m.group(1)!)
    .where((name) => name != 'pendingFonts')
    .map((name) {
      final base =
          name.endsWith('TextTheme') ? name.substring(0, name.length - 9) : name;
      return base[0].toUpperCase() + base.substring(1);
    })
    .toSet();

void main() {
  test('every weight lib/ asks for has a bundled Nunito file', () {
    // Deliberately over-approximate: a few of these weights are only ever used
    // with Poppins, and requiring the Nunito cut as well costs ~125 KB apiece
    // and removes the need to work out which family each call site styles. If
    // that ever gets expensive, narrow it, but do not narrow it by guessing.
    final asked = RegExp(r'FontWeight\.w([1-9]00)\b')
        .allMatches(_libSources())
        .map((m) => int.parse(m.group(1)!))
        .toSet()
      ..addAll(_themeWeights);

    expect(asked, containsAll(_themeWeights),
        reason: 'the theme weights are unconditional');

    for (final weight in asked) {
      final part = _weightPart[weight];
      expect(part, isNotNull, reason: 'w$weight is not a Google Fonts variant');
      expect(File('assets/fonts/Nunito-$part.ttf').existsSync(), isTrue,
          reason: 'lib/ styles text at w$weight, so google_fonts will look for '
              'assets/fonts/Nunito-$part.ttf and throw when it is absent');
    }
  });

  test('the Poppins wordmark ships upright and italic', () {
    // AppTheme.title is italic w800 and the game screen reuses w800 upright.
    // Both are the same family, and a missing italic does not fall back to the
    // upright cut: it throws like any other absent variant.
    for (final name in const ['Poppins-ExtraBold', 'Poppins-ExtraBoldItalic']) {
      expect(File('assets/fonts/$name.ttf').existsSync(), isTrue,
          reason: '$name.ttf is missing');
    }
  });

  test('lib/ asks for no family beyond the two that are bundled', () {
    // Guards drift the other way: `GoogleFonts.roboto()` compiles, analyses
    // clean, and throws on the frame that first renders it.
    expect(_familiesUsed(_libSources()), {'Nunito', 'Poppins'});
  });

  test('every bundled font is a real TrueType file', () {
    // A truncated download or a stray Git LFS pointer is still a file that
    // exists, and existing is all the checks above ask of it.
    final fonts = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList();
    expect(fonts, hasLength(8), reason: 'six Nunito cuts and two Poppins');

    for (final font in fonts) {
      final bytes = font.readAsBytesSync();
      expect(bytes.length, greaterThan(50000),
          reason: '${font.path} is too small to be a full font');
      // sfnt version 1.0, the header Google Fonts' static TrueType cuts carry.
      expect(bytes.sublist(0, 4), [0x00, 0x01, 0x00, 0x00],
          reason: '${font.path} does not start with a TrueType header');
    }
  });

  test('the OFL text ships beside the fonts it covers', () {
    // main.dart hands these to LicenseRegistry by this exact path, and reads
    // them lazily, so a rename surfaces only when a player opens the licence
    // page. Bundling OFL fonts without the notice is also simply not allowed.
    for (final family in _familiesUsed(_libSources())) {
      final path = 'assets/fonts/OFL-${family.toLowerCase()}.txt';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      expect(file.readAsStringSync(), contains('SIL OPEN FONT LICENSE'),
          reason: '$path does not look like the OFL');
    }
  });

  testWidgets('every style the app renders loads from the bundle', (tester) async {
    // The checks above assert that files exist under the names this file says
    // google_fonts wants. This one asks google_fonts instead: with fetching off
    // its only remaining source is the asset manifest, so awaiting the load
    // futures either resolves from the bundle or throws. It is the difference
    // between testing a transcription of the rule and testing the rule.
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        final body = text.bodyMedium!;
        return Column(children: <Widget>[
          Text('theme 400', style: body),
          Text('theme 500', style: text.labelLarge),
          for (final weight in const [
            FontWeight.w600,
            FontWeight.w700,
            FontWeight.w800,
            FontWeight.w900,
          ])
            Text('nunito $weight', style: body.copyWith(fontWeight: weight)),
          // The wordmark, italic, and the game screen's upright score.
          Text('Dotto', style: AppTheme.title),
          Text('52', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        ]);
      }),
    ));

    await GoogleFonts.pendingFonts();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('fonts are bundled and never fetched', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/fonts/'),
        reason: 'unbundled fonts are invisible to the asset manifest lookup');
    expect(File('lib/main.dart').readAsStringSync(),
        contains('GoogleFonts.config.allowRuntimeFetching = false'),
        reason: 'runtime fetching is what put a font download on the startup '
            'path and reported its failure as a crash');
  });
}
