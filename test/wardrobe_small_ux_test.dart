import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/garment_options.dart';
import 'package:my_closet/models/wardrobe_filters.dart';
import 'package:my_closet/screens/garment_editor_screen.dart';
import 'package:my_closet/screens/wardrobe_screen.dart';

import 'support/wardrobe_fakes.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder chip(String value) => find.widgetWithText(ChoiceChip, value);

void main() {
  test(
    'Subtype filters deduplicate custom values and distinguish reserved labels',
    () {
      final items = [
        testGarment(subtype: '니트'),
        testGarment(subtype: ' 니트 '),
        testGarment(subtype: '직접 만든 종류'),
        testGarment(subtype: ''),
        testGarment(subtype: '   '),
        testGarment(subtype: '미분류'),
        testGarment(subtype: '전체'),
      ];
      final before = items.map((v) => v.toJson()).toList();
      expect(wardrobeSubtypes(items), ['니트', '직접 만든 종류', '미분류', '전체', '']);
      expect(filterWardrobeBySubtype(items, '', '').length, 2);
      expect(filterWardrobeBySubtype(items, '', '미분류').length, 1);
      expect(subtypeFilterLabel('미분류'), '미분류 (직접 입력)');
      expect(filterWardrobeBySubtype(items, '', null).length, items.length);
      expect(items.map((v) => v.toJson()).toList(), before);
    },
  );
  test(
    'Custom subtype and name search work together without changing metadata',
    () {
      final items = [
        testGarment(name: 'Blue 여름옷', subtype: '내가 만든 종류'),
        testGarment(name: 'Blue 코트', subtype: '코트'),
        testGarment(name: '겨울옷', subtype: '내가 만든 종류'),
      ];
      expect(
        filterWardrobeBySubtype(items, ' blue ', '내가 만든 종류').single.name,
        'Blue 여름옷',
      );
      expect(filterWardrobeBySubtype(items, '코트', '내가 만든 종류'), isEmpty);
      expect(wardrobeSubtypes(items), ['내가 만든 종류', '코트']);
    },
  );
  test(
    'Fits and body-part descriptions are appropriate to garment context',
    () {
      final tops = fitsForCategory(GarmentCategory.tops);
      expect(tops.map((v) => v.name), ['슬림핏', '레귤러핏', '오버핏', '루즈핏']);
      expect(
        tops.any(
          (v) => v.description.contains('다리') || v.description.contains('발목'),
        ),
        isFalse,
      );
      final pants = fitsForCategory(GarmentCategory.bottoms, subtype: '청바지');
      expect(pants.take(4).map((v) => v.name), [
        '와이드핏',
        '스트레이트핏',
        '테이퍼드핏',
        '스키니핏',
      ]);
      expect(pants.any((v) => v.description.contains('어깨')), isFalse);
      for (final subtype in ['미니스커트', '내가 만든 주름치마']) {
        final skirts = fitsForCategory(
          GarmentCategory.bottoms,
          subtype: subtype,
        );
        expect(skirts.map((v) => v.name), ['A라인', 'H라인']);
        expect(skirts.every((v) => v.description.contains('스커트')), isTrue);
      }
      expect(
        fitsForCategory(
          GarmentCategory.dresses,
          subtype: '롱 원피스',
        ).every((v) => v.description.contains('원피스')),
        isTrue,
      );
      expect(
        fitsForCategory(
          GarmentCategory.dresses,
          subtype: '점프수트',
        ).any((v) => v.name == 'A라인'),
        isFalse,
      );
      for (final category in [
        GarmentCategory.shoes,
        GarmentCategory.bags,
        GarmentCategory.accessories,
        GarmentCategory.other,
      ]) {
        expect(fitsForCategory(category), isEmpty);
      }
    },
  );
  for (final size in [const Size(360, 740), const Size(1440, 1000)]) {
    testWidgets(
      'Subtype filters combine with search and refresh after edit/delete at ${size.width}px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = MemoryWardrobe();
        final knit = testGarment(name: '따뜻한 니트', subtype: '니트');
        final coat = testGarment(
          name: '롱 코트',
          subtype: '코트',
          category: GarmentCategory.outerwear,
        );
        for (final garment in [knit, coat, testGarment(name: '옛날 옷')]) {
          await repo.save(garment, imageBytes: testPhoto());
        }
        final originalPhoto = repo.photos[knit.id];
        final originalMetadata = knit.toJson();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WardrobeScreen(
                repository: repo,
                photoService: FakePhotoService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(chip('상의'), findsOneWidget);
        expect(find.byKey(const ValueKey('subcategory-section')), findsNothing);
        await tap(tester, find.byKey(const ValueKey('category-filter-tops')));
        expect(chip('니트'), findsOneWidget);
        expect(chip('미분류'), findsOneWidget);
        await tap(tester, chip('미분류'));
        expect(find.text('검색 결과 1벌'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('garment-search')),
          '옛날',
        );
        await tester.pumpAndSettle();
        expect(find.text('검색 결과 1벌'), findsOneWidget);
        expect(
          chip('니트'),
          findsOneWidget,
        ); // Search does not shrink available filters.
        await tester.enterText(
          find.byKey(const ValueKey('garment-search')),
          '없음',
        );
        await tester.pumpAndSettle();
        expect(find.text('아직 등록된 옷이 없어요'), findsOneWidget);
        await tap(tester, find.text('검색 조건 초기화'));
        await tap(
          tester,
          find.byKey(const ValueKey('category-filter-outerwear')),
        );
        await tap(tester, chip('코트'));
        await tap(tester, find.byKey(ValueKey('garment-${coat.id}')));
        await tap(tester, find.text('정보 수정'));
        final subtype = find.widgetWithText(TextFormField, '세부 종류 직접 입력');
        await tester.ensureVisible(subtype);
        await tester.enterText(subtype, '내 레인코트');
        await tester.pumpAndSettle();
        await tap(tester, find.text('옷 저장하기'));
        await tap(tester, find.byType(BackButton));
        expect(
          chip('코트'),
          findsOneWidget,
        ); // Default recommendations remain with zero garments.
        expect(chip('내 레인코트'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(chip('코트')).selected, isTrue);
        await tap(tester, chip('내 레인코트'));
        await tap(tester, find.byKey(ValueKey('garment-${coat.id}')));
        await tap(tester, find.text('의류 삭제'));
        await tap(tester, find.text('삭제하기'));
        expect(chip('내 레인코트'), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('subtype-filter-all')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('category-filter-outerwear')),
              )
              .selected,
          isTrue,
        );
        expect(repo.items[knit.id]!.toJson(), originalMetadata);
        expect(repo.photos[knit.id], originalPhoto);
      },
    );
  }
  testWidgets(
    'Mobile subtype filters scroll horizontally when many kinds exist',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = MemoryWardrobe();
      for (var i = 0; i < 15; i++) {
        await repo.save(
          testGarment(name: '의류 $i', subtype: '사용자 종류 $i'),
          imageBytes: testPhoto(),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WardrobeScreen(
              repository: repo,
              photoService: FakePhotoService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('category-filter-tops')));
      final scroll = find.byKey(const ValueKey('subtype-filter-scroll'));
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      await tester.drag(scroll, const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tap(tester, chip('사용자 종류 14'));
      expect(find.text('검색 결과 1벌'), findsOneWidget);
    },
  );
  testWidgets(
    'New palette colors save primary and extras with exact HEX and preserve photo',
    (tester) async {
      final repo = MemoryWardrobe();
      final garment = testGarment();
      await repo.save(garment, imageBytes: testPhoto());
      final originalPhoto = repo.photos[garment.id];
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditorScreen(
            repository: repo,
            photoService: FakePhotoService(),
            garment: garment,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        find
            .descendant(
              of: find.byKey(const PageStorageKey('section-colors')),
              matching: find.byType(ListTile),
            )
            .first,
      );
      for (final name in ['카키', '카멜', '민트']) {
        await tap(tester, find.byKey(ValueKey('primary-$name')));
      }
      await tap(tester, find.byKey(const ValueKey('additional-카키')));
      await tap(tester, find.byKey(const ValueKey('additional-카멜')));
      await tap(tester, find.text('옷 저장하기'));
      final saved = repo.items[garment.id]!;
      expect(saved.primaryColor, '민트');
      expect(saved.additionalColors, ['카키', '카멜']);
      expect(saved.toJson()['primaryColorHex'], '#A6D9C5');
      expect(saved.toJson()['additionalColorDetails'], [
        {'name': '카키', 'hex': '#77794A'},
        {'name': '카멜', 'hex': '#BF8A55'},
      ]);
      expect(repo.photos[garment.id], originalPhoto);
      expect(Garment.fromJson(saved.toJson()).toJson(), saved.toJson());
    },
  );
  testWidgets(
    'Changing subtype and category confirms clearing incompatible custom fit drafts',
    (tester) async {
      final garment = Garment.fromJson({
        ...testGarment(
          category: GarmentCategory.bottoms,
          subtype: '청바지',
        ).toJson(),
        'fit': '기존 맞춤 핏',
      });
      final repo = MemoryWardrobe();
      await repo.save(garment, imageBytes: testPhoto());
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditorScreen(
            repository: repo,
            photoService: FakePhotoService(),
            garment: garment,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        find
            .descendant(
              of: find.byKey(const PageStorageKey('section-fit')),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(find.byKey(const ValueKey('fit-스키니핏')), findsOneWidget);
      final subtype = find.widgetWithText(TextFormField, '세부 종류 직접 입력');
      await tester.ensureVisible(subtype);
      await tester.enterText(subtype, '미니스커트');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('apply-subtype')));
      await tap(
        tester,
        find.byKey(const ValueKey('confirm-classification-change')),
      );
      expect(find.byKey(const ValueKey('fit-스키니핏')), findsNothing);
      expect(find.byKey(const ValueKey('fit-A라인')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('category-field')));
      await tap(tester, find.text('신발').last);
      await tap(
        tester,
        find.byKey(const ValueKey('confirm-classification-change')),
      );
      expect(find.byKey(const ValueKey('fit-A라인')), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '핏'))
            .controller!
            .text,
        '',
      );
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items[garment.id]!.fit, '');
      expect(repo.items[garment.id]!.subtype, '');
    },
  );
}
