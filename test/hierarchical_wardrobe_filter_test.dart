import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/garment_options.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/models/wardrobe_filters.dart';
import 'package:my_closet/screens/wardrobe_screen.dart';
import 'package:my_closet/services/storage/indexeddb_wardrobe_repository.dart';
import 'package:my_closet/theme/app_theme.dart';

import 'support/wardrobe_fakes.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder category(GarmentCategory? value) =>
    find.byKey(ValueKey('category-filter-${value?.name ?? 'all'}'));
Finder subtype(String? value) => find.byKey(
  ValueKey(
    value == null ? 'subtype-filter-all' : 'subtype-filter-value:$value',
  ),
);

void main() {
  test('Three existing IndexedDB records and image bytes survive filtering and reopening', () async {
    final factory = newIdbFactoryMemory();
    final repository = IndexedDbWardrobeRepository(
      factory,
      databaseName: 'three_existing_clothes',
    );
    final clothes = [
      testGarment(subtype: '니트'),
      testGarment(category: GarmentCategory.bottoms, subtype: '내 소분류'),
      testGarment(category: GarmentCategory.outerwear),
    ];
    final originals = clothes.map((v) => v.toJson()).toList();
    final photo = testPhoto();
    for (final garment in clothes) {
      await repository.save(garment, imageBytes: photo);
    }
    final loaded = await repository.list();
    for (final category in GarmentCategory.values) {
      for (final subtype in <String?>[
        null,
        ...wardrobeSubtypes(loaded, category: category),
      ]) {
        filterWardrobeBySubtype(loaded, '', subtype, category: category);
      }
    }
    await repository.close();
    final reopened = IndexedDbWardrobeRepository(
      factory,
      databaseName: 'three_existing_clothes',
    );
    final restored = await reopened.list();
    expect(restored.length, 3);
    for (var i = 0; i < clothes.length; i++) {
      expect(
        restored.firstWhere((v) => v.id == clothes[i].id).toJson(),
        originals[i],
      );
      expect(await reopened.readImage(clothes[i].id), photo);
    }
    await reopened.close();
  });
  test('Default subtypes reuse registration options even with no clothes', () {
    for (final category in GarmentCategory.values) {
      expect(
        wardrobeSubtypes([], category: category),
        subtypeSuggestions[category],
      );
    }
  });
  test('Custom and unclassified subtypes belong only to their category and deduplicate', () {
    final garments = [
      testGarment(subtype: ' 니트 '),
      testGarment(subtype: '맞춤 상의'),
      testGarment(subtype: '맞춤 상의'),
      testGarment(subtype: ''),
      testGarment(category: GarmentCategory.bottoms, subtype: '맞춤 하의'),
    ];
    final tops = wardrobeSubtypes(garments, category: GarmentCategory.tops);
    expect(tops.where((v) => v == '니트').length, 1);
    expect(tops.where((v) => v == '맞춤 상의').length, 1);
    expect(tops, contains(''));
    expect(tops, isNot(contains('맞춤 하의')));
    expect(
      wardrobeSubtypes(garments, category: GarmentCategory.bottoms),
      isNot(contains('')),
    );
  });
  test('Category, subtype and name are all applied together', () {
    final garments = [
      testGarment(name: 'Blue 니트', subtype: '니트'),
      testGarment(name: 'White 니트', subtype: '니트'),
      testGarment(
        name: 'Blue 다른 옷',
        subtype: '니트',
        category: GarmentCategory.other,
      ),
    ];
    expect(
      filterWardrobeBySubtype(
        garments,
        ' blue ',
        '니트',
        category: GarmentCategory.tops,
      ).single.name,
      'Blue 니트',
    );
    expect(
      filterWardrobeBySubtype(
        garments,
        '',
        null,
        category: GarmentCategory.tops,
      ).length,
      2,
    );
    expect(filterWardrobeBySubtype(garments, '', null).length, 3);
  });
  for (final size in [const Size(360, 740), const Size(1440, 1000)]) {
    testWidgets(
      'All categories including empty ones and shared subtype defaults at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(AppDesign.minimal),
            home: Scaffold(
              body: WardrobeScreen(
                repository: MemoryWardrobe(),
                photoService: FakePhotoService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('subcategory-section')), findsNothing);
        for (final value in GarmentCategory.values) {
          expect(category(value), findsOneWidget);
          await tap(tester, category(value));
          expect(find.text('아직 등록된 옷이 없어요'), findsOneWidget);
          expect(find.text('검색 결과 0벌'), findsOneWidget);
          expect(tester.widget<ChoiceChip>(subtype(null)).selected, isTrue);
          for (final option in subtypeSuggestions[value]!) {
            expect(subtype(option), findsOneWidget);
          }
        }
        await tap(tester, category(null));
        expect(find.byKey(const ValueKey('subcategory-section')), findsNothing);
        if (size.width < 900) {
          expect(
            tester
                .widget<SingleChildScrollView>(
                  find.byKey(const ValueKey('category-filter-scroll')),
                )
                .scrollDirection,
            Axis.horizontal,
          );
        } else {
          expect(
            find.byKey(const ValueKey('category-filter-wrap')),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final design in AppDesign.values) {
    testWidgets(
      'Switching category resets subtype, keeps query and preserves three clothes/photos (${design.name})',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = MemoryWardrobe();
        final clothes = [
          testGarment(name: 'Blue 니트', subtype: '니트'),
          testGarment(
            name: 'Blue 맞춤 하의',
            category: GarmentCategory.bottoms,
            subtype: '직접 만든 종류',
          ),
          testGarment(name: '옛날 옷', category: GarmentCategory.outerwear),
        ];
        final snapshots = clothes.map((v) => v.toJson()).toList();
        final bytes = testPhoto();
        for (final garment in clothes) {
          await repository.save(garment, imageBytes: bytes);
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(design),
            home: Scaffold(
              body: WardrobeScreen(
                repository: repository,
                photoService: FakePhotoService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('검색 결과 3벌'), findsOneWidget);
        await tap(tester, category(GarmentCategory.tops));
        await tap(tester, subtype('니트'));
        await tester.enterText(
          find.byKey(const ValueKey('garment-search')),
          'Blue',
        );
        await tester.pumpAndSettle();
        expect(find.text('검색 결과 1벌'), findsOneWidget);
        await tap(tester, category(GarmentCategory.bottoms));
        expect(tester.widget<ChoiceChip>(subtype(null)).selected, isTrue);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('garment-search')))
              .controller!
              .text,
          'Blue',
        );
        await tap(tester, subtype('직접 만든 종류'));
        expect(find.text('검색 결과 1벌'), findsOneWidget);
        await tap(tester, subtype('청바지'));
        expect(find.text('아직 등록된 옷이 없어요'), findsOneWidget);
        await tap(tester, category(GarmentCategory.outerwear));
        await tap(tester, subtype(''));
        await tester.enterText(
          find.byKey(const ValueKey('garment-search')),
          '',
        );
        await tester.pumpAndSettle();
        expect(find.text('검색 결과 1벌'), findsOneWidget);
        expect(
          tester
              .widget<SingleChildScrollView>(
                find.byKey(const ValueKey('subtype-filter-scroll')),
              )
              .scrollDirection,
          Axis.horizontal,
        );
        await tap(tester, category(null));
        expect(find.text('검색 결과 3벌'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        final restored = await repository.list();
        expect(restored.length, 3);
        for (var i = 0; i < clothes.length; i++) {
          expect(
            restored.firstWhere((v) => v.id == clothes[i].id).toJson(),
            snapshots[i],
          );
          expect(await repository.readImage(clothes[i].id), bytes);
        }
        await repository.close();
      },
    );
  }
}
