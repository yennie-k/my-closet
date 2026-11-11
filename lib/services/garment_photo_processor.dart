import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'wardrobe_repository.dart';

const maxInputPhotoBytes = 15 * 1024 * 1024;

enum PhotoProcessingStage { decoded, oriented, resized, composited }

class ProcessedPhoto {
  const ProcessedPhoto(
    this.bytes,
    this.width,
    this.height, {
    this.mimeType = 'image/jpeg',
  });
  final Uint8List bytes;
  final int width, height;
  final String mimeType;
}

// Independent of the picker and persistence; future AI analysis can receive the
// normalized photo without changing the form or either storage implementation.
// This is the low-level Dart decoder path. User-selected files must enter
// prepareGarmentPhoto (in the service) for restart-JPEG compatibility handling.
ProcessedPhoto normalizeGarmentPhoto(
  (String, Uint8List) input, {
  void Function(PhotoProcessingStage stage, img.Image image)? observe,
}) {
  try {
    final decoder = _validatedDecoder(input);
    var decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const WardrobeException('사진이 손상되어 미리 볼 수 없어요. 다른 사진을 선택해 주세요.');
    }
    return _normalizeDecodedImage(decoded, observe: observe);
  } on WardrobeException {
    rethrow;
  } catch (_) {
    throw const WardrobeException(
      '사진을 읽을 수 없어요. 손상되지 않은 JPG, PNG, WebP 사진을 선택해 주세요.',
    );
  }
}

img.Decoder _validatedDecoder((String, Uint8List) input) {
  final (name, bytes) = input;
  final extension = name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
    throw const WardrobeException('JPG, PNG, WebP 사진만 등록할 수 있어요.');
  }
  if (bytes.isEmpty || bytes.length > maxInputPhotoBytes) {
    throw const WardrobeException('사진은 비어 있지 않은 15MB 이하 파일이어야 해요.');
  }
  try {
    final img.Decoder decoder = switch (extension) {
      'jpg' || 'jpeg' => img.JpegDecoder(),
      'png' => img.PngDecoder(),
      _ => img.WebPDecoder(),
    };
    final info = decoder.startDecode(bytes);
    if (info == null) {
      throw const WardrobeException(
        '확장자와 사진 형식이 다르거나 손상된 사진이에요. 다른 사진을 선택해 주세요.',
      );
    }
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 24000000 ||
        info.width > 12000 ||
        info.height > 12000) {
      throw const WardrobeException(
        '사진 해상도가 너무 커요. 2,400만 화소 이하의 사진을 선택해 주세요.',
      );
    }
    return decoder;
  } on WardrobeException {
    rethrow;
  } catch (_) {
    throw const WardrobeException('?? ??? ?? ? ???. ?? ??? ??? ???.');
  }
}

void validateGarmentPhotoInput((String, Uint8List) input) {
  _validatedDecoder(input);
}

ProcessedPhoto normalizeRgbaGarmentPhoto((Uint8List, int, int) input) {
  final (rgba, width, height) = input;
  if (width < 1 ||
      height < 1 ||
      width > 12000 ||
      height > 12000 ||
      width * height > 24000000 ||
      rgba.length != width * height * 4) {
    throw const WardrobeException('?? ?? ??? ???? ????. ?? ??? ??? ???.');
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
    rowStride: width * 4,
  );
  // Flutter has already baked JPEG orientation. This image has no EXIF.
  return _normalizeDecodedImage(image);
}

ProcessedPhoto _normalizeDecodedImage(
  img.Image decoded, {
  void Function(PhotoProcessingStage, img.Image)? observe,
}) {
  observe?.call(PhotoProcessingStage.decoded, decoded);
  decoded = img.bakeOrientation(decoded);
  observe?.call(PhotoProcessingStage.oriented, decoded);
  if (decoded.width > 1600 || decoded.height > 1600) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 1600 : null,
      height: decoded.height > decoded.width ? 1600 : null,
    );
  }
  observe?.call(PhotoProcessingStage.resized, decoded);
  // JPEG has no transparency. Composite transparent PNG/WebP over white.
  final canvas = img.Image(width: decoded.width, height: decoded.height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, decoded);
  observe?.call(PhotoProcessingStage.composited, canvas);
  var output = img.encodeJpg(canvas, quality: 85);
  if (output.length > 2 * 1024 * 1024) {
    output = img.encodeJpg(canvas, quality: 65);
  }
  if (output.length > 2 * 1024 * 1024) {
    throw const WardrobeException('사진을 충분히 압축하지 못했어요. 더 작은 사진을 선택해 주세요.');
  }
  return ProcessedPhoto(output, canvas.width, canvas.height);
}

/// Only JPEGs declaring a nonzero DRI use the proven native-codec compatibility
/// path. No entropy or pixel bytes are rewritten, and ordinary formats retain
/// their existing decoder. This bounded marker walk stops at the first scan.
bool hasJpegRestartInterval(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) return false;
  var at = 2;
  var interval = 0;
  while (at + 1 < bytes.length) {
    if (bytes[at++] != 255) return false;
    while (at < bytes.length && bytes[at] == 255) {
      at++;
    }
    if (at >= bytes.length) return false;
    final marker = bytes[at++];
    if (marker == 218) return interval > 0;
    if (marker == 217) return false;
    if (marker == 1 || marker == 216 || (marker >= 208 && marker <= 215)) {
      continue;
    }
    if (at + 2 > bytes.length) return false;
    final length = (bytes[at] << 8) | bytes[at + 1];
    if (length < 2 || at + length > bytes.length) return false;
    if (marker == 221) {
      if (length != 4) return false;
      interval = (bytes[at + 2] << 8) | bytes[at + 3];
    }
    at += length;
  }
  return false;
}
