import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../tool/photo_pixel_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'raw decoder pixels survive full-size PNG roundtrips without resizing',
    () async {
      final source = img.Image(width: 129, height: 97);
      for (final p in source) {
        p
          ..r = p.x * 255 ~/ 128
          ..g = p.y * 255 ~/ 96
          ..b = 75;
      }
      final report = await compareJpegPixels(
        img.encodeJpg(source, quality: 90),
      );
      for (final key in [
        'dart_raw_vs_png_dart_roundtrip',
        'dart_raw_vs_png_flutter_roundtrip',
        'dart_streaming_vs_nonstreaming',
      ]) {
        expect((report[key] as Map)['rgba_exact'], isTrue, reason: key);
      }
      expect(
        (report['flutter_vs_dart_decoded'] as Map)['rgb_mae'],
        lessThan(3),
      );
      expect(((report['jpeg'] as Map)['frames'] as List).length, 1);
    },
  );
  test('header parser rejects malformed data with bounded checks', () {
    for (final data in [
      <int>[],
      [255, 216, 255, 192, 0, 1],
      [255, 216, 255, 218, 0, 2],
    ]) {
      expect(
        () => jpegHeaderSummary(Uint8List.fromList(data)),
        throwsFormatException,
      );
    }
  });
}
