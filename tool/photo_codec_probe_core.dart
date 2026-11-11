import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:my_closet/services/garment_photo_processor.dart';

List<List<int>> samples(img.Image image) => [
  for (final y in [.1, .3, .7, .9])
    for (final x in [.1, .3, .7, .9])
      [
        for (final c in [
          image
              .getPixel((x * image.width).floor(), (y * image.height).floor())
              .rNormalized,
          image
              .getPixel((x * image.width).floor(), (y * image.height).floor())
              .gNormalized,
          image
              .getPixel((x * image.width).floor(), (y * image.height).floor())
              .bNormalized,
        ])
          (c * 255).round(),
      ],
];
Map<String, dynamic> probePhoto(Map<String, dynamic> item) {
  try {
    final bytes = Uint8List.fromList(base64Decode(item['bytes'] as String));
    final decoded = img.decodeImage(bytes)!;
    final oriented = img.bakeOrientation(decoded);
    final result = normalizeGarmentPhoto((item['file'] as String, bytes));
    return {
      'name': item['name'],
      'decoded': samples(oriented),
      'decodedSize': [oriented.width, oriented.height],
      'output': samples(img.decodeJpg(result.bytes)!),
      'outputSize': [result.width, result.height],
      'jpeg': base64Encode(result.bytes),
    };
  } catch (e) {
    return {'name': item['name'], 'error': e.toString()};
  }
}
