import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_controller.dart';
import '../services/garment_photo_service.dart';
import '../services/wardrobe_repository.dart';
import '../widgets/common.dart';
import '../widgets/editor_exit_scope.dart';
import 'auth_screen.dart';
import 'wardrobe_screen.dart';

typedef ServerRepositoryFactory = WardrobeRepository Function(
  String userId,
  int generation,
);

class ServerWardrobeScreen extends StatefulWidget {
  const ServerWardrobeScreen({
    super.key,
    required this.auth,
    required this.repositoryFactory,
    required this.photoService,
  });
  final AuthController auth;
  final ServerRepositoryFactory repositoryFactory;
  final GarmentPhotoService photoService;

  @override
  State<ServerWardrobeScreen> createState() => _ServerWardrobeScreenState();
}

class _ServerWardrobeScreenState extends State<ServerWardrobeScreen> {
  final _editorExit = EditorExitCoordinator();
  var _workspaceNavigation = GlobalKey<NavigatorState>();
  String? _workspaceIdentity;
  AuthController get auth => widget.auth;
  ServerRepositoryFactory get repositoryFactory => widget.repositoryFactory;
  GarmentPhotoService get photoService => widget.photoService;

  Future<void> _closeWorkspace() async {
    if (await _editorExit.requestExit() && mounted) Navigator.of(context).pop();
  }

  Future<void> _back() async {
    final navigator = _workspaceNavigation.currentState;
    if (navigator != null && navigator.canPop()) {
      await navigator.maybePop();
    } else {
      await _closeWorkspace();
    }
  }

  Future<void> _signOut() async {
    if (await _editorExit.requestExit() && mounted) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) => EditorExitScope(
    coordinator: _editorExit,
    child: PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final identity = auth.user == null
              ? null
              : '${auth.user!.id}:${auth.generation}';
          if (identity != _workspaceIdentity) {
            _workspaceIdentity = identity;
            // Never reparent an old user's Navigator into the new workspace.
            _workspaceNavigation = GlobalKey<NavigatorState>();
          }
          return Scaffold(
            appBar: AppBar(
              leading: Navigator.canPop(context)
                  ? BackButton(onPressed: _back)
                  : null,
              title: const Text('서버 개발 옷장'),
              actions: [
                if (auth.user != null)
                  IconButton(
                    tooltip: '서버 로그아웃',
                    onPressed: auth.busy ? null : _signOut,
                    icon: const Icon(Icons.logout),
                  ),
              ],
            ),
            body: SafeArea(
              child: Row(
                children: [
                  if (MediaQuery.sizeOf(context).width >= 1100) ...[
                    SizedBox(
                      width: 220,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Brand(),
                            const SizedBox(height: 36),
                            const Text('로컬 Supabase\n개발 전용 저장 공간'),
                            const SizedBox(height: 20),
                            OutlinedButton(
                              onPressed: _closeWorkspace,
                              child: const Text('이 기기 옷장으로 돌아가기'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.user == null
                                    ? '서버 옷장 · 로그인이 필요해요.'
                                    : '서버 옷장 · ${auth.user!.email}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                '127.0.0.1:54321 · 서버 개발 전용 · 기존 로컬 옷은 자동 이전하지 않아요.',
                                style: TextStyle(fontSize: 12),
                              ),
                              if (auth.error != null) Text(auth.error!),
                            ],
                          ),
                        ),
                        Expanded(
                          child: auth.restoring
                              ? const Center(child: CircularProgressIndicator())
                              : auth.user == null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(22),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.lock_outline,
                                          size: 44,
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          '로그인 후 서버 의류 정보를 관리할 수 있어요.',
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                          onPressed:
                                              auth.busy || !auth.available
                                              ? null
                                              : () => Navigator.of(context)
                                                    .push(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            AuthScreen(
                                                              auth: auth,
                                                            ),
                                                      ),
                                                    ),
                                          child: const Text('로그인 / 회원가입'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : _ServerWorkspace(
                                  // Destroy the whole nested navigation stack on sign-out/account
                                  // change, including an open detail/editor and its private draft.
                                  key: ValueKey(
                                    '${auth.user!.id}:${auth.generation}',
                                  ),
                                  repositoryFactory: () => repositoryFactory(
                                    auth.user!.id,
                                    auth.generation,
                                  ),
                                  photoService: photoService,
                                  navigatorKey: _workspaceNavigation,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ServerWorkspace extends StatefulWidget {
  const _ServerWorkspace({
    super.key,
    required this.repositoryFactory,
    required this.photoService,
    required this.navigatorKey,
  });
  final WardrobeRepository Function() repositoryFactory;
  final GarmentPhotoService photoService;
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  State<_ServerWorkspace> createState() => _ServerWorkspaceState();
}

class _ServerWorkspaceState extends State<_ServerWorkspace> {
  late final WardrobeRepository _repository = widget.repositoryFactory();
  @override
  void dispose() {
    unawaited(_repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: widget.navigatorKey,
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: WardrobeScreen(
          repository: _repository,
          photoService: widget.photoService,
        ),
      ),
    ),
  );
}
