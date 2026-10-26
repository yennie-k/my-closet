import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';

import 'support/wardrobe_fakes.dart';

void main() {
  test('All outfit attributes round trip without losing dates or labels', () {
    final now = DateTime.utc(2026, 10, 26);
    final garment = Garment(
      id: Garment.newId(),
      name: '셔츠',
      category: GarmentCategory.tops,
      createdAt: now,
      updatedAt: now,
      subtype: '셔츠',
      primaryColor: '아이보리',
      additionalColors: ['블루'],
      seasons: [Season.spring, Season.autumn],
      thickness: GarmentThickness.medium,
      styleTags: ['미니멀', '캐주얼'],
      material: '면',
      fit: '레귤러',
      notes: '첫 옷',
      imageWidth: 800,
      imageHeight: 1000,
    );
    expect(Garment.fromJson(garment.toJson()).toJson(), garment.toJson());
    expect(Garment.newId(), isNot(garment.id));
  });
  test('Category and case insensitive name search combine with each other', () {
    final items = [
      testGarment(name: 'Blue 셔츠'),
      testGarment(name: 'Blue 데님', category: GarmentCategory.bottoms),
      testGarment(name: '코튼 셔츠'),
    ];
    expect(filterGarments(items, ' blue ', null).length, 2);
    expect(
      filterGarments(items, 'BLUE', GarmentCategory.tops).single.name,
      'Blue 셔츠',
    );
    expect(filterGarments(items, '없음', null), isEmpty);
  });
}
