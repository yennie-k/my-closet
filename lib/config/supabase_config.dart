/// Compile-time, public client configuration. Never supply a secret/service key.
class LocalSupabaseConfig {
  const LocalSupabaseConfig({
    required this.enabled,
    required this.url,
    required this.publishableKey,
    this.wardrobeEnabled = false,
  });

  factory LocalSupabaseConfig.fromEnvironment() => const LocalSupabaseConfig(
    enabled: bool.fromEnvironment('MY_CLOSET_SUPABASE_ENABLED'),
    url: String.fromEnvironment('MY_CLOSET_SUPABASE_URL'),
    publishableKey: String.fromEnvironment(
      'MY_CLOSET_SUPABASE_PUBLISHABLE_KEY',
    ),
    wardrobeEnabled: bool.fromEnvironment('MY_CLOSET_SERVER_WARDROBE_ENABLED'),
  );

  final bool enabled;
  final String url;
  final String publishableKey;
  final bool wardrobeEnabled;

  String? validationError({Uri? browserOrigin}) {
    if (!enabled) {
      return wardrobeEnabled ? '서버 옷장은 로컬 인증 개발 설정과 함께 켜야 해요.' : null;
    }
    if (url != 'http://127.0.0.1:54321') {
      return '개발 연결은 로컬 API 127.0.0.1:54321만 허용해요.';
    }
    if (!RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(publishableKey)) {
      return '로컬 publishable key 설정을 확인해 주세요. 비밀키는 사용할 수 없어요.';
    }
    if (browserOrigin != null &&
        (browserOrigin.scheme != 'http' ||
            !['localhost', '127.0.0.1'].contains(browserOrigin.host) ||
            browserOrigin.port != 8081)) {
      return '개발 인증은 별도 브라우저 주소 localhost:8081에서 실행해 주세요.';
    }
    return null;
  }
}
