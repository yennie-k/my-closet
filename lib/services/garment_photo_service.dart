import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'wardrobe_repository.dart';

class ProcessedPhoto {
  const ProcessedPhoto(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

abstract interface class GarmentPhotoService {
  Future<ProcessedPhoto?> pick();
}

class FileGarmentPhotoService implements GarmentPhotoService {
  static const maxInputBytes = 15 * 1024 * 1024;
  @override
  Future<ProcessedPhoto?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '옷 사진 (JPG, PNG, WebP)',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          uniformTypeIdentifiers: [
            'public.jpeg',
            'public.png',
            'org.webmproject.webp',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxInputBytes) {
      throw const WardrobeException('사진은 15MB 이하로 선택해 주세요.');
    }
    return compute(normalizeGarmentPhoto, (
      file.name,
      await file.readAsBytes(),
    ));
  }
}

// Independent of the picker and persistence; future AI analysis can receive the
// normalized photo without changing the form or either storage implementation.
ProcessedPhoto normalizeGarmentPhoto((String, Uint8List) input) {
  final (name, bytes) = input;
  final extension = name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
    throw const WardrobeException('JPG, PNG, WebP 사진만 등록할 수 있어요.');
  }
  if (bytes.isEmpty || bytes.length > FileGarmentPhotoService.maxInputBytes) {
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
    var decoded = decoder.decodeFrame(0);
    if (decoded == null) {
      throw const WardrobeException('사진이 손상되어 미리 볼 수 없어요. 다른 사진을 선택해 주세요.');
    }
    decoded = img.bakeOrientation(decoded);
    if (decoded.width > 1600 || decoded.height > 1600) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 1600 : null,
        height: decoded.height > decoded.width ? 1600 : null,
      );
    }
    // JPEG has no transparency. Composite transparent PNG/WebP over white.
    final canvas = img.Image(width: decoded.width, height: decoded.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, decoded);
    var output = img.encodeJpg(canvas, quality: 85);
    if (output.length > 2 * 1024 * 1024) {
      output = img.encodeJpg(canvas, quality: 65);
    }
    if (output.length > 2 * 1024 * 1024) {
      throw const WardrobeException('사진을 충분히 압축하지 못했어요. 더 작은 사진을 선택해 주세요.');
    }
    return ProcessedPhoto(output, canvas.width, canvas.height);
  } on WardrobeException {
    rethrow;
  } catch (_) {
    throw const WardrobeException(
      '사진을 읽을 수 없어요. 손상되지 않은 JPG, PNG, WebP 사진을 선택해 주세요.',
    );
  }
}
