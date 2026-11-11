import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/garment.dart';
import 'garment_photo_service.dart';
import 'server_photo_repository.dart';
import 'supabase_wardrobe_repository.dart';
import 'wardrobe_repository.dart';

class ServerPhotoException extends WardrobeException {
  ServerPhotoException(this.code, {this.retryable = false})
    : super(photoErrorMessage(code));
  final String code;
  final bool retryable;
}

String photoErrorMessage(String code) => switch (code) {
  'unauthorized' ||
  'authentication_unavailable' => '사진 작업의 인증을 확인하지 못했어요. 로그인 상태를 확인해 주세요.',
  'invalid_request' ||
  'size_mismatch' => '사진은 2MiB 이하의 JPG·PNG·WebP여야 해요. 다시 선택해 주세요.',
  'invalid_image' ||
  'mime_mismatch' ||
  'hash_mismatch' ||
  'download_corrupt' => '사진 형식·크기·해시 검증에 실패했어요. 이전 사진은 유지돼요. 다른 사진을 선택해 주세요.',
  'not_found_or_not_owned' => '의류가 없거나 사진 작업 권한이 없어요.',
  'pending_upload_exists' => '이전 업로드가 남아 있어요. 상태를 확인하거나 업로드를 취소해 주세요.',
  'cleanup_pending' || 'cleanup_not_due' =>
    '이전 사진 보호 기간에는 다시 교체하거나 의류를 삭제할 수 없어요. 표시된 시각 이후 정리해 주세요.',
  'expired' => '업로드 예약이 만료됐어요. 남은 업로드를 취소한 후 다시 선택해 주세요.',
  'revision_conflict' ||
  'reservation_mismatch' => '다른 작업에서 의류나 사진 상태가 바뀌었어요. 저장된 정보를 다시 확인해 주세요.',
  'verification_in_progress' => '서버가 사진을 검증하고 있어요. 잠시 후 검증 재시도를 눌러 주세요.',
  'object_referenced' => '다른 작업에서 사용 중인 사진은 정리하지 않았어요. 상태를 새로 확인해 주세요.',
  'upload_failed' => '사진 전송을 완료하지 못했어요. 이전 사진은 유지돼요. 같은 사진으로 다시 시도할 수 있어요.',
  'not_found' => '업로드된 사진을 아직 찾지 못했어요. 예약 만료 전 다시 검증할 수 있어요.',
  _ => '사진 작업을 완료하지 못했어요. 이전 사진을 유지하고 있으니 로컬 서버 연결과 사진 상태를 확인해 주세요.',
};

void validateServerPhoto(ProcessedPhoto photo) {
  if (photo.bytes.isEmpty || photo.bytes.length > 2097152) {
    throw ServerPhotoException('size_mismatch');
  }
  final img.Decoder decoder = switch (photo.mimeType) {
    'image/jpeg' => img.JpegDecoder(),
    'image/png' => img.PngDecoder(),
    'image/webp' => img.WebPDecoder(),
    _ => throw ServerPhotoException('mime_mismatch'),
  };
  try {
    final info = decoder.startDecode(photo.bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width > 4096 ||
        info.height > 4096 ||
        info.width * info.height > 4000000 ||
        info.width != photo.width ||
        info.height != photo.height) {
      throw ServerPhotoException('invalid_image');
    }
  } on ServerPhotoException {
    rethrow;
  } catch (_) {
    throw ServerPhotoException('invalid_image');
  }
}

