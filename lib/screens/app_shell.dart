import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'upcoming_screen.dart';
import 'wardrobe_screen.dart';
import '../services/wardrobe_repository.dart';
import '../services/garment_photo_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.preferences,
    required this.onSave,
    required this.wardrobeRepository,
    required this.photoService,
  });
  final UserPreferences preferences;
  final Future<void> Function(UserPreferences) onSave;
  final WardrobeRepository wardrobeRepository;
  final GarmentPhotoService photoService;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  static const labels = ['홈', '내 옷장', '코디 추천', '코디 기록', '마이페이지'];
  static const icons = [
    Icons.home_outlined,
    Icons.checkroom_outlined,
    Icons.auto_awesome_outlined,
    Icons.calendar_month_outlined,
    Icons.person_outline,
  ];
  static const selectedIcons = [
    Icons.home_rounded,
    Icons.checkroom,
    Icons.auto_awesome,
    Icons.calendar_month,
    Icons.person,
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 900;
      final pages = [
        HomeScreen(
          preferences: widget.preferences,
          onNavigate: (v) => setState(() => _index = v),
        ),
        WardrobeScreen(
          repository: widget.wardrobeRepository,
          photoService: widget.photoService,
        ),
        const UpcomingScreen(
          icon: Icons.auto_awesome_outlined,
          eyebrow: 'OUTFIT FOR YOU',
          title: '오늘은 무엇을 입을까요?',
          description: '내 옷과 취향, 날씨와 외출 계획을 함께 생각하는\n나만의 AI 스타일리스트를 준비하고 있어요.',
          feature: 'AI 코디 추천',
          detail: '날씨 API와 AI 연결 후, 나에게 맞는 코디를 추천해 드릴 예정이에요.',
        ),
        const UpcomingScreen(
          icon: Icons.calendar_month_outlined,
          eyebrow: 'STYLE DIARY',
          title: '좋아했던 하루를 기록해요',
          description: '마음에 든 코디와 그날의 기분을 차곡차곡.\n나만의 스타일 기록을 남길 공간이에요.',
          feature: '코디 기록',
          detail: '오늘 입은 코디를 저장하고 날짜별로 돌아보는 기능을 준비 중이에요.',
        ),
        ProfileScreen(preferences: widget.preferences, onSave: widget.onSave),
      ];
      return Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                title: const Brand(),
                toolbarHeight: 76,
                centerTitle: false,
                automaticallyImplyLeading: false,
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (desktop) ...[
                SizedBox(
                  width: 235,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 32, 10, 40),
                        child: Brand(),
                      ),
                      Expanded(
                        child: NavigationRail(
                          extended: true,
                          minExtendedWidth: 235,
                          selectedIndex: _index,
                          onDestinationSelected: (value) =>
                              setState(() => _index = value),
                          destinations: List.generate(
                            labels.length,
                            (i) => NavigationRailDestination(
                              icon: Icon(icons[i]),
                              selectedIcon: Icon(selectedIcons[i]),
                              label: Text(labels[i]),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '나를 닮은 옷장,\n나다운 하루.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.8,
                            color: Color(0xFF777777),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.5),
                ),
              ],
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: pages
                      .map(
                        (page) => page is WardrobeScreen
                            ? page
                            : SingleChildScrollView(
                                padding: EdgeInsets.all(desktop ? 48 : 22),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1060,
                                    ),
                                    child: page,
                                  ),
                                ),
                              ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: List.generate(
                  labels.length,
                  (i) => NavigationDestination(
                    icon: Icon(icons[i]),
                    selectedIcon: Icon(selectedIcons[i]),
                    label: labels[i],
                  ),
                ),
              ),
      );
    },
  );
}
