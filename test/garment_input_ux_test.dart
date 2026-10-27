import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/garment_options.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/garment_editor_screen.dart';
import 'package:my_closet/widgets/garment_illustrations.dart';
import 'package:my_closet/theme/app_theme.dart';

import 'support/wardrobe_fakes.dart';
import 'garment_compatibility_test.dart' show legacyMetadata;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> expand(WidgetTester tester, String id) => tap(
  tester,
  find
      .descendant(
        of: find.byKey(PageStorageKey('section-$id')),
        matching: find.byType(ListTile),
      )
      .first,
);
Future<void> type(WidgetTester tester, String label, String value) async {
  final finder = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<void> pumpEditor(
  WidgetTester tester,
  MemoryWardrobe repository,
  Garment garment, {
  AppDesign design = AppDesign.minimal,
}) async {
  await repository.save(garment, imageBytes: testPhoto());
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(design),
      home: GarmentEditorScreen(
        repository: repository,
        photoService: FakePhotoService(),
        garment: garment,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'All category recommendations update without replacing custom subtype',
    (tester) async {
      final garment = Garment.fromJson(legacyMetadata());
      final repo = MemoryWardrobe();
      await pumpEditor(tester, repo, garment);
      for (final category in GarmentCategory.values) {
        await tap(tester, find.byKey(const ValueKey('category-field')));
        await tap(tester, find.text(category.label).last);
        final field = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, '세부 종류 직접 입력'),
        );
        expect(field.controller!.text, garment.subtype);
        final suggestions = subtypeSuggestions[category]!;
        if (suggestions.isNotEmpty) {
          expect(
            find.widgetWithText(FilterChip, suggestions.first),
            findsOneWidget,
          );
        }
      }
    },
  );

  testWidgets(
    'Primary single select, extra multi select, custom entry and duplicate blocking',
    (tester) async {
      final repo = MemoryWardrobe();
      final garment = testGarment();
      await pumpEditor(tester, repo, garment);
      await expand(tester, 'colors');
      await tap(tester, find.byKey(const ValueKey('primary-화이트')));
      await tap(tester, find.byKey(const ValueKey('primary-블랙')));
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('additional-블랙')))
            .onTap,
        isNull,
      );
      await tap(tester, find.byKey(const ValueKey('additional-블루')));
      await tap(tester, find.byKey(const ValueKey('additional-핑크')));
      await tap(tester, find.byKey(const ValueKey('primary-블루')));
      expect(find.widgetWithText(InputChip, '블루'), findsNothing);
      await type(tester, '추가 색상 직접 입력', '블루');
      await tap(tester, find.byKey(const ValueKey('additional-add')));
      expect(find.text('대표 색상과 다른 색상을 입력해 주세요.'), findsOneWidget);
      await type(tester, '추가 색상 직접 입력', '차콜');
      // Saving without pressing Add still commits the pending custom entry.
      await tap(tester, find.text('옷 저장하기'));
      final saved = repo.items.values.single;
      expect(saved.primaryColor, '블루');
      expect(saved.additionalColors, ['핑크', '차콜']);
    },
  );

  for (final design in AppDesign.values) {
    testWidgets(
      'Custom legacy values and illustrated selections fit mobile with ${design.name} theme',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final old = Garment.fromJson(legacyMetadata());
        final repo = MemoryWardrobe();
        await pumpEditor(tester, repo, old, design: design);
        final originalPhoto = repo.photos[old.id];
        await expand(tester, 'materials');
        expect(find.widgetWithText(InputChip, old.material), findsOneWidget);
        await tap(tester, find.byKey(const ValueKey('material-울')));
        await tap(tester, find.byKey(const ValueKey('material-면')));
        await type(tester, '소재 직접 입력', '린넨 60% / 면 40%');
        await expand(tester, 'fit');
        expect(
          tester
              .widget<TextFormField>(find.widgetWithText(TextFormField, '핏'))
              .controller!
              .text,
          old.fit,
        );
        expect(
          find.byWidgetPredicate(
            (v) => v is CustomPaint && v.painter is FitSilhouettePainter,
          ),
          findsWidgets,
        );
        await tap(tester, find.byKey(const ValueKey('fit-오버핏')));
        await expand(tester, 'thickness');
        await tap(tester, find.byKey(const ValueKey('thickness-5')));
        await tap(tester, find.text('옷 저장하기'));
        final saved = repo.items.values.single;
        expect(saved.id, old.id);
        expect(saved.createdAt, old.createdAt);
        expect(repo.photos[old.id], originalPhoto);
        expect(saved.material, old.material);
        expect(saved.materials, [old.material, '울', '면', '린넨 60% / 면 40%']);
        expect(saved.fit, '오버핏');
        expect(saved.thicknessLevel, 5);
        expect(saved.primaryColor, old.primaryColor);
        expect(saved.subtype, old.subtype);
      },
    );
  }

  testWidgets(
    'Unchanged legacy garment keeps its original modification time and image',
    (tester) async {
      final old = Garment.fromJson(legacyMetadata());
      final repo = MemoryWardrobe();
      await pumpEditor(tester, repo, old);
      final originalPhoto = repo.photos[old.id];
      repo.failSave =
          true; // An unchanged form must not perform a write at all.
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items[old.id]!.updatedAt, old.updatedAt);
      expect(repo.photos[old.id], originalPhoto);
      expect(find.byKey(const ValueKey('editor-error')), findsNothing);
    },
  );

  testWidgets('Palette remains usable at larger text scale', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = MemoryWardrobe();
    final old = testGarment();
    await repo.save(old, imageBytes: testPhoto());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: GarmentEditorScreen(
          repository: repo,
          photoService: FakePhotoService(),
          garment: old,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expand(tester, 'colors');
    await tap(tester, find.byKey(const ValueKey('primary-아이보리')));
    await expand(tester, 'fit');
    await tap(tester, find.byKey(const ValueKey('fit-레귤러핏')));
  });
}
