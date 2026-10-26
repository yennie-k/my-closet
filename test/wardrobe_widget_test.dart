import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/home_screen.dart';
import 'package:my_closet/screens/wardrobe_screen.dart';
import 'package:my_closet/theme/app_theme.dart';

import 'support/wardrobe_fakes.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeField(WidgetTester tester, String label, String value) async {
  final finder = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(360, 740), const Size(1440, 1000)]) {
    testWidgets(
      'Register photo, all info, edit and confirm delete at ${size.width}px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = MemoryWardrobe();
        final photos = FakePhotoService();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(AppDesign.lovely),
            home: Scaffold(
              body: WardrobeScreen(
                repository: repository,
                photoService: photos,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('첫 번째 옷을 등록해 보세요'), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('add-garment')));
        await tap(tester, find.text('옷 저장하기'));
        expect(find.byKey(const ValueKey('editor-error')), findsOneWidget);
        photos.fail = true;
        await tap(tester, find.text('사진 선택'));
        expect(find.text('손상된 사진이에요.'), findsOneWidget);
        photos.fail = false;
        photos.cancel = true;
        await tap(tester, find.text('사진 선택'));
        expect(find.text('사진 변경'), findsNothing);
        photos.cancel = false;
        await tap(tester, find.text('사진 선택'));
        expect(find.text('사진 변경'), findsOneWidget);
        await tap(tester, find.text('사진 삭제'));
        expect(find.text('사진 선택'), findsOneWidget);
        await tap(tester, find.text('사진 선택'));
        await typeField(tester, '의류 이름 *', '아이보리 셔츠');
        await tap(tester, find.byKey(const ValueKey('category-field')));
        await tap(tester, find.text('상의').last);
        await typeField(tester, '세부 종류', '셔츠');
        await typeField(tester, '대표 색상', '아이보리');
        await typeField(tester, '추가 색상', '블루, 그레이');
        await tap(tester, find.text('봄'));
        await tap(tester, find.text('가을'));
        await tap(
          tester,
          find.widgetWithText(DropdownButtonFormField<GarmentThickness>, '두께'),
        );
        await tap(tester, find.text('보통').last);
        await tap(tester, find.text('미니멀'));
        await typeField(tester, '소재', '면 100%');
        await typeField(tester, '핏', '레귤러핏');
        await typeField(tester, '메모', '출근할 때 입어요.');
        repository.failSave = true;
        await tap(tester, find.text('옷 저장하기'));
        expect(repository.items, isEmpty);
        expect(find.textContaining('저장 공간이 부족해요'), findsOneWidget);
        repository.failSave = false;
        await tap(tester, find.text('옷 저장하기'));
        final garment = repository.items.values.single;
        expect(garment.category, GarmentCategory.tops);
        expect(garment.additionalColors, ['블루', '그레이']);
        expect(garment.seasons, [Season.spring, Season.autumn]);
        expect(garment.thickness, GarmentThickness.medium);
        expect(garment.styleTags, ['미니멀']);
        expect(garment.notes, '출근할 때 입어요.');
        expect(repository.photos[garment.id], isNotEmpty);
        expect(find.text('전체 1벌'), findsOneWidget);
        await tap(tester, find.byKey(ValueKey('garment-${garment.id}')));
        expect(find.text('옷 상세 보기'), findsOneWidget);
        await tap(tester, find.text('정보 수정'));
        await typeField(tester, '의류 이름 *', '새 이름 셔츠');
        await tap(tester, find.text('사진 변경'));
        await tap(tester, find.text('옷 저장하기'));
        expect(find.text('새 이름 셔츠'), findsOneWidget);
        expect(repository.items[garment.id]!.createdAt, garment.createdAt);
        expect(
          repository.items[garment.id]!.updatedAt.isAfter(garment.updatedAt),
          isTrue,
        );
        await tap(tester, find.text('의류 삭제'));
        await tap(tester, find.text('취소'));
        expect(repository.items.length, 1);
        repository.failDelete = true;
        await tap(tester, find.text('의류 삭제'));
        await tap(tester, find.text('삭제하기'));
        expect(find.textContaining('삭제하지 못했어요'), findsOneWidget);
        expect(repository.items.length, 1);
        repository.failDelete = false;
        await tap(tester, find.text('의류 삭제'));
        await tap(tester, find.text('삭제하기'));
        expect(repository.items, isEmpty);
        expect(repository.photos, isEmpty);
        expect(find.text('전체 0벌'), findsOneWidget);
      },
    );
  }

  testWidgets('Category and search filter cards and can reset empty results', (
    tester,
  ) async {
    final repository = MemoryWardrobe();
    for (final garment in [
      testGarment(name: '흰 셔츠'),
      testGarment(name: '청바지', category: GarmentCategory.bottoms),
    ]) {
      await repository.save(garment, imageBytes: testPhoto());
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WardrobeScreen(
            repository: repository,
            photoService: FakePhotoService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ChoiceChip, '하의'));
    expect(find.text('검색 결과 1벌'), findsOneWidget);
    expect(find.text('흰 셔츠'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('garment-search')), '셔츠');
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 옷이 없어요'), findsOneWidget);
    await tap(tester, find.text('검색 조건 초기화'));
    expect(find.text('검색 결과 2벌'), findsOneWidget);
  });

  testWidgets('Home style profile uses full mobile content width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: HomeScreen(
              preferences: const UserPreferences(styles: fashionStyles),
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('style-profile-card'))).width,
      316,
    );
  });
}
