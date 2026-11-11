import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

import '../tool/photo_pixel_diagnostics.dart';

// Only this generated fixture has no arbitrary binary metadata. Do not run this
// mutation helper against user photos. Extra 0x55 bytes reproduce the camera's
// entropy-to-RST padding in memory without making a second image file.
Uint8List paddedSyntheticRestart(Uint8List clean) {
  final result = BytesBuilder();
  for (var i = 0; i < clean.length; i++) {
    if (clean[i] == 255 &&
        i + 1 < clean.length &&
        clean[i + 1] >= 208 &&
        clean[i + 1] <= 215) {
      result.add(List.filled(9, 0x55));
    }
    result.addByte(clean[i]);
  }
  return result.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic restart padding reproduces Dart pixel damage; narrow compatibility route recovers it', () async {
    final clean = File('test/fixtures/synthetic_restart_422.jpg')
        .readAsBytesSync();
    final padded = paddedSyntheticRestart(clean);
    final reference = await flutterPixels(clean);
    final nativePadded = await flutterPixels(padded);
    expect(pixelDifference(reference, nativePadded)['rgba_exact'], isTrue);
    final broken = dartPixels(img.decodeJpg(padded)!);
    expect(pixelDifference(reference, broken)['rgb_mae'], greaterThan(10));
    expect(hasJpegRestartInterval(padded), isTrue);
    final photo = await prepareGarmentPhoto(('synthetic.jpg', padded));
    expect((photo.width, photo.height), (reference.width, reference.height));
    expect(photo.bytes.length, lessThanOrEqualTo(2097152));
    expect(
      pixelDifference(reference, await flutterPixels(photo.bytes))['rgb_mae'],
      lessThan(4),
    );
  });
  for (final ext in ['jpg', 'png', 'webp']) {
    test(
      'ordinary $ext retains byte-identical existing normalization',
      () async {
        final source = img.Image(width: 63, height: 41);
        for (final p in source) {
          p
            ..r = p.x * 4
            ..g = p.y * 5
            ..b = 80;
        }
        final bytes = switch (ext) {
          'jpg' => img.encodeJpg(source),
          'png' => img.encodePng(source),
          _ => img.encodeWebP(source),
        };
        expect(hasJpegRestartInterval(bytes), isFalse);
        final old = normalizeGarmentPhoto(('source.$ext', bytes));
        final current = await prepareGarmentPhoto(('source.$ext', bytes));
        expect(current.bytes, old.bytes);
      },
    );
  }
  test('restart compatibility bakes native EXIF orientation exactly once', () async {
    final clean = File('test/fixtures/synthetic_restart_422.jpg').readAsBytesSync();
    for (final orientation in [2,3,5,6,8]) {
      final exif = img.ExifData()..imageIfd.orientation = orientation;
      final encoded = img.injectJpgExif(clean,exif)!;
      final reference = await flutterPixels(encoded);
      final result = await prepareGarmentPhoto(('rotated.jpg',encoded));
      expect((result.width,result.height),(reference.width,reference.height));
      expect(pixelDifference(reference,await flutterPixels(result.bytes))['rgb_mae'],lessThan(4));
    }
  });
  test('compatibility route still enforces original extension and resolution validation', () async {
    final jpeg = File('test/fixtures/synthetic_restart_422.jpg')
        .readAsBytesSync();
    await expectLater(
      prepareGarmentPhoto(('not-a-png.png', jpeg)),
      throwsA(isA<WardrobeException>()),
    );
    final huge = Uint8List.fromList(jpeg);
    final sof = jpegHeaderSummary(huge)['frames'] as List;
    expect(sof.length, 1);
    // Change this synthetic header only; no full-resolution allocation allowed.
    final offset = _sof(huge);
    huge[offset + 5] = 0x7f;
    huge[offset + 6] = 0xff;
    huge[offset + 7] = 0x7f;
    huge[offset + 8] = 0xff;
    await expectLater(
      prepareGarmentPhoto(('huge.jpg', huge)),
      throwsA(isA<WardrobeException>()),
    );
  });
}

int _sof(Uint8List data) {
  for (var i = 0; i < data.length - 1; i++) {
    if (data[i] == 255 && data[i + 1] == 192) return i;
  }
  throw StateError('Synthetic SOF missing');
}
