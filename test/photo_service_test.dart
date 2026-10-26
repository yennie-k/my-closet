import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

void main() {
  test('JPG, PNG and WebP decode into persistent JPEG bytes', () {
    final source = img.Image(width: 16, height: 12);
    for (final input in [
      ('photo.JPG', img.encodeJpg(source)),
      ('photo.png', img.encodePng(source)),
      ('photo.webp', img.encodeWebP(source)),
    ]) {
      final processed = normalizeGarmentPhoto(input);
      expect(processed.width, 16);
      expect(processed.height, 12);
      expect(img.decodeJpg(processed.bytes), isNotNull);
    }
  });
  test('Large image is resized without changing aspect ratio', () {
    final result = normalizeGarmentPhoto((
      'large.png',
      img.encodePng(img.Image(width: 2000, height: 1000)),
    ));
    expect(result.width, 1600);
    expect(result.height, 800);
    expect(result.bytes.length, lessThan(2 * 1024 * 1024));
  });
  test(
    'Unsupported, empty, corrupt, mismatched and oversized files are rejected',
    () {
      for (final input in [
        ('a.gif', Uint8List(2)),
        ('a.jpg', Uint8List(0)),
        ('a.png', Uint8List.fromList([1, 2, 3])),
        ('a.jpg', img.encodePng(img.Image(width: 4, height: 4))),
        ('a.png', Uint8List(FileGarmentPhotoService.maxInputBytes + 1)),
      ]) {
        expect(
          () => normalizeGarmentPhoto(input),
          throwsA(isA<WardrobeException>()),
        );
      }
    },
  );
}
