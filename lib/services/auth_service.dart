import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthIdentity {
  const AuthIdentity(this.id, this.email);
  final String id;
  final String email;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

abstract interface class AuthService {
  Stream<AuthIdentity?> get changes;
  Future<AuthIdentity?> restore();
  Future<AuthIdentity> signIn(String email, String password);
  Future<AuthIdentity?> signUp(String email, String password);
  Future<void> signOut();
}

/// The SDK verifies/refreshes JWTs through local Auth; no hand-written JWT decode.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this.client, this.sessionStorage);
  final SupabaseClient client;
  final LocalStorage sessionStorage;

  AuthIdentity? _identity(User? user) => user == null || user.isAnonymous
      ? null
      : AuthIdentity(user.id, user.email ?? '');

  @override
  Stream<AuthIdentity?> get changes => client.auth.onAuthStateChange
      .where((event) => event.event != AuthChangeEvent.initialSession)
      .map((event) => _identity(event.session?.user));

  @override
  Future<AuthIdentity?> restore() async {
    if (client.auth.currentSession == null) return null;
    if (client.auth.currentSession!.isExpired) {
      await client.auth.refreshSession();
    }
    return _identity((await client.auth.getUser()).user);
  }

  @override
  Future<AuthIdentity> signIn(String email, String password) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final identity = _identity(response.user);
    if (identity == null || response.session == null) {
      throw const AuthFailure('로그인 상태를 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return identity;
  }

  @override
  Future<AuthIdentity?> signUp(String email, String password) async {
    final response = await client.auth.signUp(email: email, password: password);
    return response.session == null ? null : _identity(response.user);
  }

  @override
  Future<void> signOut() async {
    try {
      // SDK clears its in-memory session before requesting server revocation.
      await client.auth.signOut(scope: SignOutScope.local);
    } finally {
      // Also await removal explicitly, including offline/revocation failure.
      await sessionStorage.removePersistedSession();
    }
  }
}

String authErrorMessage(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is AuthException) {
    return switch (error.code) {
      'invalid_credentials' => '이메일 또는 비밀번호가 올바르지 않아요.',
      'email_not_confirmed' => '이메일 인증을 완료해 주세요. 로컬 Mailpit에서 확인할 수 있어요.',
      'weak_password' => '비밀번호가 보안 조건을 충족하지 않아요. 더 강한 비밀번호를 사용해 주세요.',
      'email_address_invalid' ||
      'validation_failed' => '이메일과 비밀번호 형식을 확인해 주세요.',
      'user_already_exists' ||
      'email_exists' => '가입 정보를 확인해 주세요. 이미 가입했다면 로그인해 주세요.',
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' => '요청이 많아요. 잠시 후 다시 시도해 주세요.',
      'signup_disabled' => '현재 로컬 서버에서 회원가입이 비활성화되어 있어요.',
      'refresh_token_not_found' ||
      'refresh_token_already_used' ||
      'session_not_found' ||
      'bad_jwt' ||
      'session_expired' => '세션이 만료되었어요. 다시 로그인해 주세요.',
      _ => '인증 요청을 완료하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요.',
    };
  }
  return '로컬 인증 서버에 연결하지 못했어요. 서버 상태를 확인해 주세요.';
}
