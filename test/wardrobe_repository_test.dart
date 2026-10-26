import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:my_closet/services/storage/indexeddb_wardrobe_repository.dart';
import 'package:my_closet/services/storage/wardrobe_io.dart';
import 'package:my_closet/services/wardrobe_repository.dart';

import 'support/wardrobe_fakes.dart';

void main() {
  test(
    'Unavailable browser storage is an asynchronous recoverable error',
    () async {
      var attempts = 0;
      final repository = IndexedDbWardrobeRepository.lazy(() {
        attempts++;
        throw const WardrobeException('저장소를 열 수 없어요.');
      });
      await expectLater(repository.list(), throwsA(isA<WardrobeException>()));
      await expectLater(repository.list(), throwsA(isA<WardrobeException>()));
      expect(attempts, 2);
      await repository.close();
    },
  );
  test(
    'IndexedDB transaction contract preserves photos and deletes both records',
    () async {
      final factory = newIdbFactoryMemory();
      final repository = IndexedDbWardrobeRepository(factory);
      final garment = testGarment();
      final photo = testPhoto();
      await repository.save(garment, imageBytes: photo);
      await repository.close();
      final reopened = IndexedDbWardrobeRepository(factory);
      expect((await reopened.list()).single.toJson(), garment.toJson());
      expect(await reopened.readImage(garment.id), photo);
      final updated = testGarment(id: garment.id, name: '새 이름');
      await reopened.save(updated);
      expect((await reopened.list()).single.name, '새 이름');
      expect(await reopened.readImage(garment.id), photo);
      await reopened.delete(garment.id);
      expect(await reopened.list(), isEmpty);
      await expectLater(
        reopened.readImage(garment.id),
        throwsA(isA<WardrobeException>()),
      );
      await reopened.close();
    },
  );
  test('Missing required image rolls back metadata transaction', () async {
    final repository = IndexedDbWardrobeRepository(newIdbFactoryMemory());
    await expectLater(
      repository.save(testGarment()),
      throwsA(isA<WardrobeException>()),
    );
    expect(await repository.list(), isEmpty);
    await repository.close();
  });
  test(
    'Native file store persists metadata and raw image across new instances',
    () async {
      final directory = await Directory.systemTemp.createTemp('closet_store_');
      addTearDown(() {
        if (!directory.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        )) {
          throw StateError('Test cleanup escaped its temporary directory');
        }
        return directory.delete(recursive: true);
      });
      final first = FileWardrobeRepository(() async => directory);
      final garment = testGarment();
      final photo = testPhoto();
      await first.save(garment, imageBytes: photo);
      await first.close();
      final second = FileWardrobeRepository(() async => directory);
      expect((await second.list()).single.toJson(), garment.toJson());
      expect(await second.readImage(garment.id), photo);
      await second.save(testGarment(id: garment.id, name: '수정된 옷'));
      expect((await second.list()).single.name, '수정된 옷');
      expect(await second.readImage(garment.id), photo);
      await second.delete(garment.id);
      expect(await second.list(), isEmpty);
    },
  );
  test('Quota errors receive a useful message', () {
    expect(
      wardrobeError(StateError('QuotaExceededError')),
      contains('저장 공간이 부족'),
    );
  });
}
