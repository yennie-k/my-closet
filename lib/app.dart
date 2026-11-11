import 'dart:async';

import 'package:flutter/material.dart';

import 'models/user_preferences.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/preferences_service.dart';
import 'services/wardrobe_repository.dart';
import 'services/garment_photo_service.dart';
import 'services/storage/wardrobe_factory.dart';
import 'theme/app_theme.dart';
import 'services/auth_controller.dart';
import 'services/server_wardrobe_reader.dart';
import 'screens/server_wardrobe_test_screen.dart';
import 'screens/server_wardrobe_screen.dart';

class MyClosetApp extends StatefulWidget {
  const MyClosetApp({
    super.key,
    required this.store,
    this.wardrobeRepository,
    this.photoService,
    this.auth,
    this.serverReader,
    this.serverRepositoryFactory,
  });
  final PreferencesStore store;
  final WardrobeRepository? wardrobeRepository;
  final GarmentPhotoService? photoService;
  final AuthController? auth;
  final ServerWardrobeReader? serverReader;
  final ServerRepositoryFactory? serverRepositoryFactory;
  @override
  State<MyClosetApp> createState() => _MyClosetAppState();
}

class _MyClosetAppState extends State<MyClosetApp> {
  UserPreferences _preferences = const UserPreferences();
  bool _loading = true;
  bool _loadFailed = false;
  late final WardrobeRepository _wardrobe =
      widget.wardrobeRepository ?? createWardrobeRepository();
  late final GarmentPhotoService _photos =
      widget.photoService ?? FileGarmentPhotoService();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.wardrobeRepository == null) unawaited(_wardrobe.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final value = await widget.store.load();
      if (mounted) {
        setState(() {
          _preferences = value;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _save(UserPreferences value) async {
    await widget.store.save(value);
    if (mounted) setState(() => _preferences = value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Closet | 나다운 스타일의 시작',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(_preferences.design),
    routes: {
      if (widget.auth != null && widget.serverRepositoryFactory != null)
        '/dev/server-wardrobe-crud': (_) => ServerWardrobeScreen(
          auth: widget.auth!,
          repositoryFactory: widget.serverRepositoryFactory!,
          photoService: _photos,
        ),
      if (widget.auth != null && widget.serverReader != null)
        '/dev/server-wardrobe': (_) => ServerWardrobeTestScreen(
          auth: widget.auth!,
          reader: widget.serverReader!,
        ),
    },
    home: _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _loadFailed
        ? Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('설정을 불러오지 못했어요. 다시 시도해 주세요.'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('다시 시도')),
                ],
              ),
            ),
          )
        : _preferences.onboardingComplete
        ? AppShell(
            preferences: _preferences,
            onSave: _save,
            wardrobeRepository: _wardrobe,
            photoService: _photos,
            auth: widget.auth,
            serverReader: widget.serverReader,
            serverCrudEnabled: widget.serverRepositoryFactory != null,
          )
        : OnboardingScreen(
            preferences: _preferences,
            onChanged: (value) => setState(() => _preferences = value),
            onComplete: _save,
          ),
  );
}
