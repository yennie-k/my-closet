import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/garment.dart';
import '../models/server_garment_record.dart';
import 'revisioned_wardrobe_repository.dart';
import 'wardrobe_repository.dart';

enum ServerWardrobeFailureKind {
  authentication,
  sessionChanged,
  permission,
  network,
  conflict,
  missingOrInaccessible,
  validation,
  duplicateChanged,
  photosUnsupported,
  unknown,
}

class ServerWardrobeException extends WardrobeException {
  const ServerWardrobeException(this.kind, super.message);
  final ServerWardrobeFailureKind kind;
}

/// User JWT only. No Storage API, local preferences or IndexedDB dependency.
class SupabaseWardrobeRepository
    implements RevisionedWardrobeRepository, MetadataOnlyWardrobeRepository {
  SupabaseWardrobeRepository({
    required this.client,
    required this.userId,
    required this.sessionIsCurrent,
  });
  final SupabaseClient client;
  final String userId;
  final bool Function() sessionIsCurrent;
  final _records = Expando<ServerGarmentRecord>();
  bool _closed = false;
  static const _timeout = Duration(seconds: 20);

  void _check() {
    if (_closed || !sessionIsCurrent()) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.sessionChanged,
        '로그인 계정이 바뀌었어요. 화면을 다시 열어 주세요.',
      );
    }
    if (client.auth.currentSession == null ||
        client.auth.currentUser?.id != userId ||
        client.auth.currentUser!.isAnonymous) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.authentication,
        '로그인한 사용자만 서버 옷장을 사용할 수 있어요.',
      );
    }
  }

  Future<T> _request<T>(Future<T> Function() action) async {
    _check();
    try {
      final result = await action().timeout(_timeout);
      _check(); // Discard results from an old account/session, including writes.
      return result;
    } on ServerWardrobeException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const ServerWardrobeException(
          ServerWardrobeFailureKind.permission,
          '이 작업에 대한 권한이 없어요. 로그인 상태와 서버 권한을 확인해 주세요.',
        );
      }
      if (['PGRST301', 'PGRST302', 'PGRST303'].contains(e.code)) {
        throw const ServerWardrobeException(
          ServerWardrobeFailureKind.authentication,
          '인증이 만료되었거나 유효하지 않아요. 다시 로그인해 주세요.',
        );
      }
      if (['23514', '23502', '22P02', '22001'].contains(e.code)) {
        throw const ServerWardrobeException(
          ServerWardrobeFailureKind.validation,
          '입력 정보가 서버의 저장 조건과 맞지 않아요. 값을 확인해 주세요.',
        );
      }
      if ([
        '502',
        '503',
        '504',
        'PGRST000',
        'PGRST001',
        'PGRST002',
      ].contains(e.code)) {
        throw _networkFailure;
      }
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.unknown,
        '서버가 작업을 완료하지 못했어요. 저장 여부와 서버 상태를 확인해 주세요.',
      );
    } on FormatException {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.unknown,
        '서버 응답을 읽지 못했어요. 데이터를 바꾸지 않고 다시 확인해 주세요.',
      );
    } on TimeoutException {
      throw _networkFailure;
    } on ClientException {
      throw _networkFailure;
    } catch (_) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.unknown,
        '서버 정보를 처리하지 못했어요. 입력 내용을 보관하고 다시 확인해 주세요.',
      );
    }
  }

  static const _networkFailure = ServerWardrobeException(
    ServerWardrobeFailureKind.network,
    '로컬 서버에 연결하지 못했어요. 저장 여부가 불확실할 수 있으니 같은 화면에서 다시 시도해 주세요.',
  );

  Garment _bind(Map<String, dynamic> row) {
    final record = ServerGarmentRecord(row);
    if (record.userId != userId) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.permission,
        '다른 계정의 데이터는 표시할 수 없어요.',
      );
    }
    _records[record.garment] = record;
    return record.garment;
  }

  ServerGarmentRecord recordFor(Garment original) {
    _check();
    final record = _records[original];
    if (record == null) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.conflict,
        '서버에서 읽은 원본 정보가 없어요. 새로고침한 뒤 다시 열어 주세요.',
      );
    }
    return record;
  }

  @override
  Future<List<Garment>> list() => _request(() async {
    // Explicit pagination avoids silently truncating at PostgREST's row cap.
    final result = <Garment>[];
    for (var start = 0; ; start += 200) {
      final rows = await client
          .from('garments')
          .select()
          .eq('user_id', userId)
          .order('server_created_at')
          .order('id')
          .range(start, start + 199);
      _check();
      result.addAll(rows.map(_bind));
      if (rows.length < 200) break;
    }
    return result;
  });

  Future<Map<String, dynamic>?> _find(String serverId) => client
      .from('garments')
      .select()
      .eq('user_id', userId)
      .eq('id', serverId)
      .maybeSingle();

  @override
  Future<Garment> refresh(Garment original) => _request(() async {
    final row = await _find(recordFor(original).serverId);
    if (row == null) _missing();
    return _bind(row);
  });

  Never _missing() => throw const ServerWardrobeException(
    ServerWardrobeFailureKind.missingOrInaccessible,
    '의류가 삭제되었거나 접근 권한이 없어 조회할 수 없어요. 목록을 새로고침해 주세요.',
  );

  Future<Never> _zeroRows(ServerGarmentRecord original) async {
    final current = await _find(original.serverId);
    _check();
    if (current == null) _missing();
    if (current['revision'] != original.revision) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.conflict,
        '다른 화면에서 이 옷이 변경되었어요. 자동으로 덮어쓰지 않았어요. 입력 내용을 보관한 뒤 화면을 닫고 새로고침해 주세요. 이전 요청이 이미 저장되었을 수도 있어요.',
      );
    }
    throw const ServerWardrobeException(
      ServerWardrobeFailureKind.permission,
      '서버의 권한 또는 사진 상태 제한으로 반영되지 않았어요. 새로고침 후 상태를 확인해 주세요.',
    );
  }

  @override
  Future<Garment> saveWithOriginal(Garment garment, {Garment? original}) =>
      _request(() async {
        if (original == null) return _create(garment);
        final before = recordFor(original);
        if (garment.id != before.garment.id ||
            garment.createdAt != before.garment.createdAt ||
            garment.imageWidth != before.garment.imageWidth ||
            garment.imageHeight != before.garment.imageHeight ||
            garment.imageMimeType != before.garment.imageMimeType) {
          throw const ServerWardrobeException(
            ServerWardrobeFailureKind.validation,
            '의류 식별자·등록일·사진 정보는 이 단계에서 바꿀 수 없어요.',
          );
        }
        final rows = await client
            .from('garments')
            .update(ServerGarmentRecord.metadata(garment, original: before))
            .eq('id', before.serverId)
            .eq('user_id', userId)
            .eq('revision', before.revision)
            .select();
        if (rows.isEmpty) await _zeroRows(before);
        return _bind(rows.single);
      });

  Future<Garment> _create(Garment garment) async {
    try {
      final row = await client
          .from('garments')
          .insert(ServerGarmentRecord.insert(garment, userId))
          .select()
          .single();
      return _bind(row);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      // Never use merge/upsert: retries must not overwrite an existing row.
      final row = await client
          .from('garments')
          .select()
          .eq('user_id', userId)
          .eq('local_id', garment.id)
          .maybeSingle();
      _check();
      if (row == null) {
        throw const ServerWardrobeException(
          ServerWardrobeFailureKind.duplicateChanged,
          '중복 요청을 확인하지 못했어요. 새로고침 후 등록 여부를 확인해 주세요.',
        );
      }
      final existing = ServerGarmentRecord(row);
      final wanted = ServerGarmentRecord.metadata(garment);
      final actual = ServerGarmentRecord.metadata(existing.garment);
      wanted.remove('updated_at');
      actual.remove('updated_at');
      if (jsonEncode(wanted) != jsonEncode(actual) ||
          existing.garment.createdAt != garment.createdAt ||
          existing.garment.imageWidth != garment.imageWidth ||
          existing.garment.imageHeight != garment.imageHeight ||
          existing.garment.imageMimeType != garment.imageMimeType) {
        throw const ServerWardrobeException(
          ServerWardrobeFailureKind.duplicateChanged,
          '같은 등록 요청이 이미 저장되어 있고 내용이 달라요. 덮어쓰지 않았어요. 입력 내용을 보관하고 목록을 새로고침해 주세요.',
        );
      }
      return _bind(row);
    }
  }

  @override
  Future<void> save(Garment garment, {Uint8List? imageBytes}) async {
    if (imageBytes != null) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.photosUnsupported,
        '서버 사진 업로드는 아직 지원하지 않아요.',
      );
    }
    await saveWithOriginal(garment);
  }

  @override
  Future<void> deleteWithOriginal(Garment original) => _request(() async {
    final before = recordFor(original);
    if (before.hasPhotoWorkflow) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.photosUnsupported,
        '사진 또는 업로드 예약이 남아 있어 의류를 삭제하지 않았어요. 업로드 취소 또는 사진 삭제 예약 후 보호 기간이 지난 사진을 정리해 주세요.',
      );
    }
    final rows = await client
        .from('garments')
        .delete()
        .eq('id', before.serverId)
        .eq('user_id', userId)
        .eq('revision', before.revision)
        .eq('photo_state', 'pending')
        .eq('upload_state', 'none')
        .isFilter('photo_path', null)
        .isFilter('upload_path', null)
        .isFilter('retired_photo_path', null)
        .select('id');
    if (rows.isEmpty) await _zeroRows(before);
  });

  @override
  Future<void> delete(String id) async => throw const ServerWardrobeException(
    ServerWardrobeFailureKind.conflict,
    '삭제하려면 읽었던 원본 revision이 필요해요. 상세 화면에서 다시 시도해 주세요.',
  );

  @override
  Future<Uint8List> readImage(String id) async =>
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.photosUnsupported,
        '서버 사진 조회·업로드는 다음 단계에서 연결해요.',
      );

  @override
  Future<void> close() async {
    _closed = true;
  }
}
