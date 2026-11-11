import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Independent of local preferences and the IndexedDB wardrobe repository.
class AuthController extends ChangeNotifier {
  AuthController(AuthService service) : _service = service {
    _subscription = service.changes.listen(
      (user) {
        if (_disposed || (_signingOut && user != null)) return;
        _operation++;
        _apply(user);
        restoring = false;
        error = null;
        notifyListeners();
      },
      onError: (Object failure, StackTrace stack) {
        if (_disposed) return;
        _operation++;
        _apply(null);
        restoring = false;
        error = authErrorMessage(failure);
        notifyListeners();
      },
    );
  }

  AuthController.unavailable(String message) : _service = null {
    error = message;
    restoring = false;
  }

  final AuthService? _service;
  StreamSubscription<AuthIdentity?>? _subscription;
  AuthIdentity? user;
  bool restoring = true;
  bool busy = false;
  bool _signingOut = false;
  bool _disposed = false;
  int _operation = 0;
  int generation = 0;
  String? error;
  String? notice;
  bool get available => _service != null;

  void _apply(AuthIdentity? value) {
    if (user?.id != value?.id) generation++;
    user = value;
  }

  Future<void> restore() async {
    if (!available || busy || _disposed) return;
    final operation = ++_operation;
    restoring = true;
    error = null;
    notifyListeners();
    try {
      final result = await _service!.restore();
      if (!_disposed && operation == _operation) _apply(result);
    } catch (failure) {
      if (!_disposed && operation == _operation) {
        _apply(null);
        error = authErrorMessage(failure);
      }
    } finally {
      if (!_disposed && operation == _operation) {
        restoring = false;
        notifyListeners();
      }
    }
  }

  Future<bool> submit(
    String email,
    String password, {
    required bool signUp,
  }) async {
    if (!available || busy || _disposed) return false;
    ++_operation;
    busy = true;
    restoring = false;
    error = null;
    notice = null;
    notifyListeners();
    try {
      final result = signUp
          ? await _service!.signUp(email.trim(), password)
          : await _service!.signIn(email.trim(), password);
      if (_disposed) return false;
      _apply(result);
      notice = signUp && result == null
          ? '이메일 확인이 필요할 수 있어요. 로컬 Mailpit (127.0.0.1:54324)에서 확인한 후 로그인해 주세요.'
          : null;
      return true;
    } catch (failure) {
      if (!_disposed) error = authErrorMessage(failure);
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    if (!available || busy || _disposed) return;
    ++_operation;
    generation++; // Invalidates outstanding server reads even before HTTP completes.
    _apply(null);
    _signingOut = true;
    busy = true;
    restoring = false;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await _service!.signOut();
    } catch (_) {
      if (!_disposed) {
        error = '이 기기에서는 로그아웃했어요. 서버의 세션 종료 확인은 실패했어요. 연결 후 다시 확인해 주세요.';
      }
    } finally {
      _signingOut = false;
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
