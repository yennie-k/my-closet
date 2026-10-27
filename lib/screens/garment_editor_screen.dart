import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/garment_options.dart';
import '../models/user_preferences.dart';
import '../services/garment_photo_service.dart';
import '../services/wardrobe_repository.dart';
import '../widgets/common.dart';
import '../widgets/garment_photo.dart';
import '../widgets/garment_input_fields.dart';

class GarmentEditorScreen extends StatefulWidget {
  const GarmentEditorScreen({
    super.key,
    required this.repository,
    required this.photoService,
    this.garment,
  });
  final WardrobeRepository repository;
  final GarmentPhotoService photoService;
  final Garment? garment;
  @override
  State<GarmentEditorScreen> createState() => _GarmentEditorScreenState();
}

class _GarmentEditorScreenState extends State<GarmentEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _subtype, _primaryColor, _fit, _notes;
  GarmentCategory? _category;
  GarmentThickness? _thickness;
  late List<Season> _seasons;
  late List<String> _styles;
  late List<String> _additionalColors, _materials;
  ProcessedPhoto? _photo;
  bool _existingPhoto = false, _busy = false, _picking = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final g = widget.garment;
    _name = TextEditingController(text: g?.name);
    _subtype = TextEditingController(text: g?.subtype);
    _primaryColor = TextEditingController(text: g?.primaryColor);
    _additionalColors = [...?g?.additionalColors];
    _materials = [...?g?.materials];
    _fit = TextEditingController(text: g?.fit);
    _notes = TextEditingController(text: g?.notes);
    _category = g?.category;
    _thickness = g?.thickness;
    _seasons = [...?g?.seasons];
    _styles = [...?g?.styleTags];
    _existingPhoto = g != null;
  }

  @override
  void dispose() {
    for (final c in [_name, _subtype, _primaryColor, _fit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await widget.photoService.pick();
      if (mounted && photo != null) {
        setState(() {
          _photo = photo;
          _existingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is WardrobeException
              ? e.message
              : '사진 선택을 열지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    if (!valid || (_photo == null && !_existingPhoto)) {
      setState(() => _error = '의류 이름, 카테고리, 사진과 입력한 값을 확인해 주세요.');
      return;
    }
    _form.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = widget.garment;
    final now = DateTime.now().toUtc();
    var garment = Garment(
      id: old?.id ?? Garment.newId(),
      name: _name.text.trim(),
      category: _category!,
      createdAt: old?.createdAt ?? now,
      updatedAt: old?.updatedAt ?? now,
      subtype: _subtype.text.trim(),
      primaryColor: _primaryColor.text.trim(),
      additionalColors: _additionalColors
          .where((v) => !sameColorName(v, _primaryColor.text))
          .toList(),
      seasons: _seasons,
      thickness: _thickness,
      styleTags: _styles,
      material: old?.material ?? _materials.join(' · '),
      materials: _materials,
      fit: _fit.text.trim(),
      notes: _notes.text.trim(),
      imageWidth: _photo?.width ?? old!.imageWidth,
      imageHeight: _photo?.height ?? old!.imageHeight,
      imageMimeType: _photo == null
          ? old?.imageMimeType ?? 'image/jpeg'
          : 'image/jpeg',
    );
    try {
      if (old != null &&
          _photo == null &&
          jsonEncode(old.toJson()) == jsonEncode(garment.toJson())) {
        if (mounted) Navigator.pop(context, old);
        return;
      }
      garment = Garment.fromJson({
        ...garment.toJson(),
        'updatedAt': now.toIso8601String(),
      });
      await widget.repository.save(garment, imageBytes: _photo?.bytes);
      if (mounted) Navigator.pop(context, garment);
    } catch (e) {
      if (mounted) setState(() => _error = wardrobeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_picking,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.garment == null ? '새로운 옷 등록' : '옷 정보 수정'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: AbsorbPointer(
                absorbing: _busy || _picking,
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '사진과 함께, 내 옷장에 한 벌 더.',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('* 표시는 필수 항목이에요.'),
                      const SizedBox(height: 24),
                      SurfaceCard(
                        child: Column(
                          children: [
                            SizedBox(
                              height: 250,
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _photo != null
                                    ? Image.memory(
                                        _photo!.bytes,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) =>
                                            const PhotoError(),
                                      )
                                    : _existingPhoto
                                    ? GarmentPhoto(
                                        garment: widget.garment!,
                                        repository: widget.repository,
                                        fit: BoxFit.contain,
                                      )
                                    : const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                              size: 56,
                                            ),
                                            SizedBox(height: 12),
                                            Text('내 옷 사진 *'),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pick,
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: Text(
                                    _picking
                                        ? '사진 처리 중…'
                                        : _photo != null || _existingPhoto
                                        ? '사진 변경'
                                        : '사진 선택',
                                  ),
                                ),
                                if (_photo != null || _existingPhoto)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _photo = null;
                                      _existingPhoto = false;
                                    }),
                                    child: const Text('사진 삭제'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'JPG · PNG · WebP / 최대 15MB\n최대 1,600px로 줄여 JPEG로 저장해요. 투명 배경은 흰색으로 바뀌어요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _field(
                        _name,
                        '의류 이름 *',
                        hint: '예: 아이보리 코튼 셔츠',
                        required: true,
                      ),
                      DropdownButtonFormField<GarmentCategory>(
                        key: const ValueKey('category-field'),
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '카테고리 *',
                          border: OutlineInputBorder(),
                        ),
                        items: GarmentCategory.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _category = v),
                        validator: (v) => v == null ? '카테고리를 선택해 주세요.' : null,
                      ),
                      const SizedBox(height: 20),
                      GarmentInputSection(
                        id: 'subtype',
                        title: '세부 종류',
                        summary: _subtype.text.isEmpty
                            ? '카테고리별 추천 또는 직접 입력'
                            : _subtype.text,
                        initiallyExpanded: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '카테고리를 바꿔도 입력한 값은 유지돼요.',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            SuggestedTextField(
                              controller: _subtype,
                              label: '세부 종류 직접 입력',
                              suggestions: subtypeSuggestions[_category] ?? [],
                              onChanged: () => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      GarmentInputSection(
                        id: 'colors',
                        title: '색상',
                        summary:
                            '대표: ${_primaryColor.text.isEmpty ? '미선택' : _primaryColor.text} / 추가: ${_additionalColors.isEmpty ? '없음' : _additionalColors.join(' · ')}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '대표 색상 · 한 가지',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            GarmentColorPalette(
                              id: 'primary',
                              selected: [_primaryColor.text],
                              onToggle: (v) =>
                                  _setPrimary(_primaryColor.text == v ? '' : v),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _primaryColor,
                              maxLength: 80,
                              onChanged: _setPrimary,
                              decoration: const InputDecoration(
                                labelText: '대표 색상',
                                helperText: '팔레트에 없는 색상도 직접 입력할 수 있어요.',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              '추가 색상 · 여러 가지',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            GarmentColorPalette(
                              id: 'additional',
                              selected: _additionalColors,
                              excluded: _primaryColor.text,
                              onToggle: (v) => setState(() {
                                _additionalColors =
                                    _additionalColors.contains(v)
                                    ? _additionalColors
                                          .where((x) => x != v)
                                          .toList()
                                    : [..._additionalColors, v];
                              }),
                            ),
                            const SizedBox(height: 16),
                            CustomValuesInput(
                              id: 'additional',
                              label: '추가 색상 직접 입력',
                              hint: '예: 차콜, 카키',
                              values: _additionalColors,
                              excluded: _primaryColor.text,
                              onChanged: (v) =>
                                  setState(() => _additionalColors = v),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        '계절',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: Season.values
                            .map(
                              (v) => FilterChip(
                                label: Text(v.label),
                                selected: _seasons.contains(v),
                                onSelected: (selected) => setState(() {
                                  selected
                                      ? _seasons.add(v)
                                      : _seasons.remove(v);
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      GarmentInputSection(
                        id: 'thickness',
                        title: '두께',
                        summary: _thickness == null
                            ? '선택 안 함 · 보온성과는 달라요'
                            : '${_thickness!.level}/5 · ${_thickness!.label}',
                        child: ThicknessSelector(
                          value: _thickness,
                          onChanged: (v) => setState(() => _thickness = v),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '스타일 태그',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: fashionStyles
                            .map(
                              (v) => FilterChip(
                                label: Text(v),
                                selected: _styles.contains(v),
                                onSelected: (selected) => setState(() {
                                  selected ? _styles.add(v) : _styles.remove(v);
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      GarmentInputSection(
                        id: 'materials',
                        title: '소재',
                        summary: _materials.isEmpty
                            ? '복수 선택 · 혼방 비율 직접 입력 가능'
                            : _materials.join(' · '),
                        child: MaterialSelector(
                          values: _materials,
                          onChanged: (v) => setState(() => _materials = v),
                        ),
                      ),
                      GarmentInputSection(
                        id: 'fit',
                        title: '핏',
                        summary: _fit.text.isEmpty
                            ? '실루엣을 보고 선택하거나 직접 입력'
                            : _fit.text,
                        child: FitSelector(
                          controller: _fit,
                          category: _category,
                          subtype: _subtype.text,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      _field(_notes, '메모', max: 2000, lines: 4),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            key: const ValueKey('editor-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: Text(_busy ? '저장 중…' : '옷 저장하기'),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _setPrimary(String value) {
    setState(() {
      if (_primaryColor.text != value) _primaryColor.text = value;
      _additionalColors = _additionalColors
          .where((v) => !sameColorName(v, value))
          .toList();
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    int max = 80,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      maxLength: max,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (value) => required && (value == null || value.trim().isEmpty)
          ? '의류 이름을 입력해 주세요.'
          : null,
    ),
  );
}
