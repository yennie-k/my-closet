// Standalone browser persistence probe. No Flutter engine or test-only
// repository: this imports the same IndexedDB implementation as the app.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'package:my_closet/models/garment.dart';
import 'package:my_closet/services/storage/indexeddb_wardrobe_repository.dart';

@JS('document.body.textContent')
external set statusText(JSString value);
@JS('sessionStorage.getItem')
external JSString? getSessionValue(JSString key);
@JS('sessionStorage.setItem')
external void setSessionValue(JSString key, JSString value);

Future<void> main() async {
  const databaseName = 'my_closet_storage_probe';
  final factory = idbFactoryNative;
  final repository = IndexedDbWardrobeRepository(
    factory,
    databaseName: databaseName,
  );
  final photo = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1kAAAAASUVORK5CYII=',
    ),
  );
  final date = DateTime.utc(2026, 10, 26);
  final garment = Garment(
    id: 'refresh-probe',
    name: '새로고침 검증 셔츠',
    category: GarmentCategory.tops,
    createdAt: date,
    updatedAt: date,
    seasons: [Season.spring],
    notes: '영속 저장 검증',
    subtype: '내가 만든 세부 종류',
    primaryColor: '차콜빛 민트',
    additionalColors: ['연보라'],
    material: '면 70% / 폴리에스터 30%',
    fit: '나만의 핏',
    thickness: GarmentThickness.thin,
    imageMimeType: 'image/png',
    imageWidth: 1,
    imageHeight: 1,
  );
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  bool sameBytes(Uint8List a, Uint8List b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
  try {
    final phase = getSessionValue('closet-probe-phase'.toJS)?.toDart;
    if (phase == null) {
      // Seed the exact old schema, not a v2 model serialized by the new code.
      await repository.list();
      final db = await factory.open(databaseName);
      final legacy = {...garment.toJson(), 'version': 1};
      for (final key in [
        'materials',
        'thicknessLevel',
        'primaryColorHex',
        'additionalColorDetails',
      ]) {
        legacy.remove(key);
      }
      final tx = db.transactionList(['garments', 'photos'], idbModeReadWrite);
      await tx.objectStore('garments').put(legacy, garment.id);
      await tx.objectStore('photos').put(photo, garment.id);
      await tx.completed;
      db.close();
      await repository.close();
      setSessionValue('closet-probe-phase'.toJS, 'read'.toJS);
      statusText = 'WRITE_OK'.toJS;
      return;
    }
    final saved = (await repository.list()).single;
    if (phase == 'read') {
      check(
        jsonEncode(saved.toJson()) == jsonEncode(garment.toJson()),
        'metadata differs after page reload',
      );
      check(
        sameBytes(await repository.readImage(saved.id), photo),
        'image differs after page reload',
      );
      final rawDb = await factory.open(databaseName);
      final rawTx = rawDb.transaction('garments', idbModeReadOnly);
      final raw =
          await rawTx.objectStore('garments').getObject(saved.id) as Map;
      await rawTx.completed;
      rawDb.close();
      check(
        raw['version'] == 1 && !raw.containsKey('materials'),
        'read unexpectedly overwrote v1 metadata',
      );
      final updated = Garment.fromJson({
        ...saved.toJson(),
        'name': '수정 완료',
        'materials': [saved.material, '울'],
        'thicknessLevel': 5,
      });
      await repository.save(updated);
      check((await repository.list()).single.name == '수정 완료', 'update failed');
      check(
        sameBytes(await repository.readImage(saved.id), photo),
        'update lost photo',
      );
      await repository.close();
      setSessionValue('closet-probe-phase'.toJS, 'updated'.toJS);
      statusText = 'READ_AFTER_RELOAD_OK; UPDATE_WRITTEN'.toJS;
      return;
    }
    check(saved.name == '수정 완료', 'v2 update lost after second reload');
    check(
      saved.materials.length == 2 && saved.materials.first == garment.material,
      'legacy mixture lost',
    );
    check(saved.thicknessLevel == 5, 'v2 thickness lost');
    check(
      saved.id == garment.id &&
          saved.createdAt == garment.createdAt &&
          saved.updatedAt == garment.updatedAt,
      'migration changed identifiers or timestamps',
    );
    check(
      sameBytes(await repository.readImage(saved.id), photo),
      'v2 reload lost original image',
    );
    await repository.delete(saved.id);
    check((await repository.list()).isEmpty, 'metadata delete failed');
    var photoDeleted = false;
    try {
      await repository.readImage(saved.id);
    } catch (_) {
      photoDeleted = true;
    }
    check(photoDeleted, 'photo delete failed');
    await repository.close();
    await factory.deleteDatabase(databaseName);
    statusText = 'UPDATED_AFTER_RELOAD_OK; LEGACY_PRESERVED; DELETE_OK'.toJS;
  } catch (error, stack) {
    await repository.close();
    statusText = 'PROBE_ERROR: $error\n$stack'.toJS;
  }
}
