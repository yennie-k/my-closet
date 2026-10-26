import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.preferences,
    required this.onNavigate,
  });
  final UserPreferences preferences;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        eyebrow: 'YOUR EVERYDAY, STYLED.',
        title: '오늘도, 나답게 입어요.',
        description: '반가워요. 나만의 취향으로 채워 갈 옷장에 오신 걸 환영해요.',
      ),
      const SizedBox(height: 32),
      SurfaceCard(
        color: Theme.of(context).colorScheme.secondaryContainer,
        padding: const EdgeInsets.all(30),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MY DIGITAL WARDROBE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '내 옷장에서 찾는\n새로운 가능성',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('가지고 있는 옷에 취향을 더하면,\n매일의 코디가 조금 더 쉬워질 거예요.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onNavigate(1),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('내 옷장 둘러보기'),
                ),
              ],
            );
            return Row(
              children: [
                Expanded(child: text),
                if (constraints.maxWidth > 580) ...[
                  const SizedBox(width: 24),
                  Container(
                    width: 210,
                    height: 230,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Icon(
                      Icons.checkroom_outlined,
                      size: 116,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: Text(
              '나의 스타일 프로필',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton(onPressed: () => onNavigate(4), child: const Text('수정하기')),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: MediaQuery.sizeOf(context).width < 900 ? double.infinity : null,
        key: const ValueKey('style-profile-card'),
        child: SurfaceCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final items = [
                _profileInfo(
                  context,
                  Icons.palette_outlined,
                  '앱 디자인',
                  preferences.design.label,
                ),
                _profileInfo(
                  context,
                  Icons.favorite_border,
                  '패션 추구미',
                  preferences.styles.join(' · '),
                ),
                _profileInfo(
                  context,
                  Icons.thermostat_outlined,
                  '체감온도',
                  preferences.temperature.label,
                ),
              ];
              if (MediaQuery.sizeOf(context).width < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 32),
                      items[i],
                    ],
                  ],
                );
              }
              return Wrap(spacing: 28, runSpacing: 20, children: items);
            },
          ),
        ),
      ),
      const SizedBox(height: 32),
      Text('당신의 하루를 위한 준비', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 640;
          final cards = [
            _feature(
              context,
              Icons.wb_sunny_outlined,
              '오늘의 날씨',
              '날씨와 체감온도를 함께 살펴봐요.',
              null,
            ),
            _feature(
              context,
              Icons.auto_awesome_outlined,
              '나를 위한 코디',
              '취향과 외출 계획에 맞는 한 벌.',
              2,
            ),
            _feature(
              context,
              Icons.calendar_month_outlined,
              '코디 기록',
              '좋았던 스타일을 오래 기억해요.',
              3,
            ),
          ];
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: cards[i]),
                    ],
                  ],
                )
              : Column(
                  children: [
                    for (final card in cards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: card,
                      ),
                  ],
                );
        },
      ),
      const SizedBox(height: 24),
      const Text(
        'MY CLOSET  /  작은 취향이 모여 나다운 스타일이 됩니다.',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.8,
          color: Color(0xFF777777),
        ),
      ),
    ],
  );

  Widget _profileInfo(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 180, maxWidth: 400),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Color(0xFF777777)),
              ),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _feature(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    int? destination,
  ) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            const ComingSoonBadge(),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(description),
        const SizedBox(height: 18),
        if (destination != null)
          TextButton(
            onPressed: () => onNavigate(destination),
            child: const Text('살펴보기 →'),
          )
        else
          const Text(
            '날씨 API 연결 예정',
            style: TextStyle(fontSize: 12, color: Color(0xFF777777)),
          ),
      ],
    ),
  );
}
