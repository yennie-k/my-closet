import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/garment_options.dart';
import 'garment_illustrations.dart';

class GarmentInputSection extends StatelessWidget {
  const GarmentInputSection({
    super.key,
    required this.id,
    required this.title,
    required this.summary,
    required this.child,
    this.initiallyExpanded = false,
  });
  final String id, title, summary;
  final Widget child;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('section-$id'),
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [SizedBox(width: double.infinity, child: child)],
      ),
    ),
  );
}

class SuggestedTextField extends StatelessWidget {
  const SuggestedTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    required this.onChanged,
    required this.selectedValue,
    required this.onApply,
    required this.onSuggestionSelected,
    this.errorText,
  });
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final VoidCallback onChanged;
  final String selectedValue;
  final String? errorText;
  final VoidCallback onApply;
  final ValueChanged<String> onSuggestionSelected;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        controller: controller,
        onChanged: (_) => onChanged(),
        onFieldSubmitted: (_) => onApply(),
        maxLength: 80,
        decoration: InputDecoration(
          labelText: label,
          helperText: '추천 선택 또는 직접 입력 후 종류 적용',
          helperMaxLines: 2,
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
      ),
      if (controller.text != selectedValue)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('apply-subtype'),
            onPressed: onApply,
            icon: const Icon(Icons.check),
            label: const Text('종류 적용'),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: suggestions
            .map(
              (v) => FilterChip(
                label: Text(v),
                selected: selectedValue == v,
                onSelected: (selected) {
                  onSuggestionSelected(selected ? v : '');
                },
              ),
            )
            .toList(),
      ),
    ],
  );
}

