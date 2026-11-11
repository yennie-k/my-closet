// Opt-in regression: normalizer -> Flutter decoder -> existing local worker.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/services/garment_photo_service.dart';
import 'package:my_closet/services/supabase_photo_wardrobe_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'server_photo_contract_test.dart' show PhotoTransport;

void main() {
  const input = String.fromEnvironment('MY_CLOSET_PHOTO_REGRESSION_FIXTURES');
  if (input.isEmpty) {
    test('explicit local synthetic fixture required', () {}, skip: 'Opt-in');
    return;
  }
  final file = File(input).absolute;
  if (!file.path
      .replaceAll('\\', '/')
      .contains('/my_closet/build/photo-preview-regression/')) {
    throw StateError('Unexpected fixture location');
  }
  final ctx = jsonDecode(file.readAsStringSync());
  if (ctx['api'] != 'http://127.0.0.1:54321' ||
      !RegExp(r'^crud-\d+-a@example.test$')
          .hasMatch(ctx['users']['a']['email'])) {
    throw StateError('Local synthetic context required');
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = PhotoTransport();
  late SupabaseClient client;
  late SupabasePhotoWardrobeRepository repo;
  final checks = <Map<String, dynamic>>[];
  setUpAll(() async {
    client = SupabaseClient(
      ctx['api'],
      ctx['publishableKey'],
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final user = ctx['users']['a'];
    await client.auth.signInWithPassword(
      email: user['email'],
      password: user['password'],
    );
    expect(client.auth.currentUser!.id, user['id']);
    repo = SupabasePhotoWardrobeRepository(
      client: client,
      userId: user['id'],
      sessionIsCurrent: () => true,
    );
  });
  tearDownAll(() async {
    await repo.close();
    await client.dispose();
    transport.close();
    File('${file.parent.path}/server-results.json').writeAsStringSync(
      jsonEncode({
        'passed': checks.where((c) => c['passed'] == true).length,
        'failed': checks.where((c) => c['passed'] == false).length,
        'checks': checks,
      }),
    );
  });
  for (final name in ['2048-420.jpg', 'png-rgb.png', 'webp-lossless.webp']) {
    test(
      'synthetic $name normalization, Flutter decode, upload, ready and refresh',
      () async {
        try {
          final bytes = File('build/photo-codec-20261105/$name')
              .readAsBytesSync();
          final photo = normalizeGarmentPhoto((name, bytes));
          await validatePhotoPreview(photo);
          final now = DateTime.now().toUtc();
          final draft = Garment(
            id: Garment.newId(),
            name: 'PREVIEW REGRESSION $name',
            category: GarmentCategory.tops,
            createdAt: now,
            updatedAt: now,
            imageWidth: 1,
            imageHeight: 1,
          );
          final saved = await repo.saveWithOriginal(draft);
          final uploaded = await repo.uploadPhoto(saved, photo);
          expect(repo.photoStatus(uploaded).ready, isTrue);
          expect(await repo.readVerifiedPhoto(uploaded), photo.bytes);
          final fresh = await repo.refresh(uploaded);
          expect(repo.photoStatus(fresh).ready, isTrue);
          expect(
            (fresh.imageWidth, fresh.imageHeight),
            (photo.width, photo.height),
          );
          checks.add({'name': name, 'passed': true});
        } catch (_) {
          checks.add({'name': name, 'passed': false});
          rethrow;
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
