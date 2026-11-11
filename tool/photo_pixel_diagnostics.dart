// In-memory diagnostics only. No file, network, repository or upload access.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:my_closet/services/garment_photo_service.dart';
// Diagnostic experiment only: never used by the app's image processing path.
// ignore: implementation_imports
import 'package:image/src/formats/jpeg/jpeg_data.dart' show JpegData;

class DecodedPixels {
  const DecodedPixels(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
}

Future<DecodedPixels> flutterPixels(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('No decoded RGBA pixels');
    return DecodedPixels(
      image.width,
      image.height,
      Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

DecodedPixels dartPixels(img.Image image) => DecodedPixels(
  image.width,
  image.height,
  Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgba)),
);

Map<String, Object> pixelDifference(DecodedPixels a, DecodedPixels b) {
  if (a.width != b.width ||
      a.height != b.height ||
      a.rgba.length != b.rgba.length) {
    return {
      'dimensions_match': false,
      'a_size': '${a.width}x${a.height}',
      'b_size': '${b.width}x${b.height}',
    };
  }
  var sum = 0, maxError = 0, different = 0;
  final rows = <double>[];
  for (var y = 0; y < a.height; y++) {
    var rowSum = 0;
    for (var x = 0; x < a.width; x++) {
      final offset = (y * a.width + x) * 4;
      var pixelMax = 0;
      for (var c = 0; c < 3; c++) {
        final d = (a.rgba[offset + c] - b.rgba[offset + c]).abs();
        rowSum += d;
        if (d > maxError) maxError = d;
        if (d > pixelMax) pixelMax = d;
      }
      if (pixelMax > 16) different++;
    }
    sum += rowSum;
    rows.add(double.parse((rowSum / (a.width * 3)).toStringAsFixed(3)));
  }
  return {
    'dimensions_match': true,
    'rgb_mae': double.parse(
      (sum / (a.width * a.height * 3)).toStringAsFixed(4),
    ),
    'max_channel_error': maxError,
    'pixels_above_16': different,
    'pixels_above_16_fraction': different / (a.width * a.height),
    'rgba_exact':
        sha256.convert(a.rgba).toString() == sha256.convert(b.rgba).toString(),
    'row_rgb_mae': rows,
  };
}

/// Marker metadata only. Does not claim that syntactically valid JPEG is intact.
Map<String, Object?> jpegHeaderSummary(Uint8List data) {
  if (data.length < 4 || data[0] != 255 || data[1] != 216) {
    throw const FormatException('Not a JPEG SOI');
  }
  final scans = <Map<String, Object?>>[];
  final frames = <Map<String, Object?>>[];
  final restarts = <int>[];
  var restartInterval = 0, at = 2, eoi = false;
  int? adobeTransform;
  while (at < data.length) {
    if (data[at++] != 255) continue;
    while (at < data.length && data[at] == 255) {
      at++;
    }
    if (at >= data.length) break;
    final marker = data[at++];
    if (marker == 0) continue;
    if (marker == 217) {
      eoi = true;
      break;
    }
    if (marker >= 208 && marker <= 215) {
      restarts.add(marker - 208);
      continue;
    }
    if (marker == 216 || marker == 1) continue;
    if (at + 2 > data.length) {
      throw const FormatException('Truncated JPEG marker');
    }
    final length = (data[at] << 8) | data[at + 1];
    if (length < 2 || at + length > data.length) {
      throw const FormatException('Invalid JPEG marker length');
    }
    final begin = at + 2, end = at + length;
    if (marker == 221 && length == 4) {
      restartInterval = (data[begin] << 8) | data[begin + 1];
    }
    if (marker == 238 &&
        end - begin >= 12 &&
        String.fromCharCodes(data.sublist(begin, begin + 5)) == 'Adobe') {
      adobeTransform = data[begin + 11];
    }
    if (marker >= 192 && marker <= 207 && ![196, 200, 204].contains(marker)) {
      if (end - begin < 6) throw const FormatException('Invalid SOF');
      final n = data[begin + 5];
      if (begin + 6 + 3 * n > end) {
        throw const FormatException('Invalid SOF components');
      }
      frames.add({
        'marker': '0x${marker.toRadixString(16)}',
        'precision': data[begin],
        'width': (data[begin + 3] << 8) | data[begin + 4],
        'height': (data[begin + 1] << 8) | data[begin + 2],
        'components': [
          for (var i = 0; i < n; i++)
            {
              'id': data[begin + 6 + i * 3],
              'h': data[begin + 7 + i * 3] >> 4,
              'v': data[begin + 7 + i * 3] & 15,
            },
        ],
      });
    }
    if (marker == 218) {
      if (begin >= end) throw const FormatException('Invalid SOS');
      final n = data[begin];
      if (begin + 1 + 2 * n + 3 > end) {
        throw const FormatException('Invalid SOS');
      }
      scans.add({
        'components': [for (var i = 0; i < n; i++) data[begin + 1 + 2 * i]],
        'spectral_start': data[begin + 1 + 2 * n],
        'spectral_end': data[begin + 2 + 2 * n],
        'approximation': data[begin + 3 + 2 * n],
      });
    }
    at = end;
  }
  return {
    'frames': frames,
    'scans': scans,
    'restart_interval': restartInterval,
    'restart_count': restarts.length,
    'restart_prefix': restarts.take(16).toList(),
    'adobe_transform': adobeTransform,
    'has_eoi': eoi,
  };
}

Future<Map<String, Object?>> compareJpegPixels(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('Diagnostic input byte limit');
  }
  final decoder = img.JpegDecoder(maxPixels: 24000000);
  final info = decoder.startDecode(bytes);
  // Keep this expensive, multi-codec diagnostic separate from the production
  // 24MP input bound. The reported 2048x1536 image fits this 4MP diagnostic cap.
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 4000000) {
    throw const FormatException('Pixel comparison supports JPEG up to 4MP');
  }
  final native = await flutterPixels(bytes);
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('JPEG decode failed');
  // Capture before orientation, resize, PNG or JPEG encoding.
  final raw = dartPixels(decoded);
  final oriented = img.bakeOrientation(decoded);
  final dartOriented = dartPixels(oriented);
  final png = img.encodePng(
    decoded,
  ); // FULL SIZE. No diagnostic thumbnail resize.
  final pngNative = await flutterPixels(png);
  final pngDart = dartPixels(img.decodePng(png)!);
  // Same installed library, disabling only its streaming/band optimization via
  // its internal experiment entry point. Not a production workaround/API.
  final full = dartPixels(
    (JpegData()
          ..maxPixels = 4000000
          ..read(bytes))
        .getImage(),
  );
  return {
    'input_bytes': bytes.length,
    'input_sha256': sha256.convert(bytes).toString(),
    'jpeg': jpegHeaderSummary(bytes),
    'source_exif_orientation':
        img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1,
    'exif_orientation': decoded.exif.imageIfd.orientation ?? 1,
    'has_icc': decoded.iccProfile != null,
    'flutter_vs_dart_decoded': pixelDifference(native, raw),
    'flutter_vs_dart_oriented': pixelDifference(native, dartOriented),
    'dart_raw_vs_png_dart_roundtrip': pixelDifference(raw, pngDart),
    'dart_raw_vs_png_flutter_roundtrip': pixelDifference(raw, pngNative),
    'flutter_vs_dart_nonstreaming': pixelDifference(native, full),
    'dart_streaming_vs_nonstreaming': pixelDifference(raw, full),
  };
}

Future<Map<String, Object?>> comparePreparedJpeg(Uint8List bytes) async {
  final photo = await prepareGarmentPhoto(('read-only.jpg', bytes));
  final source = await flutterPixels(bytes);
  final reference = img.Image.fromBytes(
    width: source.width,
    height: source.height,
    bytes: source.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final resized = img.copyResize(
    reference,
    width: photo.width,
    height: photo.height,
  );
  return {
    'compatibility_path': hasJpegRestartInterval(bytes),
    'output_width': photo.width,
    'output_height': photo.height,
    'output_bytes': photo.bytes.length,
    'reference_resized_vs_production_jpeg': pixelDifference(
      dartPixels(resized),
      await flutterPixels(photo.bytes),
    ),
  };
}
