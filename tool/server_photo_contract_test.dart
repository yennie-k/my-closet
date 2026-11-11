// Opt-in Dart SDK/real local backend photo workflow. Synthetic fixture accounts only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/supabase_photo_wardrobe_repository.dart';
import 'package:my_closet/services/supabase_wardrobe_repository.dart';

class RealHttp extends HttpOverrides {}

class PhotoTransport extends http.BaseClient {
  final inner = IOClient(RealHttp().createHttpClient(null));
  bool failUpload = false, loseUploadResponse = false;
  int downloads = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != 'http://127.0.0.1:54321') {
      throw StateError('Non-local URL');
    }
    final upload =
        request.method == 'POST' &&
        request.url.path.startsWith('/storage/v1/object/');
    if (upload && failUpload) {
      throw http.ClientException('Injected upload outage');
    }
    final response = await inner.send(request);
    if (request.method == 'GET' &&
        request.url.path.startsWith('/storage/v1/object/')) {
      downloads++;
    }
    if (upload && loseUploadResponse) {
      loseUploadResponse = false;
      await response.stream.drain<void>();
      throw http.ClientException(
        'Injected response loss after actual Storage commit',
      );
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  const fixturePath = String.fromEnvironment('MY_CLOSET_PHOTO_FIXTURES');
  if (fixturePath.isEmpty) {
    test(
      'real photo integration requires explicit fixture',
      () {},
      skip: 'Opt-in local test',
    );
    return;
  }
  final file = File(fixturePath).absolute;
  if (!file.path
      .replaceAll('\\', '/')
      .contains('/my_closet/build/supabase-photo-flow/')) {
    throw StateError('Invalid fixture path');
  }
  final ctx = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (ctx['api'] != 'http://127.0.0.1:54321' ||
      !(ctx['publishableKey'] as String).startsWith('sb_publishable_')) {
    throw StateError('Local public config only');
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = PhotoTransport();
  late SupabaseClient client;
  late SupabasePhotoWardrobeRepository repo;
  final uid = ctx['users']['a']['id'] as String;
  var current = true;
  Garment? first, failed;
  final checks = <Map<String, dynamic>>[];
  final jpg = Uint8List.fromList(
    File('${file.parent.path}/synthetic.jpg').readAsBytesSync(),
  );
  final png = Uint8List.fromList(
    File('${file.parent.path}/synthetic.png').readAsBytesSync(),
  );
  Garment sample(String name) => Garment(
    id: Garment.newId(),
    name: name,
    category: GarmentCategory.tops,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    imageWidth: 1,
    imageHeight: 1,
  );
  void check(String name, Future<void> Function() body) {
    test(name, () async {
      try {
        await body();
        checks.add({'name': name, 'passed': true});
      } catch (_) {
        checks.add({'name': name, 'passed': false});
        rethrow;
      }
    });
  }

  setUpAll(() async {
    client = SupabaseClient(
      ctx['api'],
      ctx['publishableKey'],
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: ctx['users']['a']['email'],
      password: ctx['users']['a']['password'],
    );
    repo = SupabasePhotoWardrobeRepository(
      client: client,
      userId: uid,
      sessionIsCurrent: () => current,
    );
  });
  tearDownAll(() async {
    await repo.close();
    await client.dispose();
    transport.close();
    File('${file.parent.path}/dart-photo-results.json').writeAsStringSync(
      jsonEncode({
        'passed': checks.where((c) => c['passed'] == true).length,
        'failed': checks.where((c) => c['passed'] == false).length,
        'checks': checks,
      }),
    );
  });
  check(
    'Dart repository uploads and verifies real JPEG through original worker',
    () async {
      final g = await repo.saveWithOriginal(sample('DART PHOTO ready'));
      final progress = <String>[];
      first = await repo.uploadPhoto(
        g,
        ProcessedPhoto(jpg, 24, 18),
        onProgress: progress.add,
      );
      expect(repo.photoStatus(first!).ready, isTrue);
      expect(first!.imageWidth, 24);
      expect(progress.last, '사진 검증 완료');
      expect(await repo.readVerifiedPhoto(first!), jpg);
      final count = transport.downloads;
      expect(await repo.readVerifiedPhoto(first!), jpg);
      expect(transport.downloads, count);
    },
  );
  check(
    'identical photo retry is idempotent and creates no retired slot',
    () async {
      final revision = repo.recordFor(first!).revision;
      first = await repo.uploadPhoto(first!, ProcessedPhoto(jpg, 24, 18));
      expect(repo.recordFor(first!).revision, revision);
      expect(repo.photoStatus(first!).cleanupAfter, isNull);
    },
  );
  check(
    'Dart replacement returns new attested PNG and keeps old photo protected',
    () async {
      final old = repo.photoKey(first!);
      first = await repo.uploadPhoto(
        first!,
        ProcessedPhoto(png, 24, 18, mimeType: 'image/png'),
      );
      expect(repo.photoKey(first!), isNot(old));
      expect(first!.imageMimeType, 'image/png');
      expect(await repo.readVerifiedPhoto(first!), png);
      expect(repo.recordFor(first!).raw['retired_photo_path'], old);
    },
  );
  check(
    'new replacement while cleanup pending is a clear safe rejection',
    () async {
      final old = repo.photoKey(first!);
      await expectLater(
        repo.uploadPhoto(first!, ProcessedPhoto(jpg, 24, 18)),
        throwsA(
          isA<ServerPhotoException>().having(
            (e) => e.code,
            'code',
            'cleanup_pending',
          ),
        ),
      );
      expect(repo.photoKey(await repo.refresh(first!)), old);
    },
  );
  check(
    'failed upload preserves active photo and retry resumes exact reservation',
    () async {
      final g = await repo.saveWithOriginal(sample('DART PHOTO failure'));
      failed = await repo.uploadPhoto(g, ProcessedPhoto(jpg, 24, 18));
      final old = repo.photoKey(failed!);
      transport.failUpload = true;
      await expectLater(
        repo.uploadPhoto(
          failed!,
          ProcessedPhoto(png, 24, 18, mimeType: 'image/png'),
        ),
        throwsA(isA<ServerPhotoException>()),
      );
      transport.failUpload = false;
      failed = await repo.refresh(failed!);
      expect(repo.photoKey(failed!), old);
      expect(await repo.readVerifiedPhoto(failed!), jpg);
      failed = await repo.uploadPhoto(
        failed!,
        ProcessedPhoto(png, 24, 18, mimeType: 'image/png'),
      );
      expect(repo.photoStatus(failed!).ready, isTrue);
      expect(await repo.readVerifiedPhoto(failed!), png);
    },
  );
  check(
    'lost successful Storage response retries without overwrite or duplicate',
    () async {
      final g = await repo.saveWithOriginal(sample('DART PHOTO response loss'));
      transport.loseUploadResponse = true;
      await expectLater(
        repo.uploadPhoto(g, ProcessedPhoto(jpg, 24, 18)),
        throwsA(isA<ServerPhotoException>()),
      );
      final result = await repo.uploadPhoto(g, ProcessedPhoto(jpg, 24, 18));
      expect(repo.photoStatus(result).ready, isTrue);
      expect(await repo.readVerifiedPhoto(result), jpg);
    },
  );
  check('photo-linked garment deletion remains blocked', () async {
    await expectLater(
      repo.deleteWithOriginal(first!),
      throwsA(
        isA<ServerWardrobeException>().having(
          (e) => e.kind,
          'kind',
          ServerWardrobeFailureKind.photosUnsupported,
        ),
      ),
    );
  });
  check('parallel same-photo requests converge without overwrites', () async {
    final g = await repo.saveWithOriginal(sample('DART PHOTO parallel'));
    Future<Object> attempt() async {
      try {
        return await repo.uploadPhoto(g, ProcessedPhoto(jpg, 24, 18));
      } catch (e) {
        return e;
      }
    }

    final values = await Future.wait([attempt(), attempt()]);
    expect(values.whereType<Garment>(), isNotEmpty);
    for (final error in values.whereType<ServerPhotoException>()) {
      expect(error.retryable, isTrue);
    }
    final actual = await repo.refresh(g);
    final revision = repo.recordFor(actual).revision;
    final again = await repo.uploadPhoto(actual, ProcessedPhoto(jpg, 24, 18));
    expect(repo.recordFor(again).revision, revision);
    expect(repo.photoStatus(again).ready, isTrue);
  });
  check(
    'session boundary rejects cached image access after logout/account change',
    () async {
      expect(await repo.readVerifiedPhoto(first!), png);
      current = false;
      await expectLater(
        repo.readVerifiedPhoto(first!),
        throwsA(
          isA<ServerWardrobeException>().having(
            (e) => e.kind,
            'kind',
            ServerWardrobeFailureKind.sessionChanged,
          ),
        ),
      );
    },
  );
}
