import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../widgets/common.dart';
import '../widgets/preference_fields.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.onComplete,
  });
  final UserPreferences preferences;
  final ValueChanged<UserPreferences> onChanged;
  final Future<void> Function(UserPreferences) onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;
  final ScrollController _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _next() async {
    if (_step < 4) {
      _move(_step + 1);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete(
        widget.preferences.copyWith(onboardingComplete: true),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '저장하지 못했어요. 브라우저의 저장 공간을 확인하고 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preferences;
    final titles = [
      '나를 닮은 옷장,\n나다운 하루.',
      '어떤 분위기가\n당신과 닮았나요?',
      '당신이 좋아하는\n스타일을 알려주세요.',
      '같은 날씨에도\n느낌은 다르니까요.',
      '나만의 옷장,\n준비가 끝났어요.',
    ];
    final descriptions = [
      '내 옷에서 시작하는 나만의 스타일.\n취향과 날씨, 하루의 계획을 담을 AI 옷장을 만나보세요.',
      '매일 열어보고 싶은 옷장을 골라보세요.\n선택한 디자인이 앱 전체에 바로 적용돼요.',
      '마음이 가는 스타일을 모두 골라보세요.\n취향은 하나로 정하지 않아도 괜찮아요.',
      '평소 온도를 어떻게 느끼시나요?\n당신에게 더 편안한 코디를 위한 첫걸음이에요.',
      '선택한 취향을 기억해 둘게요.\n마이페이지에서 언제든 다시 바꿀 수 있어요.',
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Brand(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_step > 0 || MediaQuery.sizeOf(context).width >= 600)
                    Text(
                      _step == 0 ? 'YOUR EVERYDAY, STYLED.' : '0$_step / 04',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_step > 0) ...[
                          LinearProgressIndicator(
                            value: _step / 4,
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 32),
                        ],
                        Text(
                          _step == 0
                              ? 'A LITTLE MORE YOU'
                              : [
                                  '',
                                  '01  /  MY SPACE',
                                  '02  /  MY STYLE',
                                  '03  /  MY COMFORT',
                                  '04  /  ALL SET',
                                ][_step],
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.4,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          titles[_step],
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          descriptions[_step],
                          style: TextStyle(
                            height: 1.8,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_step == 0) const _WelcomeArt(),
                        if (_step == 1) ...[
                          DesignSelector(
                            value: p.design,
                            onChanged: (v) =>
                                widget.onChanged(p.copyWith(design: v)),
                          ),
                          const SizedBox(height: 20),
                          SurfaceCard(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            child: Row(
                              children: [
                                const Icon(Icons.palette_outlined),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    '${p.design.label} 미리보기\n이 분위기로 나만의 옷장을 채워보세요.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_step == 2) ...[
                          StyleSelector(
                            values: p.styles,
                            onChanged: (v) =>
                                widget.onChanged(p.copyWith(styles: v)),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            p.styles.isEmpty
                                ? '한 가지 이상 선택해 주세요.'
                                : '${p.styles.length}개의 취향을 골랐어요.',
                          ),
                        ],
                        if (_step == 3)
                          TemperatureSelector(
                            value: p.temperature,
                            onChanged: (v) =>
                                widget.onChanged(p.copyWith(temperature: v)),
                          ),
                        if (_step == 4) PreferenceSummary(preferences: p),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            if (_step > 0) ...[
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => _move(_step - 1),
                                child: const Text('이전'),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed:
                                    _saving || (_step == 2 && p.styles.isEmpty)
                                    ? null
                                    : _next,
                                child: Text(
                                  _saving
                                      ? '저장 중…'
                                      : _step == 0
                                      ? '시작하기'
                                      : _step == 4
                                      ? '내 옷장 시작하기'
                                      : '다음',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Center(
                          child: Text(
                            '오늘의 나를 위한, 작은 취향의 시작',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF777777),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();
  @override
  Widget build(BuildContext context) => SurfaceCard(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Column(
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final icon in [
              Icons.checkroom_outlined,
              Icons.dry_cleaning_outlined,
              Icons.shopping_bag_outlined,
            ])
              Flexible(
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 30,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: Icon(
                    icon,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'LESS 고민, MORE 나다움',
          style: TextStyle(fontSize: 12, letterSpacing: 1.5),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}
