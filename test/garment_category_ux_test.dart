import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/garment_options.dart';
import 'package:my_closet/models/server_garment_record.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/services/storage/indexeddb_wardrobe_repository.dart';
import 'package:my_closet/theme/app_theme.dart';
import 'package:my_closet/widgets/garment_illustrations.dart';
import 'package:my_closet/widgets/garment_input_fields.dart';

import 'garment_compatibility_test.dart' show legacyMetadata;
import 'garment_input_ux_test.dart' show tap, type, expand, pumpEditor;
import 'server_wardrobe_test.dart' show RevisionFake;
import 'support/wardrobe_fakes.dart';

class RecordingRevisionWardrobe extends RevisionFake {
  Garment? originalRead;
  @override
  Future<Garment> saveWithOriginal(Garment garment, {Garment? original}) {
    originalRead = original;
    return super.saveWithOriginal(garment, original: original);
  }
}

Future<void> chooseCategory(
  WidgetTester tester,
  GarmentCategory category,
) async {
  await tap(tester, find.byKey(const ValueKey('category-field')));
  await tap(tester, find.text(category.label).last);
  final confirm = find.byKey(const ValueKey('confirm-classification-change'));
  if (confirm.evaluate().isNotEmpty) await tap(tester, confirm);
}

void main() {
  test(
    'Every built-in subtype has a suitable fit context without mutating data',
    () {
      for (final entry in subtypeSuggestions.entries) {
        for (final subtype in entry.value) {
          final options = fitsForCategory(entry.key, subtype: subtype);
          expect(options.map((e) => e.name).toSet().length, options.length);
          if ([
            GarmentCategory.shoes,
            GarmentCategory.bags,
            GarmentCategory.accessories,
          ].contains(entry.key)) {
            expect(options, isEmpty);
          } else {
            expect(options, isNotEmpty, reason: '${entry.key}: $subtype');
          }
          if (entry.key == GarmentCategory.outerwear) {
            expect(fitContextFor(entry.key, subtype), isNot(FitContext.tops));
            expect(options.any((e) => e.description.contains('상의')), isFalse);
          }
        }
      }
      expect(
        fitContextFor(GarmentCategory.outerwear, '직접 만든 울 코트'),
        FitContext.coat,
      );
      expect(
        fitContextFor(GarmentCategory.outerwear, '사용자 제작 외투'),
        FitContext.outerwear,
      );
      expect(
        subtypeBelongsToOtherCategory(GarmentCategory.outerwear, '청바지'),
        isTrue,
      );
      expect(
        subtypeBelongsToOtherCategory(GarmentCategory.outerwear, '사용자 외투'),
        isFalse,
      );
    },
  );

  test(
    'Outerwear, shorts, leggings and joggers use meaningful fits and wording',
    () {
      for (final subtype in ['코트', '트렌치코트']) {
        expect(
          fitsForCategory(
            GarmentCategory.outerwear,
            subtype: subtype,
          ).map((e) => e.name),
          containsAll(['레귤러핏', '오버핏', 'A라인', 'H라인']),
        );
      }
      final puffer = fitsForCategory(
        GarmentCategory.outerwear,
        subtype: '경량 패딩',
      );
      expect(
        fitsForCategory(GarmentCategory.tops, subtype: '민소매').any(
          (e) => e.description.contains('소매가') || e.description.contains('소매의'),
        ),
        isFalse,
      );
      expect(puffer.map((e) => e.name), ['레귤러핏', '오버핏', '루즈핏']);
      expect(puffer.every((e) => e.description.contains('경량 패딩')), isTrue);
      for (final subtype in ['재킷', '블레이저', '바람막이', '플리스', '점퍼']) {
        expect(
          fitsForCategory(
            GarmentCategory.outerwear,
            subtype: subtype,
          ).every((e) => e.description.contains(subtype)),
          isTrue,
        );
      }
      final shorts = fitsForCategory(GarmentCategory.bottoms, subtype: '반바지');
      expect(shorts.any((e) => e.description.contains('발목')), isFalse);
      expect(shorts.every((e) => e.description.contains('반바지')), isTrue);
      expect(
        fitsForCategory(GarmentCategory.bottoms, subtype: '레깅스').single.name,
        '스키니핏',
      );
      expect(
        fitsForCategory(GarmentCategory.bottoms, subtype: '조거팬츠').first.name,
        '테이퍼드핏',
      );
      expect(needsFitReview(GarmentCategory.tops, '셔츠', '스키니핏'), isTrue);
      expect(needsFitReview(GarmentCategory.tops, '셔츠', '나만의 핏'), isTrue);
      expect(needsFitReview(GarmentCategory.outerwear, '코트', 'A라인'), isFalse);
      expect(needsFitReview(GarmentCategory.shoes, '로퍼', ''), isFalse);
    },
  );

  test('Optional thickness wording does not confuse shoes or bags with clothing warmth', () {
    for (final category in [
      GarmentCategory.shoes,
      GarmentCategory.bags,
      GarmentCategory.accessories,
      GarmentCategory.other,
    ]) {
      for (final thickness in GarmentThickness.values) {
        expect(thicknessExample(thickness, category), isNot(contains('티셔츠')));
        expect(thicknessExample(thickness, category), contains('재질'));
      }
    }
    expect(
      thicknessExample(GarmentThickness.thick, GarmentCategory.outerwear),
      contains('코트'),
    );
    expect(
      thicknessExample(GarmentThickness.thin, GarmentCategory.bottoms),
      isNot(contains('티셔츠')),
    );
    expect(
      thicknessExample(GarmentThickness.veryThick, GarmentCategory.tops),
      isNot(contains('패딩')),
    );
    expect(
      thicknessExample(GarmentThickness.medium, GarmentCategory.dresses),
      contains('원피스'),
    );
  });

  testWidgets(
    'Actual editor updates labels, descriptions and painter subtype together',
    (tester) async {
      await pumpEditor(tester, MemoryWardrobe(), testGarment(subtype: '셔츠'));
      await expand(tester, 'fit');
      Future<void> expectContext(
        GarmentCategory category,
        String subtype,
        String label,
      ) async {
        await chooseCategory(tester, category);
        await type(tester, '세부 종류 직접 입력', subtype);
        expect(find.text('$label 기준 실루엣 · 참고 일러스트'), findsOneWidget);
        final paints = tester.widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is FitSilhouettePainter,
          ),
        );
        expect(paints, isNotEmpty);
        for (final paint in paints) {
          final painter = paint.painter! as FitSilhouettePainter;
          expect(painter.category, category);
          expect(painter.subtype, subtype);
        }
        expect(tester.takeException(), isNull);
      }

      await expectContext(GarmentCategory.tops, '반팔 티셔츠', '상의');
      await expectContext(GarmentCategory.bottoms, '청바지', '바지');
      await expectContext(GarmentCategory.bottoms, '미니스커트', '스커트');
      await expectContext(GarmentCategory.bottoms, '반바지', '반바지');
      await expectContext(GarmentCategory.outerwear, '코트', '코트');
      expect(find.textContaining('상의 기준 실루엣'), findsNothing);
      await expectContext(GarmentCategory.outerwear, '경량 패딩', '경량 패딩');
      expect(find.byKey(const ValueKey('fit-A라인')), findsNothing);
      await expectContext(GarmentCategory.outerwear, '재킷', '재킷');
      await expectContext(GarmentCategory.outerwear, '바람막이', '바람막이');
      await expectContext(GarmentCategory.dresses, '롱 원피스', '원피스');
      await expectContext(GarmentCategory.dresses, '점프수트', '점프수트');
      await expectContext(GarmentCategory.dresses, '투피스 세트', '세트');
      expect(find.textContaining('구성품마다 핏이 다르면'), findsOneWidget);
    },
  );

  for (final category in [
    GarmentCategory.shoes,
    GarmentCategory.bags,
    GarmentCategory.accessories,
    GarmentCategory.other,
  ]) {
    testWidgets('${category.name} does not require a clothing fit', (
      tester,
    ) async {
      final repo = RevisionFake();
      await pumpEditor(tester, repo, testGarment());
      await expand(tester, 'fit');
      await chooseCategory(tester, category);
      expect(find.text('이 카테고리는 핏 추천을 생략해요. 입력하지 않아도 괜찮아요.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is FitSilhouettePainter,
        ),
        findsNothing,
      );
      await tap(tester, find.text('옷 저장하기'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.items.values.single.fit, isEmpty);
    });
  }

  testWidgets(
    'Confirmed category change clears incompatible fit before saving and preserves original until save',
    (tester) async {
      final old = Garment.fromJson({
        ...testGarment(
          category: GarmentCategory.bottoms,
          subtype: '청바지',
        ).toJson(),
        'fit': '스키니핏',
      });
      final repo = MemoryWardrobe();
      await pumpEditor(tester, repo, old);
      final before = old.toJson();
      final photo = repo.photos[old.id];
      await chooseCategory(tester, GarmentCategory.outerwear);
      expect(repo.items[old.id]!.toJson(), before);
      await type(tester, '세부 종류 직접 입력', '코트');
      await expand(tester, 'fit');
      expect(find.byKey(const ValueKey('fit-review-notice')), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, '핏'))
            .controller!
            .text,
        '',
      );
      expect(repo.items[old.id]!.toJson(), before);
      await tap(tester, find.byKey(const ValueKey('fit-레귤러핏')));
      expect(find.byKey(const ValueKey('fit-review-notice')), findsNothing);
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items[old.id]!.fit, '레귤러핏');
      expect(repo.items[old.id]!.category, GarmentCategory.outerwear);
      expect(repo.photos[old.id], photo);
    },
  );

  testWidgets(
    'Server edit explicitly preserves custom fit and passes the original revision identity',
    (tester) async {
      final old = Garment.fromJson({
        ...legacyMetadata(),
        'version': 2,
        'thicknessLevel': 4,
        'category': 'outerwear',
        'subtype': '나만의 코트',
        'materials': ['울', '면 20% 혼방'],
      });
      final repo = RecordingRevisionWardrobe();
      await pumpEditor(tester, repo, old);
      final photo = repo.photos[old.id];
      await type(tester, '의류 이름 *', '내 코트 이름 수정');
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.attempts, isEmpty);
      await tap(tester, find.byKey(const ValueKey('keep-custom-fit')));
      expect(repo.attempts.length, 1);
      expect(identical(repo.originalRead, old), isTrue);
      final saved = repo.items[old.id]!;
      expect(saved.fit, old.fit);
      expect(saved.subtype, old.subtype);
      expect(saved.id, old.id);
      expect(saved.createdAt, old.createdAt);
      expect(saved.materials, old.materials);
      expect(saved.material, old.material);
      expect(saved.additionalColors, old.additionalColors);
      expect(saved.seasons, old.seasons);
      expect(saved.styleTags, old.styleTags);
      expect(saved.thicknessLevel, 4);
      expect(repo.photos[old.id], photo);
      final row = {
        ...ServerGarmentRecord.insert(saved, 'synthetic-user'),
        'id': 'synthetic-server-id',
        'revision': 9,
      };
      final record = ServerGarmentRecord(row);
      expect(record.garment.toJson(), saved.toJson());
      final update = ServerGarmentRecord.metadata(saved, original: record);
      expect(update['fit'], old.fit);
      expect(update.containsKey('revision'), isFalse);
      expect(update.containsKey('photo_state'), isFalse);
    },
  );

  test('IndexedDB in-memory edit and reopen preserves custom values and photo bytes', () async {
    final factory = newIdbFactoryMemory();
    final repo = IndexedDbWardrobeRepository(factory);
    final old = Garment.fromJson(legacyMetadata());
    final photo = testPhoto();
    await repo.save(old, imageBytes: photo);
    final read = (await repo.list()).single;
    final edited = Garment.fromJson({
      ...read.toJson(),
      'name': '기존 맞춤 옷 수정',
      'updatedAt': '2026-11-09T01:00:00.000Z',
    });
    await repo.save(edited);
    final saved = (await repo.list()).single;
    expect(saved.fit, old.fit);
    expect(saved.subtype, old.subtype);
    expect(saved.createdAt, old.createdAt);
    expect(saved.materials, old.materials);
    expect(await repo.readImage(old.id), photo);
    await repo.close();
    final reopened = IndexedDbWardrobeRepository(factory);
    expect((await reopened.list()).single.toJson(), saved.toJson());
    expect(await reopened.readImage(old.id), photo);
    await reopened.close();
  });

  testWidgets(
    'Unchanged nonrecommended legacy fit performs no write or confirmation',
    (tester) async {
      final repo = RecordingRevisionWardrobe();
      final old = Garment.fromJson(legacyMetadata());
      await pumpEditor(tester, repo, old);
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.attempts, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.items[old.id]!.toJson(), old.toJson());
    },
  );

  testWidgets(
    'Custom outlines distinguish outerwear, dresses, sets and jumpsuits',
    (tester) async {
      Future<List<int>> pixels(GarmentCategory category, String subtype) async {
        final recorder = ui.PictureRecorder();
        final painter = FitSilhouettePainter(
          '레귤러핏',
          category,
          Colors.black,
          subtype: subtype,
        );
        painter.paint(Canvas(recorder), const Size(100, 110));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 110);
        final bytes = await image.toByteData();
        final result = bytes!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return result;
      }

      final top = await tester.runAsync(
        () => pixels(GarmentCategory.tops, '반팔 티셔츠'),
      );
      final coat = await tester.runAsync(
        () => pixels(GarmentCategory.outerwear, '코트'),
      );
      final puffer = await tester.runAsync(
        () => pixels(GarmentCategory.outerwear, '패딩'),
      );
      final jacket = await tester.runAsync(
        () => pixels(GarmentCategory.outerwear, '재킷'),
      );
      expect(coat, isNot(top));
      expect(puffer, isNot(coat));
      expect(jacket, isNot(coat));
      final dress = await tester.runAsync(
        () => pixels(GarmentCategory.dresses, '롱 원피스'),
      );
      final jumpsuit = await tester.runAsync(
        () => pixels(GarmentCategory.dresses, '점프수트'),
      );
      final set = await tester.runAsync(
        () => pixels(GarmentCategory.dresses, '투피스 세트'),
      );
      expect(jumpsuit, isNot(dress));
      expect(set, isNot(dress));
      expect(set, isNot(jumpsuit));
      expect(
        const FitSilhouettePainter(
          '레귤러핏',
          GarmentCategory.outerwear,
          Colors.black,
          subtype: '패딩',
        ).shouldRepaint(
          const FitSilhouettePainter(
            '레귤러핏',
            GarmentCategory.outerwear,
            Colors.black,
            subtype: '코트',
          ),
        ),
        isTrue,
      );
    },
  );

  for (final design in AppDesign.values) {
    for (final width in [360.0, 1440.0]) {
      testWidgets(
        'Coat controls fit $width px ${design.name} with enlarged text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final controller = TextEditingController(text: '직접 입력한 핏');
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(design),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: StatefulBuilder(
                    builder: (context, setState) => FitSelector(
                      controller: controller,
                      category: GarmentCategory.outerwear,
                      subtype: '코트',
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tap(tester, find.byKey(const ValueKey('fit-오버핏')));
          expect(controller.text, '오버핏');
          expect(find.text('오버핏 · 선택됨'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
