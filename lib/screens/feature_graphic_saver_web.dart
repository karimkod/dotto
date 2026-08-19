// On web: hand the PNG to the browser two ways.
//
// 1. A normal download, which is what a person running this wants.
// 2. `window.dottoFeatureGraphic` — the same bytes, base64'd, with a
//    `dottoFeatureGraphicReady` flag beside it. A download lands wherever the
//    browser decides and cannot be read back from the page, so a tool driving
//    this build headlessly needs a handle it can actually reach. This is it.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> saveFeatureGraphic(Uint8List png, String name) async {
  final b64 = base64Encode(png);
  web.window
    ..setProperty('dottoFeatureGraphic'.toJS, b64.toJS)
    ..setProperty('dottoFeatureGraphicName'.toJS, name.toJS)
    ..setProperty('dottoFeatureGraphicReady'.toJS, true.toJS);

  final blob = web.Blob(
    [png.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  anchor.click();
  web.URL.revokeObjectURL(url);

  return 'download: $name (${png.length} bytes) · window.dottoFeatureGraphic';
}
