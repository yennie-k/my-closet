import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import '../../models/garment.dart';
import '../wardrobe_repository.dart';

class IndexedDbWardrobeRepository implements WardrobeRepository {
  IndexedDbWardrobeRepository(
    IdbFactory factory, {
    this.databaseName = 'my_closet_wardrobe_v1',
  }) : _factory = (() => factory);
  IndexedDbWardrobeRepository.lazy(
    this._factory, {
    this.databaseName = 'my_closet_wardrobe_v1',
  });
  final IdbFactory Function() _factory;
  final String databaseName;
  Future<Database>? _opening;
  Future<Database> _db() async {
    try {
      return await (_opening ??= _factory().open(
        databaseName,
        version: 1,
        onUpgradeNeeded: (event) {
          event.database.createObjectStore('garments');
          event.database.createObjectStore('photos');
        },
      ));
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<List<Garment>> list() async {
    final db = await _db();
    final tx = db.transaction('garments', idbModeReadOnly);
    final values = await tx.objectStore('garments').getAll();
    await tx.completed;
    try {
      final items = values
          .map((v) => Garment.fromJson(Map<String, Object?>.from(v as Map)))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      throw const WardrobeException(
        '저장된 옷 정보 일부를 읽을 수 없어요. 데이터를 지우지 않고 보관하고 있어요.',
      );
    }
  }

  @override
  Future<Uint8List> readImage(String id) async {
    final db = await _db();
    final tx = db.transaction('photos', idbModeReadOnly);
    final value = await tx.objectStore('photos').getObject(id);
    await tx.completed;
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    throw const WardrobeException('사진을 불러올 수 없어요. 수정 화면에서 사진을 다시 선택해 주세요.');
  }

  @override
  Future<void> save(Garment garment, {Uint8List? imageBytes}) async {
    final db = await _db();
    final tx = db.transactionList(['garments', 'photos'], idbModeReadWrite);
    // Await the transaction as well as requests: a quota failure can occur at commit.
    final committed = tx.completed;
    // Attach an error handler before requests to avoid unhandled abort errors.
    final settled = committed.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    try {
      if (imageBytes == null) {
        if (await tx.objectStore('photos').getObject(garment.id) == null) {
          throw const WardrobeException('사진이 필요해요. 사진을 다시 선택해 주세요.');
        }
      } else {
        if (imageBytes.isEmpty) {
          throw const WardrobeException('비어 있는 사진은 저장할 수 없어요.');
        }
        await tx.objectStore('photos').put(imageBytes, garment.id);
      }
      await tx.objectStore('garments').put(garment.toJson(), garment.id);
      final error = await settled;
      if (error != null) throw error;
    } catch (_) {
      try {
        tx.abort();
      } catch (_) {
        /* Already committed or aborted. */
      }
      await settled;
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db();
    final tx = db.transactionList(['garments', 'photos'], idbModeReadWrite);
    final settled = tx.completed.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    try {
      await tx.objectStore('garments').delete(id);
      await tx.objectStore('photos').delete(id);
      final error = await settled;
      if (error != null) throw error;
    } catch (_) {
      try {
        tx.abort();
      } catch (_) {}
      await settled;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    (await _opening)?.close();
    _opening = null;
  }
}
