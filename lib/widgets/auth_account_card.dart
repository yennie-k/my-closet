import 'package:flutter/material.dart';

import '../screens/auth_screen.dart';
import '../services/auth_controller.dart';
import '../services/server_wardrobe_reader.dart';
import 'common.dart';

class AuthAccountCard extends StatelessWidget {
  const AuthAccountCard({
    super.key,
    required this.auth,
    this.reader,
    this.serverCrudEnabled = false,
  });
  final AuthController auth;
  final ServerWardrobeReader? reader;
  final bool serverCrudEnabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) => SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('로컬 개발 계정', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (auth.restoring)
            const Text('로그인 세션을 확인하고 있어요…')
          else
            Text(
              auth.user == null
                  ? '로그인하지 않은 상태예요.'
                  : '로그인됨 · ${auth.user!.email}',
            ),
          const SizedBox(height: 8),
          const Text('내 옷장과 설정은 계속 이 기기에 저장돼요. 로그인해도 옷이나 사진을 자동으로 업로드하지 않아요.'),
          if (auth.error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                auth.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (auth.user == null)
                FilledButton(
                  onPressed: !auth.available || auth.busy || auth.restoring
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AuthScreen(auth: auth),
                          ),
                        ),
                  child: const Text('로그인 / 회원가입'),
                )
              else
                OutlinedButton(
                  onPressed: auth.busy ? null : auth.signOut,
                  child: const Text('로그아웃'),
                ),
              if (auth.available && !auth.restoring && auth.error != null)
                TextButton(
                  onPressed: auth.busy ? null : auth.restore,
                  child: const Text('세션 다시 확인'),
                ),
              if (reader != null)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/dev/server-wardrobe'),
                  child: const Text('서버 의류 조회 테스트'),
                ),
              if (serverCrudEnabled)
                FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(context)
                          .pushNamed('/dev/server-wardrobe-crud'),
                  child: const Text('서버 개발 옷장 열기'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
