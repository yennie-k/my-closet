import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/app.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/services/preferences_service.dart';
import 'package:my_closet/theme/app_theme.dart';

import 'support/wardrobe_fakes.dart';

class MemoryStore implements PreferencesStore {
  UserPreferences value = const UserPreferences();
  bool failSave = false;
  bool failLoad = false;
  @override
  Future<UserPreferences> load() async {
    if (failLoad) throw StateError('load failed');
    return value;
  }

  @override
  Future<void> save(UserPreferences preferences) async {
    if (failSave) throw StateError('save failed');
    value = preferences;
  }
}

const completed = UserPreferences(styles: ['캐주얼'], onboardingComplete: true);

Future<void> tapText(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Onboarding validates styles, previews theme, saves and skips on restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryStore();
      await tester.pumpWidget(
        MyClosetApp(store: store, wardrobeRepository: MemoryWardrobe()),
      );
      await tester.pumpAndSettle();
      await tapText(tester, '시작하기');
      await tapText(tester, '러블리');
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme!.colorScheme.primary,
        DesignPalette.of(AppDesign.lovely).accent,
      );
      await tapText(tester, '다음');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '다음'))
            .onPressed,
        isNull,
      );
      await tapText(tester, '캐주얼');
      await tapText(tester, '빈티지');
      await tapText(tester, '다음');
      await tapText(tester, '추위를 많이 탐');
      await tapText(tester, '이전');
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '캐주얼'))
            .selected,
        isTrue,
      );
      await tapText(tester, '다음');
      await tapText(tester, '다음');
      store.failSave = true;
      await tapText(tester, '내 옷장 시작하기');
      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
      expect(store.value.onboardingComplete, isFalse);
      store.failSave = false;
      await tapText(tester, '내 옷장 시작하기');
      expect(store.value.design, AppDesign.lovely);
      expect(store.value.styles, ['캐주얼', '빈티지']);
      expect(store.value.temperature, TemperaturePreference.cold);
      expect(store.value.onboardingComplete, isTrue);
      expect(find.text('오늘도, 나답게 입어요.'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MyClosetApp(store: store, wardrobeRepository: MemoryWardrobe()),
      );
      await tester.pumpAndSettle();
      expect(find.text('오늘도, 나답게 입어요.'), findsOneWidget);
      expect(find.text('시작하기'), findsNothing);
    },
  );

  testWidgets(
    'Desktop navigation and profile save, cancellation and failure work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryStore()..value = completed;
      await tester.pumpWidget(
        MyClosetApp(store: store, wardrobeRepository: MemoryWardrobe()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tapText(tester, '내 옷장');
      expect(find.text('첫 번째 옷을 등록해 보세요'), findsOneWidget);
      for (final label in ['코디 추천', '코디 기록']) {
        await tapText(tester, label);
        expect(find.text('준비 중'), findsOneWidget);
      }
      await tapText(tester, '마이페이지');
      await tapText(tester, '러블리');
      await tapText(tester, '변경 취소');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '설정 저장하기'))
            .onPressed,
        isNull,
      );
      await tapText(tester, '모던');
      await tapText(tester, '시크');
      await tapText(tester, '더위를 많이 탐');
      store.failSave = true;
      await tapText(tester, '설정 저장하기');
      expect(find.textContaining('설정을 저장하지 못했어요'), findsOneWidget);
      expect(store.value.design, AppDesign.minimal);
      store.failSave = false;
      await tapText(tester, '설정 저장하기');
      expect(store.value.design, AppDesign.modern);
      expect(store.value.styles, ['캐주얼', '시크']);
      expect(store.value.temperature, TemperaturePreference.hot);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .primary,
        DesignPalette.of(AppDesign.modern).accent,
      );
    },
  );

  testWidgets('All mobile destinations fit a 360 pixel viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MyClosetApp(
        store: MemoryStore()..value = completed,
        wardrobeRepository: MemoryWardrobe(),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['내 옷장', '코디 추천', '코디 기록', '마이페이지', '홈']) {
      final destination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'Failed loading offers retry without overwriting saved preferences',
    (tester) async {
      final store = MemoryStore()
        ..value = completed
        ..failLoad = true;
      await tester.pumpWidget(
        MyClosetApp(store: store, wardrobeRepository: MemoryWardrobe()),
      );
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsOneWidget);
      store.failLoad = false;
      await tapText(tester, '다시 시도');
      expect(find.text('오늘도, 나답게 입어요.'), findsOneWidget);
    },
  );
}
