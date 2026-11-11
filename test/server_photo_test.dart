import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/screens/server_wardrobe_screen.dart';
import 'package:my_closet/screens/wardrobe_screen.dart';
import 'package:my_closet/services/auth_controller.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/server_photo_repository.dart';
import 'package:my_closet/services/supabase_photo_wardrobe_repository.dart';
import 'package:my_closet/widgets/garment_photo.dart';

import 'auth_test.dart' show FakeAuth, alice;
import 'server_wardrobe_test.dart' show RevisionFake, tap, type;
import 'support/wardrobe_fakes.dart';

class PhotoFake extends RevisionFake implements ServerPhotoRepository {
  bool failUpload = false;
  int reads = 0, uploads = 0;
  Completer<Uint8List>? pendingRead;
  @override
  ServerPhotoStatus photoStatus(Garment g) =>
      ServerPhotoStatus(ready: photos.containsKey(g.id), uploadState: 'none');
  @override
  String? photoKey(Garment g) => photos.containsKey(g.id)
      ? '${g.id}/${g.updatedAt.toIso8601String()}'
      : null;
  @override
  Future<Uint8List> readVerifiedPhoto(Garment g) {
    reads++;
    return pendingRead?.future ?? Future.value(photos[g.id]!);
  }

  @override
  Future<Garment> uploadPhoto(
    Garment g,
    ProcessedPhoto photo, {
    void Function(String)? onProgress,
  }) async {
    uploads++;
    onProgress?.call('서버에서 실제 사진 검증 중…');
    if (failUpload) {
      throw ServerPhotoException('storage_unavailable', retryable: true);
    }
    photos[g.id] = photo.bytes;
    final saved = Garment.fromJson({
      ...g.toJson(),
      'imageWidth': photo.width,
      'imageHeight': photo.height,
      'imageMimeType': photo.mimeType,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    items[g.id] = saved;
    return saved;
  }

  @override
  Future<Garment> verifyPendingPhoto(Garment g) async => g;
  @override
  Future<Garment> cancelPendingPhoto(Garment g) async => g;
  @override
  Future<Garment> removePhoto(Garment g) async {
    photos.remove(g.id);
    return g;
  }

  @override
  Future<Garment> cleanupPhoto(Garment g) async => g;
}

void main() {
  test('server client limits use actual content headers and reject invalid/oversize photos', () {
    final bytes = testPhoto();
    validateServerPhoto(ProcessedPhoto(bytes, 8, 8));
    for (final p in [
      ProcessedPhoto(Uint8List(0), 1, 1),
      ProcessedPhoto(Uint8List(2097153), 1, 1),
      ProcessedPhoto(Uint8List.fromList([1, 2, 3]), 1, 1),
      ProcessedPhoto(bytes, 2001, 2001),
      ProcessedPhoto(bytes, 8, 8, mimeType: 'image/png'),
    ]) {
      expect(
        () => validateServerPhoto(p),
        throwsA(isA<ServerPhotoException>()),
      );
    }
  });
  testWidgets('unapproved photos are never downloaded or displayed', (
    tester,
  ) async {
    final repo = PhotoFake();
    final g = testGarment();
    repo.items[g.id] = g;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GarmentPhoto(garment: g, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.reads, 0);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(ServerPhotoPlaceholder), findsOneWidget);
  });
  testWidgets(
    'photo upload failure preserves one metadata row and permits retry without duplicate creation',
    (tester) async {
      final repo = PhotoFake()..failUpload = true;
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
      await tap(tester, find.text('사진 선택'));
      await type(tester, '의류 이름 *', '사진 재시도 검사');
      await tap(tester, find.byKey(const ValueKey('category-field')));
      await tap(tester, find.text('상의').last);
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items.length, 1);
      final id = repo.items.keys.single;
      expect(
        find.textContaining('의류 정보는 저장됐지만 사진 작업을 완료하지 못했어요.'),
        findsOneWidget,
      );
      repo.failUpload = false;
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items.keys.single, id);
      expect(repo.uploads, 2);
      expect(repo.photos[id], isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving a failed new upload refreshes the already saved metadata in the list',
    (tester) async {
      final repo = PhotoFake()..failUpload = true;
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
      await tap(tester, find.text('사진 선택'));
      await type(tester, '의류 이름 *', '저장된 메타데이터');
      await tap(tester, find.byKey(const ValueKey('category-field')));
      await tap(tester, find.text('상의').last);
      await tap(tester, find.text('옷 저장하기'));
      expect(repo.items.length, 1);
      expect(repo.photos, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('discard-changes')));
      expect(find.text('저장된 메타데이터'), findsOneWidget);
      expect(find.byType(ServerPhotoPlaceholder), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed replacement keeps approved bytes, and cancelling preview restores previous picture',
    (tester) async {
      final repo = PhotoFake()..failUpload = true;
      final g = testGarment(name: '기존 승인 사진');
      repo.items[g.id] = g;
      final original = testPhoto();
      repo.photos[g.id] = original;
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
      await tap(tester, find.byKey(ValueKey('garment-${g.id}')));
      await tap(tester, find.text('정보 수정'));
      await tap(tester, find.text('사진 변경'));
      await tap(tester, find.text('옷 저장하기'));
      expect(identical(repo.photos[g.id], original), isTrue);
      await tap(tester, find.text('선택 취소'));
      expect(find.text('사진 변경'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'logout removes server image widgets and their Flutter image-cache key',
    (tester) async {
      final service = FakeAuth()..identity = alice;
      final auth = AuthController(service);
      await auth.restore();
      final repo = PhotoFake();
      final g = testGarment();
      repo.items[g.id] = g;
      repo.photos[g.id] = testPhoto();
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
      final provider = tester.widget<Image>(find.byType(Image).first).image;
      final key = await provider.obtainKey(ImageConfiguration.empty);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      await service.events.close();
    },
  );
  testWidgets('late photo download is not rendered after logout', (
    tester,
  ) async {
    final service = FakeAuth()..identity = alice;
    final auth = AuthController(service);
    await auth.restore();
    final repo = PhotoFake()..pendingRead = Completer();
    final g = testGarment();
    repo.items[g.id] = g;
    repo.photos[g.id] = testPhoto();
    await tester.pumpWidget(
      MaterialApp(
        home: ServerWardrobeScreen(
          auth: auth,
          repositoryFactory: (_, _) => repo,
          photoService: FakePhotoService(),
        ),
      ),
    );
    await tester.pump();
    await auth.signOut();
    await tester.pump();
    repo.pendingRead!.complete(testPhoto());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(repo.closed, isTrue);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    await service.events.close();
  });
}
