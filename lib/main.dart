import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'services/auth_controller.dart';
import 'services/auth_service.dart';
import 'services/server_wardrobe_reader.dart';
import 'services/preferences_service.dart';
import 'services/supabase_photo_wardrobe_repository.dart';
import 'screens/server_wardrobe_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = LocalSupabaseConfig.fromEnvironment();
  AuthController? auth;
  ServerWardrobeReader? serverReader;
  ServerRepositoryFactory? serverRepositoryFactory;
  if (config.enabled || config.wardrobeEnabled) {
    final error = config.validationError(
      browserOrigin: kIsWeb ? Uri.base : null,
    );
    if (error != null) {
      auth = AuthController.unavailable(error);
    } else {
      try {
        final storage = SharedPreferencesLocalStorage(
          persistSessionKey: 'my_closet.local_supabase.auth.v1',
        );
        await Supabase.initialize(
          url: config.url,
          publishableKey: config.publishableKey,
          debug: false,
          authOptions: FlutterAuthClientOptions(
            localStorage: storage,
            detectSessionInUri: false,
          ),
        );
        final client = Supabase.instance.client;
        final controller = AuthController(SupabaseAuthService(client, storage));
        auth = controller;
        serverReader = SupabaseServerWardrobeReader(client);
        if (config.wardrobeEnabled) {
          serverRepositoryFactory = (userId, generation) =>
              SupabasePhotoWardrobeRepository(
                client: client,
                userId: userId,
                sessionIsCurrent: () =>
                    controller.user?.id == userId &&
                    controller.generation == generation,
              );
        }
        // The controller handles failures; no credentials are logged.
        unawaited(auth.restore());
      } catch (_) {
        auth = AuthController.unavailable(
          '개발 인증을 시작하지 못했어요. 로컬 설정과 브라우저 저장 권한을 확인해 주세요.',
        );
      }
    }
  }
  runApp(
    MyClosetApp(
      store: LocalPreferencesStore(),
      auth: auth,
      serverReader: serverReader,
      serverRepositoryFactory: serverRepositoryFactory,
    ),
  );
}
