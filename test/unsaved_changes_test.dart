import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/server_wardrobe_screen.dart';
import 'package:my_closet/services/auth_controller.dart';

import 'auth_test.dart' show FakeAuth, alice, bob;
import 'garment_classification_change_test.dart'
    show
        openEditor,
        CountingWardrobe,
        syntheticCoat,
        category,
        accept,
        cancel,
        field,
        value;
import 'garment_input_ux_test.dart' show type, expand;
import 'server_photo_test.dart' show PhotoFake;
import 'server_wardrobe_test.dart' show RevisionFake;
import 'support/wardrobe_fakes.dart';

const warning = '변경사항이 저장되지 않았어요';
Future<void> tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> keep(WidgetTester tester) =>
    tap(tester, find.byKey(const ValueKey('continue-editing')));
Future<void> discard(WidgetTester tester) =>
    tap(tester, find.byKey(const ValueKey('discard-changes')));

class WaitingRevisionWardrobe extends RevisionFake {
  final pendingSave = Completer<Garment>();
  int requests = 0;
  @override
  Future<Garment> saveWithOriginal(Garment g, {Garment? original}) {
    requests++;
    return pendingSave.future;
  }
}

class WaitingPhotoWardrobe extends PhotoFake {
  final pendingUpload = Completer<Garment>();
  @override
  Future<Garment> uploadPhoto(
    Garment g,
    photo, {
    void Function(String)? onProgress,
  }) {
    uploads++;
    onProgress?.call('합성 사진 검증 대기');
    return pendingUpload.future;
  }
}

