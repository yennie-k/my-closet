import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/config/supabase_config.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/server_garment_record.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/server_wardrobe_screen.dart';
import 'package:my_closet/screens/garment_editor_screen.dart';
import 'package:my_closet/screens/wardrobe_screen.dart';
import 'package:my_closet/services/auth_controller.dart';
import 'package:my_closet/services/revisioned_wardrobe_repository.dart';
import 'package:my_closet/services/supabase_wardrobe_repository.dart';
import 'package:my_closet/theme/app_theme.dart';

import 'auth_test.dart' show FakeAuth, alice, bob;
import 'support/wardrobe_fakes.dart';

class RevisionFake extends MemoryWardrobe
    implements RevisionedWardrobeRepository, MetadataOnlyWardrobeRepository {
  final attempts = <Garment>[];
  bool closed = false;
  Completer<List<Garment>>? pendingList;
  @override
  Future<List<Garment>> list() => pendingList?.future ?? super.list();
  @override
  Future<Garment> refresh(Garment original) async => items[original.id]!;
  @override
  Future<Garment> saveWithOriginal(Garment garment, {Garment? original}) async {
    attempts.add(garment);
    if (failSave) {
      throw const ServerWardrobeException(
        ServerWardrobeFailureKind.network,
        '연결 실패. 같은 화면에서 다시 시도해 주세요.',
      );
    }
    items[garment.id] = garment;
    return garment;
  }

  @override
  Future<void> deleteWithOriginal(Garment original) =>
      super.delete(original.id);
  @override
  Future<void> close() async {
    closed = true;
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String text) async {
  final finder = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('server photo policy works when caller omits presentation flag', (
    tester,
  ) async {
    final repo = RevisionFake();
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
    await tap(tester, find.byKey(const ValueKey('add-garment')));
    await type(tester, '의류 이름 *', '사진 없는 회귀 검사');
    await tap(tester, find.byKey(const ValueKey('category-field')));
    await tap(tester, find.text('상의').last);
    await tap(tester, find.text('옷 저장하기'));
    expect(find.text('의류 이름, 카테고리, 사진과 입력한 값을 확인해 주세요.'), findsNothing);
    expect(repo.items.values.single.name, '사진 없는 회귀 검사');
    final created = repo.items.values.single;
    await tap(tester, find.byKey(ValueKey('garment-${created.id}')));
    expect(find.text('사진 연결 전\n의류 정보만 관리해요.'), findsOneWidget);
    await tap(tester, find.text('정보 수정'));
    expect(find.text('사진 선택'), findsNothing);
    await type(tester, '의류 이름 *', '사진 없이 수정됨');
    await tap(tester, find.text('옷 저장하기'));
    expect(repo.items.values.single.name, '사진 없이 수정됨');
    await tap(tester, find.text('의류 삭제'));
    await tap(tester, find.text('삭제하기'));
    expect(repo.items, isEmpty);
    expect(repo.photos, isEmpty);
  });

  testWidgets(
    'server required errors identify name and category without mentioning photo',
    (tester) async {
      final repo = RevisionFake();
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditorScreen(
            repository: repo,
            photoService: FakePhotoService(),
          ),
        ),
      );
      await tap(tester, find.text('옷 저장하기'));
      String summary() =>
          tester.widget<Text>(find.byKey(const ValueKey('editor-error'))).data!;
      expect(summary(), contains('의류 이름을 입력해 주세요.'));
      expect(summary(), contains('카테고리를 선택해 주세요.'));
      expect(summary(), isNot(contains('사진')));
      await type(tester, '의류 이름 *', '이름은 입력함');
      await tap(tester, find.text('옷 저장하기'));
      expect(summary(), '카테고리를 선택해 주세요.');
      expect(repo.items, isEmpty);
    },
  );

  testWidgets(
    'optional color validation reports actual error, not missing name/category/photo',
    (tester) async {
      final repo = RevisionFake();
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditorScreen(
            repository: repo,
            photoService: FakePhotoService(),
          ),
        ),
      );
      await type(tester, '의류 이름 *', '색상 오류 검사');
      await tap(tester, find.byKey(const ValueKey('category-field')));
      await tap(tester, find.text('상의').last);
      await tap(tester, find.text('색상').first);
      await type(tester, '대표 색상', '민트');
      await type(tester, '추가 색상 직접 입력', '민트');
      await tap(tester, find.text('옷 저장하기'));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('editor-error'))).data,
        '대표 색상과 다른 색상을 입력해 주세요.',
      );
      expect(repo.items, isEmpty);
    },
  );

  testWidgets(
    'local wardrobe still requires photo with otherwise valid fields',
    (tester) async {
      final repo = MemoryWardrobe();
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditorScreen(
            repository: repo,
            photoService: FakePhotoService(),
          ),
        ),
      );
      expect(find.text('이 기기 옷장 · 사진 필수'), findsOneWidget);
      await type(tester, '의류 이름 *', '로컬 사진 필수 검사');
      await tap(tester, find.byKey(const ValueKey('category-field')));
      await tap(tester, find.text('상의').last);
      await tap(tester, find.text('옷 저장하기'));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('editor-error'))).data,
        '이 기기 옷장에는 사진이 필요해요. 사진을 선택해 주세요.',
      );
      expect(repo.items, isEmpty);
      await tap(tester, find.text('사진 선택'));
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items.values.single.name, '로컬 사진 필수 검사');
      expect(repo.photos, isNotEmpty);
    },
  );
  test('CRUD flag requires local auth and remains disabled by default', () {
    expect(LocalSupabaseConfig.fromEnvironment().wardrobeEnabled, isFalse);
    expect(
      const LocalSupabaseConfig(
        enabled: false,
        wardrobeEnabled: true,
        url: '',
        publishableKey: '',
      ).validationError(),
      isNotNull,
    );
  });
  test('server mapper emits only allowed metadata columns, retains legacy and custom values', () {
    final g = testGarment();
    final row = {
      ...ServerGarmentRecord.insert(g, 'user'),
      'id': 'server-uuid',
      'revision': 7,
      'photo_state': 'pending',
      'upload_state': 'none',
      'primary_color': '사용자색',
      'primary_color_hex': '#123ABC',
      'materials': <String>[],
      'material': '혼방 원문',
      'photo_path': null,
      'upload_path': null,
      'retired_photo_path': null,
    };
    final record = ServerGarmentRecord(row);
    expect(record.garment.id, g.id);
    expect(record.serverId, 'server-uuid');
    expect(record.revision, 7);
    final update = ServerGarmentRecord.metadata(
      record.garment,
      original: record,
    );
    expect(update['materials'], isEmpty);
    expect(update['material'], '혼방 원문');
    expect(update['primary_color_hex'], '#123ABC');
    final customDetails = [
      {'name': '기존 추가 정보', 'hex': null, 'custom': '원문 보존'},
    ];
    final withDetails = ServerGarmentRecord({
      ...row,
      'additional_color_details': customDetails,
    });
    expect(
      ServerGarmentRecord.metadata(
        withDetails.garment,
        original: withDetails,
      )['additional_color_details'],
      customDetails,
    );
    for (final column in [
      'id',
      'user_id',
      'local_id',
      'created_at',
      'revision',
      'server_updated_at',
      'photo_state',
      'image_width',
      'upload_state',
    ]) {
      expect(update.containsKey(column), isFalse, reason: column);
    }
    expect(record.hasPhotoWorkflow, isFalse);
    expect(
      ServerGarmentRecord({...row, 'photo_state': 'ready'}).hasPhotoWorkflow,
      isTrue,
    );
    expect(
      ServerGarmentRecord({...row, 'upload_state': 'reserved'})
          .hasPhotoWorkflow,
      isTrue,
    );
  });
  for (final design in AppDesign.values) {
    for (final width in [360.0, 1280.0]) {
      testWidgets(
        '${design.name} ${width}px metadata form needs no photo; retry reuses ID/date',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 850));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repo = RevisionFake();
          final photos = FakePhotoService()..fail = true;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(design),
              home: Scaffold(
                body: WardrobeScreen(repository: repo, photoService: photos),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tap(tester, find.byKey(const ValueKey('add-garment')));
          expect(find.text('사진 선택'), findsNothing);
          await type(tester, '의류 이름 *', '사진 없는 서버 셔츠');
          await tap(tester, find.byKey(const ValueKey('category-field')));
          await tap(tester, find.text('상의').last);
          await type(tester, '세부 종류 직접 입력', '사용자 종류');
          repo.failSave = true;
          await tap(tester, find.text('옷 저장하기'));
          expect(find.byKey(const ValueKey('editor-error')), findsOneWidget);
          repo.failSave = false;
          await tap(tester, find.text('옷 저장하기'));
          expect(repo.attempts.length, 2);
          expect(repo.attempts[0].id, repo.attempts[1].id);
          expect(repo.attempts[0].createdAt, repo.attempts[1].createdAt);
          expect(repo.items.values.single.subtype, '사용자 종류');
          expect(repo.photos, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('logout destroys open server editor and its private draft', (
    tester,
  ) async {
    final service = FakeAuth()..identity = alice;
    final auth = AuthController(service);
    await auth.restore();
    final repo = RevisionFake();
    await tester.pumpWidget(
      MaterialApp(
        home: ServerWardrobeScreen(
          auth: auth,
          repositoryFactory: (_, _) => repo,
          photoService: FakePhotoService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('add-garment')));
    await type(tester, '의류 이름 *', '이전 계정의 민감한 초안');
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('로그인 후 서버 의류 정보를 관리할 수 있어요.'), findsOneWidget);
    expect(repo.closed, isTrue);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    await service.events.close();
  });
  testWidgets(
    'switching accounts discards old in-flight list and resets filters',
    (tester) async {
      final service = FakeAuth()..identity = alice;
      final auth = AuthController(service);
      await auth.restore();
      final a = RevisionFake()..pendingList = Completer();
      final b = RevisionFake();
      final bg = testGarment(name: 'B 계정의 셔츠');
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
      await tester.pump();
      service.events.add(bob);
      await tester.pumpAndSettle();
      a.pendingList!.complete([testGarment(name: '늦게 도착한 A 데이터')]);
      await tester.pumpAndSettle();
      expect(find.text('B 계정의 셔츠'), findsOneWidget);
      expect(find.text('늦게 도착한 A 데이터'), findsNothing);
      expect(a.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      await service.events.close();
    },
  );
}
