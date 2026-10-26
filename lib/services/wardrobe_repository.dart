import 'dart:typed_data';

import '../models/garment.dart';

class WardrobeException implements Exception {
  const WardrobeException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Metadata and its image must commit together. Future Supabase implementations
// can upload Storage objects and return the same domain models.
abstract interface class WardrobeRepository {
  Future<List<Garment>> list();
  Future<Uint8List> readImage(String id);
  Future<void> save(Garment garment, {Uint8List? imageBytes});
  Future<void> delete(String id);
  Future<void> close();
}

String wardrobeError(Object error) {
  if (error is WardrobeException) return error.message;
  final description = error.toString().toLowerCase();
  if (description.contains('quota') ||
      description.contains('space') ||
      description.contains('disk full')) {
    return '저장 공간이 부족해요. 불필요한 옷을 삭제하거나 기기의 여유 공간을 확보한 뒤 다시 시도해 주세요.';
  }
  return '옷장 저장소에 접근하지 못했어요. 브라우저의 저장 권한이나 기기의 여유 공간을 확인하고 다시 시도해 주세요.';
}
