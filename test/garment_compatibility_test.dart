import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/garment_options.dart';
import 'package:my_closet/services/storage/indexeddb_wardrobe_repository.dart';

import 'support/wardrobe_fakes.dart';

Map<String, Object?> legacyMetadata() => {
  'version': 1,
  'id': 'legacy-shirt',
  'name': '기존 옷',
  'category': 'tops',
  'createdAt': '2026-10-01T03:00:00.000Z',
  'updatedAt': '2026-10-02T03:00:00.000Z',
  'subtype': '직접 만든 셔츠',
  'primaryColor': '차콜빛 민트',
  'additionalColors': ['연보라'],
  'seasons': ['spring', 'autumn'],
  'thickness': 'thin',
  'styleTags': ['캐주얼'],
  'material': '면 70% / 폴리에스터 30%',
  'fit': '나만의 여유핏',
  'notes': '기존 메모',
  'imageMimeType': 'image/jpeg',
  'imageWidth': 8,
  'imageHeight': 8,
};

void main() {
  test('Legacy custom text, ID, timestamps and mixed material survive in-memory upgrade', () {
    final raw = legacyMetadata();
    final garment = Garment.fromJson(raw);
    expect(garment.material, raw['material']);
    expect(garment.materials, [raw['material']]);
    expect(garment.subtype, raw['subtype']);
    expect(garment.primaryColor, raw['primaryColor']);
    expect(garment.additionalColors, raw['additionalColors']);
    expect(garment.fit, raw['fit']);
    final upgraded = garment.toJson();
    expect(upgraded['id'], raw['id']);
    expect(upgraded['createdAt'], raw['createdAt']);
    expect(upgraded['updatedAt'], raw['updatedAt']);
    expect(upgraded['version'], 2);
    expect(upgraded['primaryColorHex'], isNull);
    expect(Garment.fromJson(upgraded).toJson(), upgraded);
    expect(raw['version'], 1);
  });
  test(
    'Legacy thin, medium and thick map to 2, 3, 4; five levels round trip',
    () {
      for (final entry in {'thin': 2, 'medium': 3, 'thick': 4}.entries) {
        expect(
          Garment.fromJson({...legacyMetadata(), 'thickness': entry.key})
              .thicknessLevel,
          entry.value,
        );
      }
      for (var level = 1; level <= 5; level++) {
        final garment = Garment.fromJson({
          ...legacyMetadata(),
          'version': 2,
          'thicknessLevel': level,
        });
        expect(garment.thicknessLevel, level);
        expect(garment.toJson()['thicknessLevel'], level);
      }
      expect(
        () => Garment.fromJson({...legacyMetadata(), 'thicknessLevel': 9}),
        throwsFormatException,
      );
    },
  );
  test('Standard colors have stable HEX and custom names stay intact', () {
    expect(garmentColors.length, 18);
    final garment = Garment.fromJson({
      ...legacyMetadata(),
      'primaryColor': '블랙',
      'additionalColors': ['아이보리', '커스텀 색'],
    });
    expect(garment.toJson()['primaryColorHex'], '#202020');
    expect(garment.toJson()['additionalColorDetails'], [
      {'name': '아이보리', 'hex': '#F4EEDC'},
      {'name': '커스텀 색', 'hex': null},
    ]);
    expect(sameColorName(' 차콜 ', '차콜'), isTrue);
  });
  test('Multi material list is authoritative while the original string is preserved', () {
    final garment = Garment.fromJson({
      ...legacyMetadata(),
      'version': 2,
      'materials': ['울', '면 70% / 폴리에스터 30%'],
    });
    expect(garment.materials.length, 2);
    expect(garment.material, '면 70% / 폴리에스터 30%');
    expect(
      Garment.fromJson({...garment.toJson(), 'materials': []}).materials,
      isEmpty,
    );
  });
  test('Reading v1 and failed migration never rewrite IndexedDB metadata or photos', () async {
    final factory = newIdbFactoryMemory();
    final repository = IndexedDbWardrobeRepository(factory);
    await repository.list();
    final db = await factory.open('my_closet_wardrobe_v1');
    final original = legacyMetadata();
    final photo = testPhoto();
    var tx = db.transactionList(['garments', 'photos'], idbModeReadWrite);
    await tx.objectStore('garments').put(original, original['id']);
    await tx.objectStore('photos').put(photo, original['id']);
    await tx.completed;
    final garment = (await repository.list()).single;
    expect(garment.thicknessLevel, 2);
    expect(await repository.readImage(garment.id), photo);
    tx = db.transaction('garments', idbModeReadOnly);
    expect(await tx.objectStore('garments').getObject(garment.id), original);
    await tx.completed;
    final bad = {...original, 'version': 99};
    tx = db.transaction('garments', idbModeReadWrite);
    await tx.objectStore('garments').put(bad, garment.id);
    await tx.completed;
    await expectLater(repository.list(), throwsA(isA<Exception>()));
    tx = db.transaction('garments', idbModeReadOnly);
    expect(await tx.objectStore('garments').getObject(garment.id), bad);
    await tx.completed;
    expect(await repository.readImage(garment.id), photo);
    db.close();
    await repository.close();
  });
  test('Category suggestions and prioritized fits cover requested options', () {
    expect(subtypeSuggestions[GarmentCategory.tops], contains('폴로셔츠'));
    expect(subtypeSuggestions[GarmentCategory.accessories], contains('머플러'));
    expect(fitsForCategory(GarmentCategory.bottoms).first.name, '와이드핏');
    expect(fitsForCategory(GarmentCategory.dresses).first.name, 'A라인');
    expect(materialOptions.length, 18);
  });
}