void main() {
  for (final edit in [false, true]) {
    testWidgets(
      '${edit ? 'Edit' : 'New'} untouched or focused form exits without warning',
      (tester) async {
        final repo = CountingWardrobe();
        final old = edit ? syntheticCoat() : null;
        await openEditor(tester, repo, old: old);
        await tap(tester, field('의류 이름 *'));
        await back(tester);
        expect(find.text(warning), findsNothing);
        expect(find.text('합성 편집 열기'), findsOneWidget);
        expect(repo.writes, edit ? 1 : 0);
      },
    );
  }

  for (final server in [false, true]) {
    testWidgets(
      '${server ? 'Server' : 'Local'} edits continue intact or discard without any write',
      (tester) async {
        final repo = server ? PhotoFake() : CountingWardrobe();
        final old = syntheticCoat();
        await openEditor(tester, repo, old: old);
        final photo = repo.photos[old.id];
        await type(tester, '의류 이름 *', '저장하지 않은 합성 이름');
        await back(tester);
        expect(find.text(warning), findsOneWidget);
        expect(
          find.text('저장하지 않고 나가면 이번에 변경한 내용이 사라집니다. 정말 나가시겠어요?'),
          findsOneWidget,
        );
        await keep(tester);
        expect(value(tester, '의류 이름 *'), '저장하지 않은 합성 이름');
        await back(tester);
        await discard(tester);
        expect(repo.items[old.id]!.toJson(), old.toJson());
        expect(repo.photos[old.id], photo);
        if (repo is PhotoFake) {
          expect(repo.attempts, isEmpty);
          expect(repo.uploads, 0);
        }
        if (repo is CountingWardrobe) expect(repo.writes, 1);
      },
    );
  }

  testWidgets('New metadata input discards without creating a row', (
    tester,
  ) async {
    final repo = RevisionFake();
    await openEditor(tester, repo);
    await type(tester, '의류 이름 *', '입력 중인 합성 신규 옷');
    await back(tester);
    await discard(tester);
    expect(repo.items, isEmpty);
    expect(repo.attempts, isEmpty);
  });

  testWidgets(
    'All text fields reverted to baseline leave clean even with focus changes',
    (tester) async {
      final old = syntheticCoat(fit: '레귤러핏');
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      await expand(tester, 'colors');
      await expand(tester, 'fit');
      for (final entry in {
        '의류 이름 *': old.name,
        '대표 색상': old.primaryColor,
        '핏': old.fit,
        '메모': old.notes,
      }.entries) {
        await type(tester, entry.key, '${entry.value} 변경');
        await type(tester, entry.key, entry.value);
      }
      await tester.ensureVisible(field('세부 종류 직접 입력'));
      await tester.enterText(field('세부 종류 직접 입력'), '미적용 입력');
      await tester.pumpAndSettle();
      await tester.enterText(field('세부 종류 직접 입력'), old.subtype);
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(find.text('합성 편집 열기'), findsOneWidget);
    },
  );

  testWidgets('Multi selections and thickness restored to baseline are clean', (
    tester,
  ) async {
    final old = Garment.fromJson({
      ...syntheticCoat(fit: '').toJson(),
      'seasons': ['spring', 'autumn'],
      'styleTags': ['미니멀', '캐주얼'],
      'additionalColors': ['블루', '핑크'],
      'materials': ['울', '면'],
    });
    final repo = CountingWardrobe();
    await openEditor(tester, repo, old: old);
    final spring = find.widgetWithText(FilterChip, '봄');
    await tap(tester, spring);
    expect(tester.widget<FilterChip>(spring).selected, isFalse);
    await tap(tester, spring);
    expect(tester.widget<FilterChip>(spring).selected, isTrue);
    await tap(tester, find.widgetWithText(FilterChip, '미니멀'));
    await tap(tester, find.widgetWithText(FilterChip, '미니멀'));
    await expand(tester, 'colors');
    await tap(tester, find.byKey(const ValueKey('additional-블루')));
    await tap(tester, find.byKey(const ValueKey('additional-블루')));
    await expand(tester, 'materials');
    await tap(tester, find.byKey(const ValueKey('material-울')));
    await tap(tester, find.byKey(const ValueKey('material-울')));
    await expand(tester, 'thickness');
    await tap(tester, find.byKey(const ValueKey('thickness-2')));
    await tap(tester, find.byKey(const ValueKey('thickness-4')));
    await back(tester);
    expect(find.text(warning), findsNothing);
    expect(repo.items[old.id]!.toJson(), old.toJson());
  });

  for (final input in ['추가 색상 직접 입력', '소재 직접 입력', '세부 종류 직접 입력']) {
    testWidgets('Pending $input is guarded without requiring Add or Apply', (
      tester,
    ) async {
      final repo = CountingWardrobe();
      await openEditor(tester, repo);
      if (input.startsWith('추가')) await expand(tester, 'colors');
      if (input.startsWith('소재')) await expand(tester, 'materials');
      await tester.ensureVisible(field(input));
      await tester.enterText(field(input), '아직 추가하지 않은 값');
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text(warning), findsOneWidget);
      await keep(tester);
      expect(value(tester, input), '아직 추가하지 않은 값');
      await tester.enterText(field(input), '');
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(repo.writes, 0);
    });
  }

  testWidgets(
    'Confirmed category cleanup is dirty; cancelling category change is clean',
    (tester) async {
      final old = syntheticCoat();
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      await category(tester, GarmentCategory.shoes);
      await cancel(tester);
      await back(tester);
      expect(find.text(warning), findsNothing);
      await tap(tester, find.text('합성 편집 열기'));
      await category(tester, GarmentCategory.shoes);
      await accept(tester);
      await back(tester);
      expect(find.text(warning), findsOneWidget);
      await keep(tester);
      expect(value(tester, '세부 종류 직접 입력'), '');
      expect(value(tester, '핏'), '');
      expect(repo.items[old.id]!.toJson(), old.toJson());
    },
  );

  testWidgets(
    'Selecting a photo then discarding never uploads or writes metadata',
    (tester) async {
      final repo = PhotoFake();
      await openEditor(tester, repo);
      await tap(tester, find.text('사진 선택'));
      await back(tester);
      expect(find.text(warning), findsOneWidget);
      await discard(tester);
      expect(repo.uploads, 0);
      expect(repo.attempts, isEmpty);
      expect(repo.items, isEmpty);
    },
  );

  testWidgets(
    'Selecting then removing new photo restores clean initial draft',
    (tester) async {
      final repo = CountingWardrobe();
      await openEditor(tester, repo);
      await tap(tester, find.text('사진 선택'));
      await tap(tester, find.text('사진 삭제'));
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(repo.writes, 0);
    },
  );

  testWidgets(
    'Removing existing local photo warns and discarding preserves its bytes',
    (tester) async {
      final old = syntheticCoat();
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      final photo = repo.photos[old.id];
      await tap(tester, find.text('사진 삭제'));
      await back(tester);
      expect(find.text(warning), findsOneWidget);
      await discard(tester);
      expect(repo.photos[old.id], photo);
      expect(repo.writes, 1);
    },
  );

  testWidgets(
    'Cancelling a server replacement restores the clean original photo state',
    (tester) async {
      final old = syntheticCoat();
      final repo = PhotoFake();
      await openEditor(tester, repo, old: old);
      await tap(tester, find.text('사진 변경'));
      await tap(tester, find.text('선택 취소'));
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(repo.uploads, 0);
    },
  );

  testWidgets(
    'Save success leaves without confirmation; failure retains draft and warning',
    (tester) async {
      final old = syntheticCoat(fit: '레귤러핏');
      final repo = CountingWardrobe();
      await openEditor(tester, repo, old: old);
      repo.failSave = true;
      await type(tester, '의류 이름 *', '실패 후 유지할 합성 이름');
      await tap(tester, find.text('옷 저장하기'));
      await back(tester);
      await keep(tester);
      expect(value(tester, '의류 이름 *'), '실패 후 유지할 합성 이름');
      expect(repo.items[old.id]!.toJson(), old.toJson());
      repo.failSave = false;
      await tap(tester, find.text('옷 저장하기'));
      expect(find.text(warning), findsNothing);
      expect(find.text('합성 편집 열기'), findsOneWidget);
      expect(repo.items[old.id]!.name, '실패 후 유지할 합성 이름');
    },
  );

  testWidgets(
    'Saving blocks system/app back and duplicate save until completion',
    (tester) async {
      final old = syntheticCoat(fit: '레귤러핏');
      final repo = WaitingRevisionWardrobe();
      await openEditor(tester, repo, old: old);
      await type(tester, '의류 이름 *', '저장 대기');
      await tap(tester, find.text('옷 저장하기'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(find.text('저장 중…'), findsOneWidget);
      expect(repo.requests, 1);
      await tester.tap(find.text('저장 중…'), warnIfMissed: false);
      await tester.pump();
      expect(repo.requests, 1);
      repo.pendingSave.complete(
        Garment.fromJson({...old.toJson(), 'name': '저장 대기'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('합성 편집 열기'), findsOneWidget);
    },
  );

  testWidgets(
    'Metadata saved but photo verification incomplete is never treated as fully saved',
    (tester) async {
      final old = syntheticCoat(fit: '레귤러핏');
      final repo = WaitingPhotoWardrobe();
      await openEditor(tester, repo, old: old);
      final photo = repo.photos[old.id];
      await tap(tester, find.text('사진 변경'));
      await tap(tester, find.text('옷 저장하기'));
      await back(tester);
      expect(find.text(warning), findsNothing);
      expect(find.text('저장 중…'), findsOneWidget);
      repo.pendingUpload.completeError(
        StateError('synthetic verification failure'),
      );
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text(warning), findsOneWidget);
      await discard(tester);
      expect(repo.photos[old.id], photo);
      expect(repo.uploads, 1);
    },
  );

  testWidgets('System back and maybePop use the same unsaved confirmation', (
    tester,
  ) async {
    final repo = CountingWardrobe();
    await openEditor(tester, repo);
    await type(tester, '의류 이름 *', '시스템 뒤로가기 합성 초안');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
    await keep(tester);
    final navigator = Navigator.of(tester.element(find.text('새로운 옷 등록')));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
    await discard(tester);
    expect(repo.writes, 0);
  });

  for (final logout in [false, true]) {
    testWidgets(
      'Server workspace ${logout ? 'logout' : 'outer close'} guards an inner editor',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeAuth()..identity = alice;
        final auth = AuthController(service);
        await auth.restore();
        final repo = PhotoFake();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ServerWardrobeScreen(
                        auth: auth,
                        repositoryFactory: (_, _) => repo,
                        photoService: FakePhotoService(),
                      ),
                    ),
                  ),
                  child: const Text('서버 열기'),
                ),
              ),
            ),
          ),
        );
        await tap(tester, find.text('서버 열기'));
        await tap(tester, find.byKey(const ValueKey('add-garment')));
        await type(tester, '의류 이름 *', '워크스페이스 이탈 보호');
        Finder exitButton() =>
            logout ? find.byTooltip('서버 로그아웃') : find.text('이 기기 옷장으로 돌아가기');
        await tap(tester, exitButton());
        expect(find.text(warning), findsOneWidget);
        await keep(tester);
        expect(auth.user, isNotNull);
        expect(value(tester, '의류 이름 *'), '워크스페이스 이탈 보호');
        await tap(tester, exitButton());
        await discard(tester);
        expect(repo.attempts, isEmpty);
        expect(repo.uploads, 0);
        expect(
          find.text(logout ? '로그인 후 서버 의류 정보를 관리할 수 있어요.' : '서버 열기'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        await service.events.close();
      },
    );
  }
  for (final design in AppDesign.values) {
    testWidgets(
      'Unsaved dialog fits mobile ${design.name} with enlarged text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 740);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repo = CountingWardrobe();
        await openEditor(tester, repo, design: design, scale: 1.5);
        await type(tester, '의류 이름 *', '작은 화면의 합성 초안');
        await back(tester);
        await keep(tester);
        expect(value(tester, '의류 이름 *'), '작은 화면의 합성 초안');
        await back(tester);
        await discard(tester);
        expect(repo.writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Forced account change destroys dirty editor and cannot reuse its exit callback',
    (tester) async {
      final service = FakeAuth()..identity = alice;
      final auth = AuthController(service);
      await auth.restore();
      final a = PhotoFake(), b = PhotoFake();
      final bg = testGarment(name: 'B 합성 의류');
      b.items[bg.id] = bg;
      await tester.pumpWidget(
        MaterialApp(
          home: ServerWardrobeScreen(
            auth: auth,
            repositoryFactory: (uid, _) => uid == alice.id ? a : b,
            photoService: FakePhotoService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('add-garment')));
      await type(tester, '의류 이름 *', 'A 계정 비공개 합성 초안');
      service.events.add(bob);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text(warning), findsNothing);
      expect(a.closed, isTrue);
      expect(find.text('B 합성 의류'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('add-garment')));
      await type(tester, '의류 이름 *', 'B 계정 새 초안');
      await tap(tester, find.byTooltip('서버 로그아웃'));
      await keep(tester);
      expect(value(tester, '의류 이름 *'), 'B 계정 새 초안');
      expect(a.attempts, isEmpty);
      expect(b.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      await service.events.close();
    },
  );
}
