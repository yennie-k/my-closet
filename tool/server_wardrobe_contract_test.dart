// Opt-in real LOCAL integration. Never part of default flutter test discovery.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_closet/models/garment.dart';
import 'package:my_closet/models/server_garment_record.dart';
import 'package:my_closet/services/supabase_wardrobe_repository.dart';

class LocalFaultClient extends http.BaseClient {
  final inner = http.Client();
  bool offline = false, dropNextInsert = false, denyNextRead = false;
  Completer<void>? holdRead;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != 'http://127.0.0.1:54321') {
      throw StateError('Non-local request blocked');
    }
    final rest = request.url.path == '/rest/v1/garments';
    if (rest && offline) {
      throw http.ClientException('Injected transport outage');
    }
    if (rest && denyNextRead && request.method == 'GET') {
      denyNextRead = false;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'code': '42501',
              'message': 'Injected permission denial',
            }),
          ),
        ),
        403,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    final response = await inner.send(request);
    if (rest && request.method == 'POST' && dropNextInsert) {
      dropNextInsert = false;
      await response.stream.drain<void>();
      throw http.ClientException(
        'Injected response loss AFTER actual DB commit',
      );
    }
    if (rest && request.method == 'GET' && holdRead != null) {
      await holdRead!.future;
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  const fixturePath = String.fromEnvironment('MY_CLOSET_CRUD_FIXTURES');
  if (fixturePath.isEmpty) {
    test(
      'real local contract requires explicit ignored fixture path',
      () {},
      skip: 'Opt-in test; prepare synthetic local fixtures first',
    );
    return;
  }
  final file = File(fixturePath).absolute;
  if (!file.path
      .replaceAll('\\', '/')
      .contains('/my_closet/build/supabase-wardrobe-crud/')) {
    throw StateError('Fixture path outside ignored local test folder');
  }
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (fixture['api'] != 'http://127.0.0.1:54321' ||
      !(fixture['publishableKey'] as String).startsWith('sb_publishable_')) {
    throw StateError('Local-only public configuration required');
  }
  final users = fixture['users'] as Map<String, dynamic>;
  final uid = users['a']['id'] as String;
  late SupabaseClient a, b, anon, fault;
  final transport = LocalFaultClient();
  late SupabaseWardrobeRepository repo, otherRepo, faulty;
  final results = <Map<String, dynamic>>[];
  Garment? current;
  var stillCurrent = true;
  SupabaseClient client({http.Client? httpClient}) => SupabaseClient(
    fixture['api'],
    fixture['publishableKey'],
    httpClient: httpClient,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  SupabaseWardrobeRepository repository(SupabaseClient client, String owner) =>
      SupabaseWardrobeRepository(
        client: client,
        userId: owner,
        sessionIsCurrent: () => true,
      );
  Future<void> login(SupabaseClient client, String who) async {
    await client.auth.signInWithPassword(
      email: users[who]['email'],
      password: users[who]['password'],
    );
  }

  Garment sample({String name = '테스트 셔츠', String? id}) => Garment(
    id: id ?? Garment.newId(),
    name: name,
    category: GarmentCategory.tops,
    createdAt: DateTime.utc(2026, 11, 2, 1, 2, 3),
    updatedAt: DateTime.utc(2026, 11, 2, 1, 2, 3),
    subtype: '직접 입력한 니트',
    primaryColor: '카키',
    additionalColors: ['민트', '사용자 정의 은빛'],
    seasons: [Season.spring, Season.winter],
    thickness: GarmentThickness.veryThick,
    styleTags: ['캐주얼', '사용자 정의 스타일'],
    material: '기존 혼방 문자열 70/30',
    materials: ['면', '울 30%', '사용자 혼방'],
    fit: '나만의 핏',
    notes: '모델 v2 전 필드 보존\n두 번째 줄',
    imageMimeType: 'image/jpeg',
    imageWidth: 1,
    imageHeight: 1,
  );
  Garment change(Garment g, String name) => Garment.fromJson({
    ...g.toJson(),
    'name': name,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });
  Matcher failure(ServerWardrobeFailureKind kind) =>
      isA<ServerWardrobeException>().having((e) => e.kind, 'kind', kind);
  void check(String name, Future<void> Function() body) {
    test(name, () async {
      try {
        await body();
        results.add({'name': name, 'passed': true});
      } catch (_) {
        results.add({'name': name, 'passed': false});
        rethrow;
      }
    });
  }

  setUpAll(() async {
    a = client();
    b = client();
    anon = client();
    fault = client(httpClient: transport);
    await login(a, 'a');
    await login(b, 'b');
    await login(fault, 'a');
    repo = repository(a, uid);
    otherRepo = repository(b, users['b']['id']);
    faulty = repository(fault, uid);
  });
  tearDownAll(() async {
    final out = File('${file.parent.path}/repository-results.json');
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'passed': results.where((r) => r['passed'] == true).length,
        'failed': results.where((r) => r['passed'] == false).length,
        'checks': results,
      }),
    );
    await repo.close();
    await otherRepo.close();
    await faulty.close();
    await a.dispose();
    await b.dispose();
    await anon.dispose();
    await fault.dispose();
    transport.close();
  });

  check('A create without Storage and full v2 roundtrip', () async {
    final original = sample();
    current = await repo.saveWithOriginal(original);
    expect(current!.toJson(), original.toJson());
    final envelope = repo.recordFor(current!);
    expect(envelope.serverId, isNot(original.id));
    expect(envelope.revision, 1);
    expect(envelope.raw['photo_state'], 'pending');
    expect(envelope.raw['upload_state'], 'none');
    expect(envelope.raw['photo_path'], isNull);
    expect((await repo.list()).any((g) => g.id == original.id), isTrue);
  });
  check(
    'A metadata update uses original revision and preserves all other fields',
    () async {
      final old = current!;
      final before = repo.recordFor(old);
      final expected = change(old, '수정된 서버 셔츠');
      current = await repo.saveWithOriginal(expected, original: old);
      expect(current!.toJson(), expected.toJson());
      expect(repo.recordFor(current!).revision, before.revision + 1);
      expect(repo.recordFor(current!).raw['server_updated_at'], isNotNull);
    },
  );
  check('B cannot read update or delete A through actual RLS', () async {
    final id = repo.recordFor(current!).serverId;
    expect(await b.from('garments').select().eq('id', id), isEmpty);
    expect(
      await b
          .from('garments')
          .update({'name': 'illegal'})
          .eq('id', id)
          .select(),
      isEmpty,
    );
    expect(await b.from('garments').delete().eq('id', id).select(), isEmpty);
    expect((await repo.refresh(current!)).name, current!.name);
  });
  for (final operation in ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
    check('anon $operation denied by actual GRANT/RLS', () async {
      final query = switch (operation) {
        'SELECT' => anon.from('garments').select(),
        'INSERT' =>
          anon
              .from('garments')
              .insert(ServerGarmentRecord.insert(sample(), uid)),
        'UPDATE' =>
          anon
              .from('garments')
              .update({'name': 'illegal'})
              .eq('id', repo.recordFor(current!).serverId),
        _ =>
          anon
              .from('garments')
              .delete()
              .eq('id', repo.recordFor(current!).serverId),
      };
      await expectLater(
        query,
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    });
  }
  check(
    'stale editor stays stale even after list refresh; no automatic overwrite',
    () async {
      final stale = current!;
      current = await repo.saveWithOriginal(
        change(stale, '다른 탭의 변경'),
        original: stale,
      );
      await repo.list();
      await expectLater(
        repo.saveWithOriginal(change(stale, '덮어쓰기 금지'), original: stale),
        throwsA(failure(ServerWardrobeFailureKind.conflict)),
      );
      expect((await repo.refresh(current!)).name, '다른 탭의 변경');
    },
  );
  check(
    'two real concurrent updates yield one success and one conflict',
    () async {
      final second = repository(a, uid);
      final copy = (await second.list()).singleWhere(
        (g) => g.id == current!.id,
      );
      Future<Object> attempt(
        SupabaseWardrobeRepository r,
        Garment g,
        String name,
      ) async {
        try {
          return await r.saveWithOriginal(change(g, name), original: g);
        } catch (e) {
          return e;
        }
      }

      final values = await Future.wait([
        attempt(repo, current!, '동시 수정 A'),
        attempt(second, copy, '동시 수정 B'),
      ]);
      expect(values.whereType<Garment>().length, 1);
      expect(
        values.whereType<ServerWardrobeException>().single.kind,
        ServerWardrobeFailureKind.conflict,
      );
      current = await repo.refresh(current!);
      await second.close();
    },
  );
  check('missing row is reported as deleted OR inaccessible without privileged probe', () async {
    final original = await repo.saveWithOriginal(sample(name: '삭제 후 수정 검사'));
    await repo.deleteWithOriginal(original);
    await expectLater(
      repo.saveWithOriginal(change(original, 'stale'), original: original),
      throwsA(failure(ServerWardrobeFailureKind.missingOrInaccessible)),
    );
  });
  check('simultaneous duplicate creates and sequential retry create exactly one row', () async {
    final draft = sample(name: '멱등 등록');
    final values = await Future.wait([
      repo.saveWithOriginal(draft),
      repo.saveWithOriginal(draft),
    ]);
    expect(
      repo.recordFor(values[0]).serverId,
      repo.recordFor(values[1]).serverId,
    );
    final retry = await repo.saveWithOriginal(draft);
    expect(repo.recordFor(retry).revision, 1);
    expect(
      (await a.from('garments').select('id').eq('local_id', draft.id)).length,
      1,
    );
  });
  check('changed duplicate create refuses to merge or overwrite', () async {
    final draft = sample(name: '원래 등록');
    await repo.saveWithOriginal(draft);
    await expectLater(
      repo.saveWithOriginal(change(draft, '변경된 재시도')),
      throwsA(failure(ServerWardrobeFailureKind.duplicateChanged)),
    );
    expect(
      (await a.from('garments').select('name').eq('local_id', draft.id))
          .single['name'],
      '원래 등록',
    );
  });
  check('lost INSERT response after actual commit is safely retried', () async {
    final draft = sample(name: '응답 유실 검사');
    transport.dropNextInsert = true;
    await expectLater(
      faulty.saveWithOriginal(draft),
      throwsA(failure(ServerWardrobeFailureKind.network)),
    );
    final saved = await faulty.saveWithOriginal(draft);
    expect(saved.id, draft.id);
    expect(
      (await a.from('garments').select('id').eq('local_id', draft.id)).length,
      1,
    );
  });
  check('network failure and recovery differ from permission denial', () async {
    transport.offline = true;
    await expectLater(
      faulty.list(),
      throwsA(failure(ServerWardrobeFailureKind.network)),
    );
    transport.offline = false;
    expect(await faulty.list(), isNotEmpty);
    transport.denyNextRead = true;
    await expectLater(
      faulty.list(),
      throwsA(failure(ServerWardrobeFailureKind.permission)),
    );
    expect(await faulty.list(), isNotEmpty);
  });
  check(
    'legacy material empty array and custom HEX survive unrelated edits',
    () async {
      final draft = sample(name: '기존 자유 입력 호환');
      final input = ServerGarmentRecord.insert(draft, uid)
        ..['primary_color'] = '직접 만든 색상'
        ..['primary_color_hex'] = '#123ABC'
        ..['additional_color_details'] = [
          {'name': '민트', 'hex': '#A6D9C5'},
          {'name': '사용자 정의 은빛', 'hex': '#C1C2C3'},
        ]
        ..['materials'] = <String>[]
        ..['source_model_version'] = 1;
      await a.from('garments').insert(input);
      final original = (await repo.list()).singleWhere((g) => g.id == draft.id);
      expect(original.materials, isEmpty);
      expect(original.material, draft.material);
      final saved = await repo.saveWithOriginal(
        change(original, '자유 입력 보존됨'),
        original: original,
      );
      final record = repo.recordFor(saved);
      expect(record.raw['primary_color_hex'], '#123ABC');
      expect(
        record.raw['additional_color_details'],
        input['additional_color_details'],
      );
      expect(record.raw['source_model_version'], 1);
      expect(saved.materials, isEmpty);
    },
  );
  check(
    'stale delete conflicts; refreshed delete removes only exact row',
    () async {
      final old = current!;
      current = await repo.saveWithOriginal(
        change(old, '삭제 전 변경'),
        original: old,
      );
      await expectLater(
        repo.deleteWithOriginal(old),
        throwsA(failure(ServerWardrobeFailureKind.conflict)),
      );
      await repo.deleteWithOriginal(current!);
      expect(
        await a
            .from('garments')
            .select('id')
            .eq('id', repo.recordFor(current!).serverId),
        isEmpty,
      );
    },
  );
  check(
    'late query response after session change is discarded; old repo unusable',
    () async {
      final scoped = SupabaseWardrobeRepository(
        client: fault,
        userId: uid,
        sessionIsCurrent: () => stillCurrent,
      );
      transport.holdRead = Completer();
      final reading = scoped.list();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      stillCurrent = false;
      transport.holdRead!.complete();
      await expectLater(
        reading,
        throwsA(failure(ServerWardrobeFailureKind.sessionChanged)),
      );
      transport.holdRead = null;
      await expectLater(
        scoped.list(),
        throwsA(failure(ServerWardrobeFailureKind.sessionChanged)),
      );
      await scoped.close();
    },
  );
  check('unauthenticated repository CRUD rejected before requests', () async {
    final noSession = repository(anon, uid);
    await expectLater(
      noSession.list(),
      throwsA(failure(ServerWardrobeFailureKind.authentication)),
    );
    await expectLater(
      noSession.saveWithOriginal(sample()),
      throwsA(failure(ServerWardrobeFailureKind.authentication)),
    );
    await expectLater(
      noSession.deleteWithOriginal(sample()),
      throwsA(failure(ServerWardrobeFailureKind.authentication)),
    );
    await noSession.close();
  });
  check(
    'user_id spoofing and forbidden photo fact updates remain denied',
    () async {
      await expectLater(
        a
            .from('garments')
            .insert(ServerGarmentRecord.insert(sample(), users['b']['id'])),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
      final own = (await repo.list()).first;
      final id = repo.recordFor(own).serverId;
      await expectLater(
        a.from('garments').update({'image_width': 100}).eq('id', id),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    },
  );
}