class GarmentColorPalette extends StatelessWidget {
  const GarmentColorPalette({
    super.key,
    required this.id,
    required this.selected,
    required this.onToggle,
    this.excluded = '',
  });
  final String id, excluded;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 10,
    children: garmentColors.map((color) {
      final chosen = selected.any((v) => sameColorName(v, color.name));
      final disabled =
          excluded.isNotEmpty && sameColorName(excluded, color.name);
      final paintColor = Color(
        int.parse(color.hex.substring(1), radix: 16) | 0xFF000000,
      );
      return Semantics(
        label: '${color.name}${disabled ? ', 대표 색상과 같음' : ''}',
        selected: chosen,
        enabled: !disabled,
        button: true,
        child: Tooltip(
          message: '${color.name} ${color.hex}${disabled ? ' · 대표 색상' : ''}',
          child: InkWell(
            key: ValueKey('$id-${color.name}'),
            onTap: disabled ? null : () => onToggle(color.name),
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: MediaQuery.textScalerOf(context).scale(12) * 4 + 24,
              height:
                  MediaQuery.textScalerOf(context).scale(14) +
                  MediaQuery.textScalerOf(context).scale(12) +
                  64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: chosen
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: chosen ? 3 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: paintColor.withValues(
                          alpha: disabled ? 0.35 : 1,
                        ),
                      ),
                      child: chosen
                          ? Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check,
                                  size: 20,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                              ),
                            )
                          : disabled
                          ? const Icon(Icons.remove, size: 18)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(color.name, style: const TextStyle(fontSize: 12)),
                  Text(
                    chosen
                        ? '선택됨'
                        : disabled
                        ? '대표 색상'
                        : '',
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class CustomValuesInput extends StatefulWidget {
  const CustomValuesInput({
    super.key,
    required this.id,
    required this.label,
    required this.values,
    required this.onChanged,
    this.excluded = '',
    this.hint,
    this.onPendingChanged,
  });
  final String id, label, excluded;
  final String? hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<String>? onPendingChanged;
  @override
  State<CustomValuesInput> createState() => _CustomValuesInputState();
}

class _CustomValuesInputState extends State<CustomValuesInput> {
  final _text = TextEditingController();
  String? _error;
  String _lastText = '';
  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (_lastText == _text.text) return;
      _lastText = _text.text;
      widget.onPendingChanged?.call(_lastText);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    if (widget.excluded.isNotEmpty && sameColorName(value, widget.excluded)) {
      setState(() => _error = '대표 색상과 다른 색상을 입력해 주세요.');
      return;
    }
    if (!widget.values.any((v) => sameColorName(value, v))) {
      widget.onChanged([...widget.values, value]);
    }
    _text.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.values.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.values
              .map(
                (v) => InputChip(
                  label: Text(v),
                  tooltip: '$v 선택 해제',
                  onDeleted: () => widget.onChanged(
                    widget.values.where((x) => x != v).toList(),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
      TextFormField(
        key: ValueKey('${widget.id}-custom'),
        controller: _text,
        maxLength: 120,
        onFieldSubmitted: (_) => _add(),
        onSaved: (_) => _add(),
        validator: (value) =>
            value != null &&
                value.trim().isNotEmpty &&
                widget.excluded.isNotEmpty &&
                sameColorName(value, widget.excluded)
            ? '대표 색상과 다른 색상을 입력해 주세요.'
            : null,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: ValueKey('${widget.id}-add'),
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('입력한 값 추가'),
        ),
      ),
    ],
  );
}

class MaterialSelector extends StatelessWidget {
  const MaterialSelector({
    super.key,
    required this.values,
    required this.onChanged,
    this.onPendingChanged,
  });
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<String>? onPendingChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '질감 그림은 직접 그린 참고 일러스트이며 실제 원단 사진이 아니에요.\n같은 소재도 조직·가공·혼방에 따라 촉감이 달라져요.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 16),
      CustomValuesInput(
        id: 'materials',
        label: '소재 직접 입력',
        hint: '예: 면 70% / 폴리에스터 30%',
        values: values,
        onChanged: onChanged,
        onPendingChanged: onPendingChanged,
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: materialOptions.map((option) {
            final selected = values.contains(option.name);
            return SizedBox(
              width: constraints.maxWidth < 520
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2,
              child: _IllustratedChoice(
                id: 'material-${option.name}',
                title: option.name,
                description: option.description,
                selected: selected,
                onTap: () => onChanged(
                  selected
                      ? values.where((v) => v != option.name).toList()
                      : [...values, option.name],
                ),
                illustration: CustomPaint(
                  size: const Size(48, 48),
                  painter: FabricPatternPainter(
                    option.pattern,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ],
  );
}

class FitSelector extends StatelessWidget {
  const FitSelector({
    super.key,
    required this.controller,
    required this.category,
    required this.onChanged,
    this.subtype = '',
  });
  final TextEditingController controller;
  final GarmentCategory? category;
  final String subtype;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final options = fitsForCategory(category, subtype: subtype);
    final review = needsFitReview(category, subtype, controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          onChanged: (_) => onChanged(),
          maxLength: 80,
          decoration: InputDecoration(
            labelText: '핏',
            helperMaxLines: 3,
            helperText: options.isEmpty
                ? '선택 사항 · 기존 값 유지 및 직접 입력 가능'
                : '일러스트 선택 또는 직접 입력',
            border: OutlineInputBorder(),
          ),
        ),
        if (review)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '현재 분류의 추천에 없는 핏이에요. 기존 값·직접 입력값은 유지돼요. 변경 내용을 저장할 때 이 값을 유지할지 확인해요.',
              key: const ValueKey('fit-review-notice'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              category == null
                  ? '카테고리를 선택하면 맞는 핏 추천을 볼 수 있어요.'
                  : '이 카테고리는 핏 추천을 생략해요. 입력하지 않아도 괜찮아요.',
            ),
          ),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${fitContextLabel(category, subtype)} 기준 실루엣 · 참고 일러스트',
            key: const ValueKey('fit-context-label'),
          ),
          const Text(
            '실제 착용 모습은 체형과 옷의 치수에 따라 달라요.',
            style: TextStyle(fontSize: 12),
          ),
          if (fitContextFor(category, subtype) == FitContext.set)
            const Text(
              '그림의 구성품은 예시예요. 구성품마다 핏이 다르면 메모에 적어 주세요.',
              style: TextStyle(fontSize: 12),
            ),
          if (fitContextFor(category, subtype) == FitContext.puffer)
            const Text(
              '패딩의 부피감과 몸에 맞는 여유는 달라요. 충전재가 있어도 오버핏인 것은 아니에요.',
              style: TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options
                  .map(
                    (option) => SizedBox(
                      width: constraints.maxWidth < 520
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 10) / 2,
                      child: _IllustratedChoice(
                        id: 'fit-${option.name}',
                        title: option.name,
                        description: option.description,
                        selected: controller.text == option.name,
                        onTap: () {
                          controller.text = controller.text == option.name
                              ? ''
                              : option.name;
                          onChanged();
                        },
                        illustration: CustomPaint(
                          size: const Size(48, 62),
                          painter: FitSilhouettePainter(
                            option.name,
                            category,
                            Theme.of(context).colorScheme.primary,
                            subtype: subtype,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _IllustratedChoice extends StatelessWidget {
  const _IllustratedChoice({
    required this.id,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    required this.illustration,
  });
  final String id, title, description;
  final bool selected;
  final VoidCallback onTap;
  final Widget illustration;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey(id),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(minHeight: 94),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: illustration),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title${selected ? ' · 선택됨' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class ThicknessSelector extends StatelessWidget {
  const ThicknessSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.category,
  });
  final GarmentThickness? value;
  final ValueChanged<GarmentThickness?> onChanged;
  final GarmentCategory? category;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        [
              GarmentCategory.shoes,
              GarmentCategory.bags,
              GarmentCategory.accessories,
              GarmentCategory.other,
            ].contains(category)
            ? '두께는 선택 사항이에요. 원단·재질의 두께를 비교하기 어렵다면 비워 두세요.\n굽 높이·밑창 높이·가방 크기를 뜻하지 않아요. 두께는 보온성 점수가 아니에요.'
            : '원단이 얼마나 두툼한지 골라주세요.\n두께는 보온성 점수가 아니며, 소재·충전재 등에 따라 따뜻함은 달라요.',
      ),
      const SizedBox(height: 12),
      ...GarmentThickness.values.map(
        (option) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _IllustratedChoice(
            id: 'thickness-${option.level}',
            title: '${option.level}. ${option.label}',
            description: thicknessExample(option, category),
            selected: value == option,
            onTap: () => onChanged(value == option ? null : option),
            illustration: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Container(
                  width: 32,
                  height: 3.0 + option.level * 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      TextButton(
        onPressed: () => onChanged(null),
        child: const Text('두께 선택 해제'),
      ),
    ],
  );
}
