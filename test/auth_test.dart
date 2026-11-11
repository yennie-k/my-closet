import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_closet/config/supabase_config.dart';
import 'package:my_closet/models/user_preferences.dart';
import 'package:my_closet/screens/auth_screen.dart';
import 'package:my_closet/screens/server_wardrobe_test_screen.dart';
import 'package:my_closet/services/auth_controller.dart';
import 'package:my_closet/services/auth_service.dart';
import 'package:my_closet/services/server_wardrobe_reader.dart';
import 'package:my_closet/theme/app_theme.dart';

const alice = AuthIdentity('alice', 'alice@example.test');
const bob = AuthIdentity('bob', 'bob@example.test');
const row = ServerGarmentSummary(
  id: 'server-id',
  name: '서버 테스트 니트',
  category: 'tops',
  subtype: '니트',
  photoState: 'pending',
);

class FakeAuth implements AuthService {
  final events = StreamController<AuthIdentity?>.broadcast(sync: true);
  AuthIdentity? identity;
  Object? failure;
  bool confirmationRequired = false;
  Completer<AuthIdentity?>? pendingRestore;
  Completer<void>? pendingSignOut;
  @override
  Stream<AuthIdentity?> get changes => events.stream;
  @override
  Future<AuthIdentity?> restore() =>
      pendingRestore?.future ?? Future.value(identity);
  @override
  Future<AuthIdentity> signIn(String email, String password) async {
    if (failure != null) throw failure!;
    return identity = alice;
  }

  @override
  Future<AuthIdentity?> signUp(String email, String password) async {
    if (failure != null) throw failure!;
    return confirmationRequired ? null : identity = alice;
  }

  @override
  Future<void> signOut() async {
    identity = null;
    events.add(null);
    await pendingSignOut?.future;
  }
}

class FakeReader implements ServerWardrobeReader {
  int calls = 0;
  Completer<List<ServerGarmentSummary>>? pending;
  @override
  Future<List<ServerGarmentSummary>> listOwn(String userId) {
    calls++;
    return pending?.future ?? Future.value([row]);
  }
}

void main() {
  test('개발 연결은 명시적 flag, 로컬 API, publishable key, 별도 origin을 요구한다', () {
    const disabled = LocalSupabaseConfig(
      enabled: false,
      url: '',
      publishableKey: '',
    );
    expect(disabled.validationError(), isNull);
    LocalSupabaseConfig config({
      String url = 'http://127.0.0.1:54321',
      String key = 'sb_publishable_local',
    }) => LocalSupabaseConfig(enabled: true, url: url, publishableKey: key);
    expect(
      config().validationError(
        browserOrigin: Uri.parse('http://localhost:8081'),
      ),
      isNull,
    );
    expect(
      config().validationError(
        browserOrigin: Uri.parse('http://localhost:8080'),
      ),
      isNotNull,
    );
    expect(
      config(url: 'https://cloud.supabase.co').validationError(),
      isNotNull,
    );
    expect(
      config(url: 'http://127.0.0.1:54321@evil.test').validationError(),
      isNotNull,
    );
    for (final key in ['sb_secret_test', 'eyJ.service.role', '']) {
      expect(config(key: key).validationError(), isNotNull);
    }
  });

  test('복원 중 로그아웃하면 늦게 도착한 세션을 복구하지 않는다', () async {
    final service = FakeAuth()..pendingRestore = Completer();
    final auth = AuthController(service);
    final restoring = auth.restore();
    await auth.signOut();
    service.pendingRestore!.complete(alice);
    await restoring;
    expect(auth.user, isNull);
    expect(auth.restoring, isFalse);
    auth.dispose();
    await service.events.close();
  });

  test('세션 복원, refresh 이벤트, refresh 오류, 계정 전환을 처리한다', () async {
    final service = FakeAuth()..identity = alice;
    final auth = AuthController(service);
    await auth.restore();
    expect(auth.user!.id, alice.id);
    final generation = auth.generation;
    service.events.add(alice);
    expect(auth.generation, generation);
    service.events.add(bob);
    expect(auth.user!.id, bob.id);
    expect(auth.generation, greaterThan(generation));
    service.events.addError(
      const AuthException('Sensitive raw message', code: 'session_expired'),
      StackTrace.current,
    );
    expect(auth.user, isNull);
    expect(auth.error, contains('다시 로그인'));
    expect(auth.error, isNot(contains('Sensitive')));
    auth.dispose();
    await service.events.close();
  });

  test('로그인·가입 실패 메시지와 이메일 확인 대기를 구분한다', () async {
    final service = FakeAuth()
      ..failure = const AuthException(
        'raw secret',
        code: 'invalid_credentials',
      );
    final auth = AuthController(service);
    await auth.restore();
    expect(await auth.submit('a@example.test', 'bad', signUp: false), isFalse);
    expect(auth.error, '이메일 또는 비밀번호가 올바르지 않아요.');
    service.failure = null;
    service.confirmationRequired = true;
    expect(
      await auth.submit('a@example.test', 'password', signUp: true),
      isTrue,
    );
    expect(auth.user, isNull);
    expect(auth.notice, contains('Mailpit'));
    service.confirmationRequired = false;
    expect(
      await auth.submit('a@example.test', 'password', signUp: true),
      isTrue,
    );
    expect(auth.user!.id, alice.id);
    auth.dispose();
    await service.events.close();
  });

  for (final design in AppDesign.values) {
    for (final width in [360.0, 1280.0]) {
      testWidgets('${design.name} 인증 화면 ${width.toInt()}px 입력·오류 안내·가입 검증', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeAuth()
          ..failure = const AuthException('bad', code: 'invalid_credentials');
        final auth = AuthController(service);
        await auth.restore();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(design),
            home: AuthScreen(auth: auth),
          ),
        );
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(find.text('이메일 주소를 확인해 주세요.'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('auth-email')),
          'alice@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('auth-password')),
          'wrong-password',
        );
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(find.text('이메일 또는 비밀번호가 올바르지 않아요.'), findsOneWidget);
        await tester.ensureVisible(find.text('처음인가요? 회원가입'));
        await tester.tap(find.text('처음인가요? 회원가입'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('auth-password')),
          'test-password',
        );
        await tester.enterText(
          find.byKey(const Key('auth-confirmation')),
          'different',
        );
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(find.text('비밀번호가 서로 달라요.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        await service.events.close();
      });
    }
  }

  testWidgets('미로그인 조회 차단, 로그인 조회, 로그아웃 즉시 삭제 및 늦은 응답 폐기', (tester) async {
    final service = FakeAuth();
    final auth = AuthController(service);
    await auth.restore();
    final reader = FakeReader();
    await tester.pumpWidget(
      MaterialApp(
        home: ServerWardrobeTestScreen(auth: auth, reader: reader),
      ),
    );
    await tester.pumpAndSettle();
    expect(reader.calls, 0);
    expect(find.text('로그인이 필요해요.'), findsOneWidget);
    service.events.add(alice);
    await tester.pumpAndSettle();
    expect(find.text(row.name), findsOneWidget);
    reader.pending = Completer();
    await tester.tap(find.text('다시 조회'));
    await tester.pump();
    service.pendingSignOut = Completer();
    final signingOut = auth.signOut();
    await tester.pump();
    expect(find.text(row.name), findsNothing);
    reader.pending!.complete([row]);
    await tester.pump();
    expect(find.text(row.name), findsNothing);
    service.pendingSignOut!.complete();
    await signingOut;
    await tester.pumpAndSettle();
    expect(find.text('로그인이 필요해요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    await service.events.close();
  });
}
