import 'package:flutter/material.dart';

import '../models/user_preferences.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class DesignSelector extends StatelessWidget {
  const DesignSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final AppDesign value;
  final ValueChanged<AppDesign> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 440;
      final cards = AppDesign.values.map((design) {
        final p = DesignPalette.of(design);
        final selected = value == design;
        return Semantics(
          selected: selected,
          child: InkWell(
            key: ValueKey('design-${design.name}'),
            onTap: () => onChanged(design),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? p.accent
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          design.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                      ),
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: p.accent,
                        size: 21,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    design.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF555555),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: p.soft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(Icons.checkroom_outlined, color: p.accent),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final color in [p.accent, p.soft, p.background])
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFCCCCCC)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList();
      return stacked
          ? Column(
              children: [
                for (final card in cards)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            );
    },
  );
}

class StyleSelector extends StatelessWidget {
  const StyleSelector({
    super.key,
    required this.values,
    required this.onChanged,
  });
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: fashionStyles
        .map(
          (style) => FilterChip(
            label: Text(style),
            selected: values.contains(style),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onSelected: (selected) => onChanged(
              selected
                  ? [...values, style]
                  : values.where((v) => v != style).toList(),
            ),
          ),
        )
        .toList(),
  );
}

class TemperatureSelector extends StatelessWidget {
  const TemperatureSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final TemperaturePreference value;
  final ValueChanged<TemperaturePreference> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: TemperaturePreference.values
        .map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              selected: value == option,
              child: InkWell(
                onTap: () => onChanged(option),
                borderRadius: BorderRadius.circular(20),
                child: SurfaceCard(
                  color: value == option
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(switch (option) {
                        TemperaturePreference.cold => Icons.ac_unit,
                        TemperaturePreference.normal => Icons.thermostat,
                        TemperaturePreference.hot => Icons.wb_sunny_outlined,
                      }),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              option.description,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        value == option
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
}

class PreferenceSummary extends StatelessWidget {
  const PreferenceSummary({super.key, required this.preferences});
  final UserPreferences preferences;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      children: [
        _row('앱 디자인', preferences.design.label),
        const Divider(height: 32),
        _row('패션 추구미', preferences.styles.join(' · ')),
        const Divider(height: 32),
        _row('체감온도', preferences.temperature.label),
      ],
    ),
  );
  Widget _row(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 100, child: Text(label)),
      Expanded(
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
}
