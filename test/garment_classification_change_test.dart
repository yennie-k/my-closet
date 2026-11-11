import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/garment_editor_screen.dart';
import 'package:my_closet/theme/app_theme.dart';
import 'package:my_closet/widgets/garment_edit_rules.dart';

import 'garment_compatibility_test.dart' show legacyMetadata;
import 'garment_input_ux_test.dart' show tap, type, expand;
import 'garment_category_ux_test.dart' show RecordingRevisionWardrobe;
import 'support/wardrobe_fakes.dart';

class CountingWardrobe extends MemoryWardrobe {
  int writes = 0;
  @override
  Future<void> save(Garment garment, {imageBytes}) async {
    writes++;
    await super.save(garment, imageBytes: imageBytes);
  }
}

Garment syntheticCoat({String subtype = '코트', String fit = 'A라인'}) =>
    Garment.fromJson({
      ...legacyMetadata(),
      'version': 2,
      'category': 'outerwear',
      'name': '합성 코트 - 실제 사용자 데이터 아님',
      'subtype': subtype,
      'fit': fit,
      'thicknessLevel': 4,
      'materials': ['울', '면 20% 혼방'],
    });

Finder field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);
String value(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(field(label)).controller!.text;

Future<void> openEditor(
  WidgetTester tester,
  MemoryWardrobe repo, {
  Garment? old,
  AppDesign design = AppDesign.minimal,
  double scale = 1,
}) async {
  if (old != null) await repo.save(old, imageBytes: testPhoto());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(design),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            child: const Text('합성 편집 열기'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => GarmentEditorScreen(
                  repository: repo,
                  photoService: FakePhotoService(),
                  garment: old,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tap(tester, find.text('합성 편집 열기'));
}

Future<void> category(WidgetTester tester, GarmentCategory category) async {
  await tap(tester, find.byKey(const ValueKey('category-field')));
  await tap(tester, find.text(category.label).last);
}

Future<void> accept(WidgetTester tester) =>
    tap(tester, find.byKey(const ValueKey('confirm-classification-change')));
Future<void> cancel(WidgetTester tester) =>
    tap(tester, find.byKey(const ValueKey('cancel-classification-change')));

void main() {
  test(
    'Transition rules retain only provably compatible subtype/fit values',
    () {
      final shoes = GarmentClassificationChange.category(
        target: GarmentCategory.shoes,
        subtype: '미디 원피스',
        fit: '레귤러핏',
      );
      expect(shoes.subtype, '');
      expect(shoes.fit, '');
      final pants = GarmentClassificationChange.category(
        target: GarmentCategory.bottoms,
        subtype: '코트',
        fit: '레귤러핏',
      );
      expect(pants.subtype, '');
      expect(pants.fit, '레귤러핏');
      final compatible = GarmentClassificationChange.category(
        target: GarmentCategory.shoes,
        subtype: '운동화',
        fit: '',
      );
      expect(compatible.needsReset, isFalse);
      final custom = GarmentClassificationChange.category(
        target: GarmentCategory.other,
        subtype: '나만의 종류',
        fit: '나만의 핏',
      );
      expect(custom.clearSubtype, isTrue);
      expect(custom.clearFit, isTrue);
      final puffer = GarmentClassificationChange.subtypeChange(
        category: GarmentCategory.outerwear,
        subtype: '패딩',
        fit: 'A라인',
      );
      expect(puffer.fit, '');
      expect(puffer.subtype, '패딩');
      expect(
        GarmentClassificationChange.subtypeChange(
          category: GarmentCategory.outerwear,
          subtype: '패딩',
          fit: '레귤러핏',
        ).needsReset,
        isFalse,
      );
    },
  );

  testWidgets(
    'New registration outerwear to shoes clears subtype and fit without dialog',
    (tester) async {
      final repo = CountingWardrobe();
      await openEditor(tester, repo);
      await type(tester, '의류 이름 *', '합성 신규 의류 이름 유지');
      await category(tester, GarmentCategory.outerwear);
      await tap(tester, find.widgetWithText(FilterChip, '코트'));
      await expand(tester, 'fit');
      await tap(tester, find.byKey(const ValueKey('fit-A라인')));
      await expand(tester, 'colors');
      await tap(tester, find.byKey(const ValueKey('primary-베이지')));
      await tap(tester, find.byKey(const ValueKey('additional-민트')));
      await tap(tester, find.text('봄'));
      await tap(tester, find.text('캐주얼'));
      await expand(tester, 'thickness');
      await tap(tester, find.byKey(const ValueKey('thickness-4')));
      await expand(tester, 'materials');
      await type(tester, '소재 직접 입력', '면 80% / 나일론 20%');
      await type(tester, '메모', '합성 테스트 메모도 유지');
      await category(tester, GarmentCategory.shoes);
      expect(find.byType(AlertDialog), findsNothing);
      expect(value(tester, '세부 종류 직접 입력'), '');
      expect(value(tester, '핏'), '');
      expect(value(tester, '의류 이름 *'), '합성 신규 의류 이름 유지');
      expect(value(tester, '대표 색상'), '베이지');
      expect(value(tester, '소재 직접 입력'), '면 80% / 나일론 20%');
      expect(value(tester, '메모'), '합성 테스트 메모도 유지');
      expect(repo.writes, 0);
      await category(tester, GarmentCategory.outerwear);
      expect(value(tester, '세부 종류 직접 입력'), '');
      expect(value(tester, '핏'), '');
      expect(find.widgetWithText(FilterChip, '코트'), findsOneWidget);
      await category(tester, GarmentCategory.shoes);
      await tap(tester, find.widgetWithText(FilterChip, '운동화'));
      await tap(tester, find.text('사진 선택'));
      await tap(tester, find.text('옷 저장하기'));
      final saved = repo.items.values.single;
      expect(saved.name, '합성 신규 의류 이름 유지');
      expect(saved.category, GarmentCategory.shoes);
      expect(saved.subtype, '운동화');
      expect(saved.fit, '');
      expect(saved.primaryColor, '베이지');
      expect(saved.additionalColors, ['민트']);
      expect(saved.materials, ['면 80% / 나일론 20%']);
      expect(saved.thicknessLevel, 4);
      expect(saved.seasons, [Season.spring]);
      expect(saved.styleTags, ['캐주얼']);
      expect(saved.notes, '합성 테스트 메모도 유지');
    },
  );

  testWidgets(
    'Edit category cancellation preserves category, pending custom text and all fields',
    (tester) async {
      final old = syntheticCoat(subtype: '나만의 코트', fit: '사용자 맞춤 핏');
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      final before = old.toJson(), photo = repo.photos[old.id];
      final writes = repo.writes;
      await tester.enterText(field('세부 종류 직접 입력'), '아직 적용하지 않은 직접 입력');
      await tester.pumpAndSettle();
      await category(tester, GarmentCategory.shoes);
      expect(find.text('카테고리를 변경할까요?'), findsOneWidget);
      await cancel(tester);
      expect(value(tester, '세부 종류 직접 입력'), '아직 적용하지 않은 직접 입력');
      expect(value(tester, '핏'), old.fit);
      expect(find.widgetWithText(FilterChip, '코트'), findsOneWidget);
      await category(
        tester,
        GarmentCategory.outerwear,
      ); // still current: no dialog
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.writes, writes);
      expect(repo.items[old.id]!.toJson(), before);
      expect(repo.photos[old.id], photo);
    },
  );

  for (final server in [false, true]) {
    testWidgets(
      '${server ? 'Server' : 'Local'} coat to skirt to shoes saves no hidden old classification',
      (tester) async {
        final old = syntheticCoat();
        final repo = server ? RecordingRevisionWardrobe() : CountingWardrobe();
        await openEditor(tester, repo, old: old);
        final photo = repo.photos[old.id];
        final before = old.toJson();
        await category(tester, GarmentCategory.bottoms);
        await accept(tester);
        expect(value(tester, '세부 종류 직접 입력'), '');
        expect(value(tester, '핏'), '');
        await tap(tester, find.widgetWithText(FilterChip, '미니스커트'));
        await expand(tester, 'fit');
        await tap(tester, find.byKey(const ValueKey('fit-H라인')));
        await category(tester, GarmentCategory.shoes);
        await accept(tester);
        expect(value(tester, '세부 종류 직접 입력'), '');
        expect(value(tester, '핏'), '');
        await tap(tester, find.widgetWithText(FilterChip, '운동화'));
        expect(repo.items[old.id]!.toJson(), before); // still no writes
        await tap(tester, find.text('옷 저장하기'));
        final saved = repo.items[old.id]!;
        expect(saved.category, GarmentCategory.shoes);
        expect(saved.subtype, '운동화');
        expect(saved.fit, '');
        expect(saved.toJson(), {
          ...before,
          'category': 'shoes',
          'subtype': '운동화',
          'fit': '',
          'updatedAt': saved.toJson()['updatedAt'],
        });
        expect(repo.photos[old.id], photo);
        if (repo is RecordingRevisionWardrobe) {
          expect(identical(repo.originalRead, old), isTrue);
        }
      },
    );
  }

  testWidgets(
    'Subtype chip change cancels atomically or clears only the incompatible fit',
    (tester) async {
      final old = syntheticCoat();
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      await tap(tester, find.widgetWithText(FilterChip, '패딩'));
      await cancel(tester);
      expect(value(tester, '세부 종류 직접 입력'), '코트');
      expect(value(tester, '핏'), 'A라인');
      await tap(tester, find.widgetWithText(FilterChip, '패딩'));
      await accept(tester);
      expect(value(tester, '세부 종류 직접 입력'), '패딩');
      expect(value(tester, '핏'), '');
      expect(repo.items[old.id]!.toJson(), old.toJson());
      await tap(tester, find.widgetWithText(FilterChip, '코트'));
      expect(value(tester, '핏'), ''); // no hidden per-category restore cache
    },
  );

  testWidgets(
    'Compatible fit survives subtype/category transition and other fields remain intact',
    (tester) async {
      final old = syntheticCoat(fit: '레귤러핏');
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      await tap(tester, find.widgetWithText(FilterChip, '패딩'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(value(tester, '핏'), '레귤러핏');
      await category(tester, GarmentCategory.bottoms);
      await accept(
        tester,
      ); // subtype only; regular fit is also meaningful for pants
      expect(value(tester, '핏'), '레귤러핏');
      await tap(tester, find.widgetWithText(FilterChip, '청바지'));
      await tap(tester, find.text('옷 저장하기'));
      final saved = repo.items[old.id]!;
      expect(saved.toJson(), {
        ...old.toJson(),
        'category': 'bottoms',
        'subtype': '청바지',
        'updatedAt': saved.toJson()['updatedAt'],
      });
    },
  );

  testWidgets(
    'Opening, cancelling and reopening custom legacy garment never alters stored original',
    (tester) async {
      final old = syntheticCoat(subtype: '사용자 제작 코트', fit: '나만의 핏');
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      final photo = repo.photos[old.id];
      final writes = repo.writes;
      expect(value(tester, '세부 종류 직접 입력'), old.subtype);
      expect(value(tester, '핏'), old.fit);
      await category(tester, GarmentCategory.bags);
      await accept(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('discard-changes')));
      expect(repo.items[old.id]!.toJson(), old.toJson());
      expect(repo.writes, writes);
      await tap(tester, find.text('합성 편집 열기'));
      expect(value(tester, '세부 종류 직접 입력'), old.subtype);
      expect(value(tester, '핏'), old.fit);
      expect(repo.photos[old.id], photo);
    },
  );

  testWidgets(
    'Save applies pending custom subtype, confirms fit reset, and can be cancelled safely',
    (tester) async {
      final old = syntheticCoat();
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      final beforeWrites = repo.writes;
      await tester.enterText(field('세부 종류 직접 입력'), '사용자 제작 패딩');
      await tester.pumpAndSettle();
      await tap(tester, find.text('옷 저장하기'));
      expect(find.text('세부 종류를 변경할까요?'), findsOneWidget);
      await cancel(tester);
      expect(repo.writes, beforeWrites);
      expect(value(tester, '핏'), 'A라인');
      expect(value(tester, '세부 종류 직접 입력'), '코트');
      await tester.enterText(field('세부 종류 직접 입력'), '사용자 제작 패딩');
      await tester.pumpAndSettle();
      await tap(tester, find.text('옷 저장하기'));
      await accept(tester);
      expect(repo.items[old.id]!.subtype, '사용자 제작 패딩');
      expect(repo.items[old.id]!.fit, '');
    },
  );

  testWidgets(
    'Foreign standard subtype cannot be newly applied under the wrong category',
    (tester) async {
      final repo = CountingWardrobe();
      await openEditor(tester, repo);
      await category(tester, GarmentCategory.shoes);
      await type(tester, '세부 종류 직접 입력', '미디 원피스');
      expect(find.textContaining('다른 카테고리의 추천 종류예요.'), findsOneWidget);
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.writes, 0);
      await type(tester, '세부 종류 직접 입력', '나만의 운동화');
      expect(find.textContaining('다른 카테고리의 추천 종류예요.'), findsNothing);
      expect(value(tester, '세부 종류 직접 입력'), '나만의 운동화');
    },
  );

  for (final design in AppDesign.values) {
    testWidgets(
      'Classification review fits mobile ${design.name} with long custom values',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final old = syntheticCoat(
          subtype: List.filled(20, '맞춤종류').join(),
          fit: List.filled(20, '맞춤핏').join(),
        );
        final repo = CountingWardrobe();
        await openEditor(tester, repo, old: old, design: design, scale: 1.5);
        await category(tester, GarmentCategory.accessories);
        await cancel(tester);
        expect(value(tester, '세부 종류 직접 입력'), old.subtype);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
