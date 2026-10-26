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
    if (getSessionValue('closet-probe-phase'.toJS)?.toDart != 'read') {
      await repository.save(garment, imageBytes: photo);
      await repository.close();
      setSessionValue('closet-probe-phase'.toJS, 'read'.toJS);
      statusText = 'WRITE_OK'.toJS;
      return;
    }
    final saved = (await repository.list()).single;
    check(
      jsonEncode(saved.toJson()) == jsonEncode(garment.toJson()),
      'metadata differs after page reload',
    );
    check(
      sameBytes(await repository.readImage(saved.id), photo),
      'image differs after page reload',
    );
    final updated = Garment.fromJson({...saved.toJson(), 'name': '수정 완료'});
    await repository.save(updated);
    check((await repository.list()).single.name == '수정 완료', 'update failed');
    check(
      sameBytes(await repository.readImage(saved.id), photo),
      'update lost photo',
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
    statusText = 'READ_AFTER_RELOAD_OK; UPDATE_OK; DELETE_OK'.toJS;
  } catch (error, stack) {
    await repository.close();
    statusText = 'PROBE_ERROR: $error\n$stack'.toJS;
  }
}
