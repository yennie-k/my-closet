import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'wardrobe_repository.dart';
import 'garment_photo_processor.dart';
export 'garment_photo_processor.dart';

abstract interface class GarmentPhotoService {
  Future<ProcessedPhoto?> pick();
}

class FileGarmentPhotoService implements GarmentPhotoService {
  static const maxInputBytes = maxInputPhotoBytes;
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
    return prepareGarmentPhoto((file.name, await file.readAsBytes()));
  }
}

/// Restart JPEGs may contain camera alignment bytes before RSTn that image
/// 4.12.0 misreads as new MCUs. Confirmed with the original file and an isolated
/// decoder resynchronization experiment. Use the existing Flutter codec only
/// for this feature; PNG/WebP and JPEGs without DRI retain the existing path.
Future<ProcessedPhoto> prepareGarmentPhoto((String, Uint8List) input) async {
  validateGarmentPhotoInput(
    input,
  ); // Bound dimensions BEFORE native allocation.
  final photo = hasJpegRestartInterval(input.$2)
      ? await _prepareRestartJpeg(input.$2)
      : await compute(normalizeGarmentPhoto, input);
  await validatePhotoPreview(photo);
  return photo;
}

Future<ProcessedPhoto> _prepareRestartJpeg(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) throw const FormatException('No decoded pixels');
    final rgba = Uint8List.fromList(
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
    );
    final width = image.width, height = image.height;
    // Release native resources before resizing/encoding the copied RGBA.
    image.dispose();
    image = null;
    codec.dispose();
    codec = null;
    return await compute(normalizeRgbaGarmentPhoto, (rgba, width, height));
  } on WardrobeException {
    rethrow;
  } catch (_) {
    throw const WardrobeException(
      '이 JPEG 사진을 정상적으로 읽지 못했어요. 기존 사진은 유지돼요. 다른 사진을 선택해 주세요.',
    );
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Decode one frame using Flutter's actual codec before accepting a selection.
/// Structural validation cannot detect visually wrong but valid pixel content.
Future<void> validatePhotoPreview(ProcessedPhoto photo) async {
  ui.Codec? codec;
  ui.Image? frameImage;
  try {
    if (photo.bytes.isEmpty ||
        photo.bytes.length > 2 * 1024 * 1024 ||
        photo.width < 1 ||
        photo.height < 1 ||
        photo.width * photo.height > 4000000) {
      throw const FormatException('Invalid normalized image bounds');
    }
    codec = await ui.instantiateImageCodec(photo.bytes);
    frameImage = (await codec.getNextFrame()).image;
    if (frameImage.width != photo.width || frameImage.height != photo.height) {
      throw const FormatException('Decoded dimensions differ');
    }
  } catch (_) {
    throw const WardrobeException(
      '변환한 사진을 정상적으로 미리 볼 수 없어요. 선택한 사진은 적용하지 않았어요. 다른 사진을 선택해 주세요.',
    );
  } finally {
    frameImage?.dispose();
    codec?.dispose();
  }
}
