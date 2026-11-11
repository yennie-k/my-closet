import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_closet/screens/wardrobe_screen.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

import 'server_wardrobe_test.dart' show tap;
import 'support/wardrobe_fakes.dart';

img.Image chart(
  int w,
  int h, {
  img.Format format = img.Format.uint8,
  bool alpha = false,
}) {
  final image = img.Image(
    width: w,
    height: h,
    format: format,
    numChannels: alpha ? 4 : 3,
  );
  final max = image.maxChannelValue;
  for (final p in image) {
    p.r = (0.1 + 0.8 * p.x / (w > 1 ? w - 1 : 1)) * max;
    p.g = (0.1 + 0.8 * p.y / (h > 1 ? h - 1 : 1)) * max;
    p.b = 0.4 * max;
    if (alpha) p.a = p.x < w ~/ 2 ? 0 : max / 2;
  }
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ext in ['jpg', 'png', 'webp']) {
    test(
      '$ext patterned pixels survive decode/normalization/Flutter preview',
      () async {
        final original = chart(129, 97);
        final bytes = switch (ext) {
          'jpg' => img.encodeJpg(original, quality: 95),
          'png' => img.encodePng(original),
          _ => img.encodeWebP(original),
        };
        final result = normalizeGarmentPhoto(('synthetic.$ext', bytes));
        final output = img.decodeJpg(result.bytes)!;
        for (final y in [10, 40, 80]) {
          for (final x in [10, 60, 110]) {
            final expected = original.getPixel(x, y),
                actual = output.getPixel(x, y);
            expect(actual.r, closeTo(expected.r, 8));
            expect(actual.g, closeTo(expected.g, 8));
            expect(actual.b, closeTo(expected.b, 8));
          }
        }
        await validatePhotoPreview(result);
      },
    );
  }
  for (final size in [(2048, 1536), (17, 1701), (1701, 17), (1, 1701)]) {
    test('aspect ratio and output bounds ${size.$1}x${size.$2}', () {
      final result = normalizeGarmentPhoto((
        's.png',
        img.encodePng(chart(size.$1, size.$2)),
      ));
      expect(result.width, lessThanOrEqualTo(1600));
      expect(result.height, lessThanOrEqualTo(1600));
      expect(result.width * result.height, lessThanOrEqualTo(4000000));
      expect(result.bytes.length, lessThanOrEqualTo(2097152));
      if (size == (2048, 1536)) {
        expect((result.width, result.height), (1600, 1200));
      }
    });
  }
  for (final format in [img.Format.uint8, img.Format.uint16]) {
    test(
      'transparent ${format.name} PNG composites over white without wrapping channels',
      () {
        final result = normalizeGarmentPhoto((
          'alpha.png',
          img.encodePng(chart(64, 48, alpha: true, format: format)),
        ));
        final output = img.decodeJpg(result.bytes)!;
        final white = output.getPixel(8, 20), blend = output.getPixel(56, 20);
        expect(white.r, greaterThan(248));
        expect(white.g, greaterThan(248));
        expect(white.b, greaterThan(248));
        expect(blend.r, closeTo(234, 10));
        expect(blend.g, closeTo(184, 10));
        expect(blend.b, closeTo(179, 10));
      },
    );
  }
  test('transparent WebP composites over white', () {
    final result = normalizeGarmentPhoto((
      'alpha.webp',
      img.encodeWebP(chart(64, 48, alpha: true)),
    ));
    final pixel = img.decodeJpg(result.bytes)!.getPixel(8, 20);
    expect(pixel.r, greaterThan(248));
    expect(pixel.g, greaterThan(248));
    expect(pixel.b, greaterThan(248));
  });
  for (var orientation = 2; orientation <= 8; orientation++) {
    test('EXIF $orientation is baked once, with preserved corner colors', () {
      final source = chart(65, 49)..exif.imageIfd.orientation = orientation;
      final jpg = img.encodeJpg(source, quality: 95);
      final expected = img.bakeOrientation(img.decodeJpg(jpg)!);
      final result = normalizeGarmentPhoto(('exif.jpg', jpg));
      final actual = img.decodeJpg(result.bytes)!;
      expect((actual.width, actual.height), (expected.width, expected.height));
      expect(actual.exif.imageIfd.orientation, isNot(orientation));
      for (final x in [8, actual.width - 9]) {
        for (final y in [8, actual.height - 9]) {
          expect(
            actual.getPixel(x, y).r,
            closeTo(expected.getPixel(x, y).r, 8),
          );
          expect(
            actual.getPixel(x, y).g,
            closeTo(expected.getPixel(x, y).g, 8),
          );
        }
      }
    });
  }
  test('actual Flutter codec rejects corrupt bytes and mismatched dimensions before acceptance', () async {
    final bytes = testPhoto();
    for (final value in [
      ProcessedPhoto(Uint8List.fromList([1, 2, 3]), 8, 8),
      ProcessedPhoto(bytes, 9, 8),
      ProcessedPhoto(bytes, 2001, 2001),
    ]) {
      await expectLater(
        validatePhotoPreview(value),
        throwsA(isA<WardrobeException>()),
      );
    }
  });
  testWidgets(
    'failed replacement selection preserves existing local photo and metadata',
    (tester) async {
      final repo = MemoryWardrobe();
      final garment = testGarment();
      final old = testPhoto();
      repo.items[garment.id] = garment;
      repo.photos[garment.id] = old;
      final service = FakePhotoService()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WardrobeScreen(repository: repo, photoService: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey('garment-${garment.id}')));
      await tap(tester, find.text('정보 수정'));
      await tap(tester, find.text('사진 변경'));
      expect(find.text('손상된 사진이에요.'), findsOneWidget);
      expect(identical(repo.photos[garment.id], old), isTrue);
      expect(identical(repo.items[garment.id], garment), isTrue);
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