class SupabasePhotoWardrobeRepository extends SupabaseWardrobeRepository
    implements ServerPhotoRepository {
  SupabasePhotoWardrobeRepository({
    required super.client,
    required super.userId,
    required super.sessionIsCurrent,
  });
  final _cache = <String, Uint8List>{};
  bool _photosClosed = false;
  void _guard() {
    if (_photosClosed ||
        !sessionIsCurrent() ||
        client.auth.currentUser?.id != userId ||
        client.auth.currentSession == null) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.sessionChanged,
        '로그인 계정이 바뀌었어요. 사진 화면을 다시 열어 주세요.',
      );
    }
  }

  Future<T> _photoRequest<T>(Future<T> Function() action) async {
    _guard();
    try {
      final result = await action();
      _guard();
      return result;
    } on ServerPhotoException {
      rethrow;
    } on ServerWardrobeException {
      rethrow;
    } on FunctionException catch (e) {
      final details = e.details;
      throw ServerPhotoException(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'operations_unavailable',
        retryable: details is Map && details['retryable'] == true,
      );
    } on StorageException {
      throw ServerPhotoException('storage_unavailable', retryable: true);
    } catch (_) {
      throw ServerPhotoException('operations_unavailable', retryable: true);
    }
  }

  Future<Map<String, dynamic>> _command(
    String action,
    Garment garment, {
    Map<String, dynamic> extra = const {},
  }) async {
    final row = recordFor(garment);
    final response = await client.functions
        .invoke(
          'garment-photo-operations',
          body: {
            'action': action,
            'garment_id': row.serverId,
            'revision': row.revision,
            ...extra,
          },
        )
        .timeout(const Duration(seconds: 80));
    _guard();
    return Map<String, dynamic>.from(response.data as Map);
  }

  @override
  ServerPhotoStatus photoStatus(Garment garment) {
    final row = recordFor(garment).raw;
    return ServerPhotoStatus(
      ready:
          row['photo_state'] == 'ready' &&
          row['photo_verified_at'] != null &&
          row['photo_path'] != null,
      uploadState: row['upload_state'] as String,
      errorCode: row['upload_error_code'] as String?,
      cleanupAfter: DateTime.tryParse(
        row['retired_cleanup_after'] as String? ?? '',
      ),
    );
  }

  @override
  String? photoKey(Garment garment) => photoStatus(garment).ready
      ? recordFor(garment).raw['photo_path'] as String
      : null;
  @override
  Future<Uint8List> readVerifiedPhoto(Garment garment) => _photoRequest(
    () async {
      final record = recordFor(garment), path = photoKey(garment);
      if (path == null) throw ServerPhotoException('not_found');
      if (!RegExp('^$userId/${record.serverId}/[0-9a-f]{64}[.](jpg|png|webp)\$')
          .hasMatch(path)) {
        throw ServerPhotoException('download_corrupt');
      }
      final cached = _cache.remove(path);
      if (cached != null) {
        _cache[path] = cached;
        return cached;
      }
      final bytes = await client.storage
          .from('garment-photos')
          .setHeader('Cache-Control', 'no-store, no-cache')
          .download(path)
          .timeout(const Duration(seconds: 25));
      _guard();
      if (bytes.length != record.raw['photo_size_bytes'] ||
          sha256.convert(bytes).toString() != record.raw['photo_sha256']) {
        throw ServerPhotoException('download_corrupt');
      }
      _cache[path] = bytes;
      if (_cache.length > 12) {
        final old = _cache.remove(_cache.keys.first)!;
        await MemoryImage(old).evict();
      }
      return bytes;
    },
  );
  @override
  Future<Garment> uploadPhoto(
    Garment garment,
    ProcessedPhoto photo, {
    void Function(String)? onProgress,
  }) => _photoRequest(() async {
    final copy = ProcessedPhoto(
      Uint8List.fromList(photo.bytes),
      photo.width,
      photo.height,
      mimeType: photo.mimeType,
    );
    validateServerPhoto(copy);
    final hash = sha256.convert(copy.bytes).toString();
    final ext = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
    }[copy.mimeType]!;
    final expected = '$userId/${recordFor(garment).serverId}/$hash.$ext';
    onProgress?.call('사진 업로드 예약 중…');
    final reserved = await _command(
      'reserve',
      garment,
      extra: {
        'sha256': hash,
        'size_bytes': copy.bytes.length,
        'mime_type': copy.mimeType,
      },
    );
    var current = await refresh(garment);
    if (reserved['status'] == 'already_verified') {
      onProgress?.call('사진 검증 완료');
      return current;
    }
    final r = recordFor(current);
    if (r.raw['upload_path'] != expected) {
      throw ServerPhotoException('reservation_mismatch');
    }
    if (r.raw['upload_state'] == 'reserved') {
      onProgress?.call('사진 전송 중…');
      try {
        await client.storage
            .from('garment-photos')
            .uploadBinary(
              expected,
              copy.bytes,
              fileOptions: FileOptions(
                contentType: copy.mimeType,
                cacheControl: '0',
                upsert: false,
              ),
              retryAttempts: 0,
            );
      } on StorageException catch (e) {
        if (!['409', '400'].contains(e.statusCode)) {
          throw ServerPhotoException('upload_failed', retryable: true);
        }
        // A lost response may leave the exact content-addressed object. Never
        // overwrite it; authenticate and compare bytes before acknowledging.
        final existing = await client.storage
            .from('garment-photos')
            .download(expected);
        _guard();
        if (existing.length != copy.bytes.length ||
            sha256.convert(existing).toString() != hash) {
          throw ServerPhotoException('hash_mismatch');
        }
      }
      _guard();
      final confirmed = await client
          .from('garments')
          .update({'upload_state': 'client_confirmed'})
          .eq('id', r.serverId)
          .eq('user_id', userId)
          .eq('revision', r.revision)
          .eq('upload_state', 'reserved')
          .eq('upload_path', expected)
          .select('id');
      if (confirmed.isEmpty) {
        current = await refresh(current);
        if (photoKey(current) == expected) {
          onProgress?.call('사진 검증 완료');
          return current;
        }
        if (![
              'client_confirmed',
              'checking',
            ].contains(recordFor(current).raw['upload_state']) ||
            recordFor(current).raw['upload_path'] != expected) {
          throw ServerPhotoException('revision_conflict', retryable: true);
        }
      } else {
        current = await refresh(current);
      }
    }
    onProgress?.call('서버에서 실제 사진 검증 중…');
    await _command('verify', current, extra: {'upload_path': expected});
    final verified = await refresh(current);
    if (photoKey(verified) != expected) {
      throw ServerPhotoException('verification_unavailable', retryable: true);
    }
    onProgress?.call('사진 검증 완료');
    return verified;
  });
  @override
  Future<Garment> verifyPendingPhoto(Garment garment) =>
      _photoRequest(() async {
        final path = recordFor(garment).raw['upload_path'];
        if (path == null) throw ServerPhotoException('reservation_mismatch');
        await _command('verify', garment, extra: {'upload_path': path});
        return refresh(garment);
      });
  @override
  Future<Garment> cancelPendingPhoto(Garment garment) =>
      _photoRequest(() async {
        final path = recordFor(garment).raw['upload_path'];
        if (path == null) throw ServerPhotoException('reservation_mismatch');
        await _command('cancel', garment, extra: {'path': path});
        return refresh(garment);
      });
  @override
  Future<Garment> removePhoto(Garment garment) => _photoRequest(() async {
    final path = photoKey(garment);
    if (path == null) throw ServerPhotoException('not_found');
    await _command('remove', garment, extra: {'path': path});
    return refresh(garment);
  });
  @override
  Future<Garment> cleanupPhoto(Garment garment) => _photoRequest(() async {
    final path = recordFor(garment).raw['retired_photo_path'];
    if (path == null) return garment;
    await _command('cleanup', garment, extra: {'path': path});
    return refresh(garment);
  });
  @override
  Future<void> close() async {
    _photosClosed = true;
    final bytes = _cache.values.toList();
    _cache.clear();
    for (final value in bytes) {
      await MemoryImage(value).evict();
    }
    await super.close();
  }
}
