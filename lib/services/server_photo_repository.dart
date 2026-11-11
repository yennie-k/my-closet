import 'dart:typed_data';

import '../models/garment.dart';
import 'garment_photo_service.dart';
import 'wardrobe_repository.dart';

class ServerPhotoStatus {
  const ServerPhotoStatus({
    required this.ready,
    required this.uploadState,
    this.errorCode,
    this.cleanupAfter,
  });
  final bool ready;
  final String uploadState;
  final String? errorCode;
  final DateTime? cleanupAfter;
}

abstract interface class ServerPhotoRepository implements WardrobeRepository {
  ServerPhotoStatus photoStatus(Garment garment);
  String? photoKey(Garment garment);
  Future<Uint8List> readVerifiedPhoto(Garment garment);
  Future<Garment> uploadPhoto(
    Garment garment,
    ProcessedPhoto photo, {
    void Function(String)? onProgress,
  });
  Future<Garment> verifyPendingPhoto(Garment garment);
  Future<Garment> cancelPendingPhoto(Garment garment);
  Future<Garment> removePhoto(Garment garment);
  Future<Garment> cleanupPhoto(Garment garment);
}
