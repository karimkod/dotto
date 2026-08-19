// Off web: write the PNG to disk.
//
// On Android the app's own external files directory comes first, because that
// is the one `adb pull` can reach; the system temp directory is the fallback
// for desktop (and for anywhere the first is not writable).

import 'dart:io';
import 'dart:typed_data';

Future<String> saveFeatureGraphic(Uint8List png, String name) async {
  final candidates = <String>[
    if (Platform.isAndroid)
      '/storage/emulated/0/Android/data/com.karimkod.dotto/files',
    Directory.current.path,
    Directory.systemTemp.path,
  ];
  Object? last;
  for (final dir in candidates) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) d.createSync(recursive: true);
      final f = File('$dir/$name');
      await f.writeAsBytes(png, flush: true);
      return f.path;
    } catch (e) {
      last = e;
    }
  }
  throw StateError('no writable directory ($last)');
}
