import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/garment_options.dart';
import '../models/user_preferences.dart';
import '../services/garment_photo_service.dart';
import '../services/wardrobe_repository.dart';
import '../services/revisioned_wardrobe_repository.dart';
import '../services/server_photo_repository.dart';
import '../widgets/common.dart';
import '../widgets/garment_photo.dart';
import '../widgets/garment_input_fields.dart';
import '../widgets/garment_edit_rules.dart';
import '../widgets/browser_exit_guard.dart';
import '../widgets/editor_exit_scope.dart';

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
  bool get metadataOnly => repository is MetadataOnlyWardrobeRepository;
  @override
  State<GarmentEditorScreen> createState() => _GarmentEditorScreenState();
}

class _GarmentEditorScreenState extends State<GarmentEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _categoryField = GlobalKey<FormFieldState<GarmentCategory>>();
  late final TextEditingController _name,
      _subtype,
      _subtypeInput,
      _primaryColor,
      _fit,
      _notes;
  GarmentCategory? _category;
  GarmentThickness? _thickness;
  late List<Season> _seasons;
  late List<String> _styles;
  late List<String> _additionalColors, _materials;
  ProcessedPhoto? _photo;
  bool _existingPhoto = false, _busy = false, _picking = false;
  bool _changingClassification = false;
  String? _classificationNotice, _subtypeError;
  String? _error;
  late final String _draftId;
  late final DateTime _draftCreatedAt;
  Garment? _persisted;
  String? _progress;
  final _browserExit = BrowserExitGuard();
  EditorExitCoordinator? _exitCoordinator;
  late final String _initialDraft;
  String _pendingAdditional = '', _pendingMaterial = '';
  ProcessedPhoto? _fingerprintedPhoto;
  String? _photoFingerprint;
  bool _allowLeave = false, _exitDialogOpen = false;
  bool get _working => _busy || _picking || _changingClassification;
  bool get _hasChanges => _draftSnapshot() != _initialDraft;
  bool get _serverPhotos => widget.repository is ServerPhotoRepository;

  List<String> _unordered(Iterable<String> values) => values.toList()..sort();

  String _draftSnapshot() {
    if (!identical(_fingerprintedPhoto, _photo)) {
      _fingerprintedPhoto = _photo;
      _photoFingerprint = _photo == null
          ? null
          : sha256.convert(_photo!.bytes).toString();
    }
    return jsonEncode({
      'name': _name.text,
      'category': _category?.name,
      'subtype': _subtype.text,
      'subtypeInput': _subtypeInput.text,
      'primaryColor': _primaryColor.text,
      'additionalColors': _unordered(_additionalColors),
      'pendingAdditional': _pendingAdditional,
      'seasons': _unordered(_seasons.map((v) => v.name)),
      'thickness': _thickness?.level,
      'styles': _unordered(_styles),
      'materials': _unordered(_materials),
      'pendingMaterial': _pendingMaterial,
      'fit': _fit.text,
      'notes': _notes.text,
      'existingPhoto': _existingPhoto,
      'selectedPhoto': _photoFingerprint,
    });
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _requestExit() async {
    if (_allowLeave) return true;
    if (_working || _exitDialogOpen) return false;
    if (!_hasChanges) return true;
    _exitDialogOpen = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('변경사항이 저장되지 않았어요'),
              content: const Text('저장하지 않고 나가면 이번에 변경한 내용이 사라집니다. 정말 나가시겠어요?'),
              actions: [
                TextButton(
                  key: const ValueKey('continue-editing'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('계속 수정'),
                ),
                FilledButton(
                  key: const ValueKey('discard-changes'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('저장하지 않고 나가기'),
                ),
              ],
            ),
          ) ==
          true;
    } finally {
      _exitDialogOpen = false;
    }
  }

  Future<void> _tryLeave() async {
    if (await _requestExit() && mounted) _finishLeave(_persisted);
  }

  void _finishLeave(Garment? result) {
    // Called only after explicit discard, unchanged save, or ALL save work succeeds.
    _allowLeave = true;
    _browserExit.update(false);
    if (mounted) Navigator.pop(context, result);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = EditorExitScope.maybeOf(context);
    if (!identical(coordinator, _exitCoordinator)) {
      _exitCoordinator?.unregister(this);
      _exitCoordinator = coordinator;
      coordinator?.register(this, _requestExit);
    }
  }

  @override
  void initState() {
    super.initState();
    final g = widget.garment;
    _draftId = g?.id ?? Garment.newId();
    _draftCreatedAt = g?.createdAt ?? DateTime.now().toUtc();
    _name = TextEditingController(text: g?.name);
    _subtype = TextEditingController(text: g?.subtype);
    _subtypeInput = TextEditingController(text: g?.subtype);
    _primaryColor = TextEditingController(text: g?.primaryColor);
    _additionalColors = [...?g?.additionalColors];
    _materials = [...?g?.materials];
    _fit = TextEditingController(text: g?.fit);
    _notes = TextEditingController(text: g?.notes);
    _category = g?.category;
    _thickness = g?.thickness;
    _seasons = [...?g?.seasons];
    _styles = [...?g?.styleTags];
    _existingPhoto =
        g != null &&
        (!_serverPhotos ||
            (widget.repository as ServerPhotoRepository).photoStatus(g).ready);
    _initialDraft = _draftSnapshot();
    for (final c in [
      _name,
      _subtype,
      _subtypeInput,
      _primaryColor,
      _fit,
      _notes,
    ]) {
      c.addListener(_draftChanged);
    }
  }

  @override
  void dispose() {
    _browserExit.dispose();
    _exitCoordinator?.unregister(this);
    if (_serverPhotos && _photo != null) MemoryImage(_photo!.bytes).evict();
    for (final c in [
      _name,
      _subtype,
      _subtypeInput,
      _primaryColor,
      _fit,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmClassificationChange(
    GarmentClassificationChange change, {
    required String title,
    required String target,
  }) async {
    if (!change.needsReset || (_persisted ?? widget.garment) == null) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(title),
            content: Text(
              '$target에 맞지 않거나 호환성을 확인하기 어려운 임시 입력을 비워요.\n'
              '${change.clearSubtype ? '• 세부 종류: “${_subtypeInput.text}” → 미선택\n' : ''}'
              '${change.clearFit ? '• 핏: “${_fit.text}” → 미선택\n' : ''}'
              '\n저장 전에는 원본 의류와 사진이 바뀌지 않아요. 분류를 되돌려도 비운 값은 자동 복원하지 않아요.',
            ),
            actions: [
              TextButton(
                key: const ValueKey('cancel-classification-change'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                key: const ValueKey('confirm-classification-change'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('초기화하고 변경'),
              ),
            ],
          ),
        ) ==
        true;
  }

  void _applyClassification(GarmentClassificationChange change) {
    _subtype.text = change.subtype;
    _subtypeInput.text = change.subtype;
    _fit.text = change.fit;
    _subtypeError = null;
    _classificationNotice = change.needsReset
        ? '${[if (change.clearSubtype) '세부 종류', if (change.clearFit) '핏'].join('·')}을 미선택으로 초기화했어요. 분류를 되돌려도 자동 복원하지 않아요. 이름·색상·계절 등 다른 입력과 사진은 유지돼요.'
        : null;
  }

  Future<void> _changeCategory(GarmentCategory? value) async {
    // The dropdown displays only the accepted category, never the proposal.
    if (value == null ||
        value == _category ||
        _changingClassification ||
        _busy ||
        _picking) {
      return;
    }
    setState(() => _changingClassification = true);
    try {
      final change = GarmentClassificationChange.category(
        target: value,
        subtype: _subtypeInput.text,
        fit: _fit.text,
      );
      if (!await _confirmClassificationChange(
            change,
            title: '카테고리를 변경할까요?',
            target: value.label,
          ) ||
          !mounted) {
        return;
      }
      setState(() {
        _category = value;
        _categoryField.currentState?.didChange(value);
        _applyClassification(change);
      });
    } finally {
      if (mounted) setState(() => _changingClassification = false);
    }
  }

  Future<bool> _changeSubtype(String value) async {
    if (_changingClassification || _busy || _picking) return false;
    final proposed = value.trim();
    if (proposed == _subtype.text.trim()) {
      setState(() {
        _subtypeInput.text = _subtype.text;
        _subtypeError = null;
      });
      return true;
    }
    if (subtypeBelongsToOtherCategory(_category, proposed)) {
      setState(
        () =>
            _subtypeError = '현재 카테고리의 종류를 선택하거나 직접 입력해 주세요. 다른 카테고리의 추천 종류예요.',
      );
      return false;
    }
    setState(() => _changingClassification = true);
    try {
      final change = GarmentClassificationChange.subtypeChange(
        category: _category,
        subtype: proposed,
        fit: _fit.text,
      );
      if (!await _confirmClassificationChange(
            change,
            title: '세부 종류를 변경할까요?',
            target: proposed.isEmpty ? '세부 종류 미선택' : proposed,
          ) ||
          !mounted) {
        if (mounted) setState(() => _subtypeInput.text = _subtype.text);
        return false;
      }
      setState(() => _applyClassification(change));
      return true;
    } finally {
      if (mounted) setState(() => _changingClassification = false);
    }
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await widget.photoService.pick();
      if (mounted && photo != null) {
        if (_serverPhotos && _photo != null) {
          await MemoryImage(_photo!.bytes).evict();
        }
        if (!mounted) return;
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
    if (_busy || _picking || _changingClassification) return;
    // Pending custom subtype text must be applied/reviewed before serializing.
    if (!await _changeSubtype(_subtypeInput.text) || !mounted) return;
    if (_busy || _picking || _changingClassification) return;
    final invalidFields = _form.currentState!.validateGranularly();
    final errors = invalidFields
        .map((field) => field.errorText)
        .whereType<String>()
        .toSet();
    if (invalidFields.isNotEmpty && errors.isEmpty) {
      errors.add('표시된 입력 오류를 확인해 주세요.');
    }
    if (!widget.metadataOnly && _photo == null && !_existingPhoto) {
      errors.add('이 기기 옷장에는 사진이 필요해요. 사진을 선택해 주세요.');
    }
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    _form.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = _persisted ?? widget.garment;
    final now = DateTime.now().toUtc();
    var garment = Garment(
      id: _draftId,
      name: _name.text.trim(),
      category: _category!,
      createdAt: _draftCreatedAt,
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
      imageWidth: widget.metadataOnly
          ? old?.imageWidth ?? 1
          : _photo?.width ?? old?.imageWidth ?? 1,
      imageHeight: widget.metadataOnly
          ? old?.imageHeight ?? 1
          : _photo?.height ?? old?.imageHeight ?? 1,
      imageMimeType: widget.metadataOnly
          ? old?.imageMimeType ?? 'image/jpeg'
          : _photo == null
          ? old?.imageMimeType ?? 'image/jpeg'
          : 'image/jpeg',
    );
    var metadataSaved = false;
    try {
      if (old != null &&
          _photo == null &&
          jsonEncode(old.toJson()) == jsonEncode(garment.toJson())) {
        if (mounted) _finishLeave(old);
        return;
      }
      if (needsFitReview(_category, _subtype.text, _fit.text)) {
        final keep = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('입력한 핏을 유지할까요?'),
            content: Text(
              '${_category!.label} · ${_subtype.text.trim().isEmpty ? '세부 종류 미선택' : _subtype.text.trim()}의 추천에 없는 핏 “${_fit.text.trim()}”이에요.\n직접 입력값으로 유지하거나, 돌아가서 변경·선택 해제할 수 있어요. 기존 저장 데이터는 자동으로 바꾸지 않아요.',
            ),
            actions: [
              TextButton(
                key: const ValueKey('review-fit'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('돌아가서 확인'),
              ),
              FilledButton(
                key: const ValueKey('keep-custom-fit'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('이 핏으로 저장'),
              ),
            ],
          ),
        );
        if (!mounted || keep != true) return;
      }
      garment = Garment.fromJson({
        ...garment.toJson(),
        'updatedAt': now.toIso8601String(),
      });
      final repository = widget.repository;
      if (repository is RevisionedWardrobeRepository) {
        garment = await repository.saveWithOriginal(garment, original: old);
        _persisted = garment;
        metadataSaved = true;
      } else {
        await repository.save(garment, imageBytes: _photo?.bytes);
      }
      if (repository is ServerPhotoRepository && _photo != null) {
        garment = await repository.uploadPhoto(
          garment,
          _photo!,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
        );
        _persisted = garment;
      }
      if (mounted) _finishLeave(garment);
    } catch (e) {
      if (_serverPhotos && _persisted != null) {
        try {
          _persisted = await (widget.repository as RevisionedWardrobeRepository)
              .refresh(_persisted!);
        } catch (_) {
          /* Keep original error and form; no overwrite. */
        }
      }
      if (mounted) {
        setState(
          () => _error = metadataSaved && _serverPhotos
              ? '의류 정보는 저장됐지만 사진 작업을 완료하지 못했어요.\n${wardrobeError(e)}'
              : wardrobeError(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _hasChanges;
    _browserExit.update(!_allowLeave && (dirty || _working));
    return PopScope<Garment>(
      canPop: _allowLeave || (!dirty && !_working),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context)
              ? BackButton(onPressed: _tryLeave)
              : null,
          title: Text(widget.garment == null ? '새로운 옷 등록' : '옷 정보 수정'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: AbsorbPointer(
                  absorbing: _busy || _picking || _changingClassification,
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.metadataOnly
                              ? _serverPhotos
                                    ? '서버 개발 옷장 · 사진은 선택 사항'
                                    : '서버 개발 옷장 · 의류 정보만 저장'
                              : '사진과 함께, 내 옷장에 한 벌 더.',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!widget.metadataOnly)
                          const Text(
                            '이 기기 옷장 · 사진 필수',
                            style: TextStyle(fontSize: 12),
                          ),
                        const Text('* 표시는 필수 항목이에요.'),
                        const SizedBox(height: 24),
                        if (widget.metadataOnly && !_serverPhotos)
                          const SurfaceCard(
                            child: Text(
                              '사진 없이 정보를 등록해요. 사진 선택·업로드·자동 이전은 하지 않아요. 기존 서버 사진과 사진 상태도 변경하지 않아요.',
                            ),
                          )
                        else
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
                                            garment:
                                                _persisted ?? widget.garment!,
                                            repository: widget.repository,
                                            fit: BoxFit.contain,
                                          )
                                        : Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .add_photo_alternate_outlined,
                                                  size: 56,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  _serverPhotos
                                                      ? '내 옷 사진 (선택)'
                                                      : '내 옷 사진 *',
                                                ),
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
                                    if (_photo != null ||
                                        (!widget.metadataOnly &&
                                            _existingPhoto))
                                      TextButton(
                                        onPressed: () {
                                          if (_serverPhotos && _photo != null) {
                                            MemoryImage(_photo!.bytes).evict();
                                          }
                                          setState(() {
                                            _photo = null;
                                            final saved =
                                                _persisted ?? widget.garment;
                                            _existingPhoto =
                                                _serverPhotos &&
                                                saved != null &&
                                                (widget.repository
                                                        as ServerPhotoRepository)
                                                    .photoStatus(saved)
                                                    .ready;
                                          });
                                        },
                                        child: Text(
                                          widget.metadataOnly
                                              ? '선택 취소'
                                              : '사진 삭제',
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _serverPhotos
                                      ? '사진은 선택 사항이에요. JPG · PNG · WebP / 선택 파일 최대 15MB\n최대 1,600px JPEG로 압축해 2MiB·400만 화소 이하로 업로드해요. 투명 배경은 흰색이 돼요.\n카드에는 서버 검증이 완료된 사진만 표시해요.'
                                      : 'JPG · PNG · WebP / 최대 15MB\n최대 1,600px로 줄여 JPEG로 저장해요. 투명 배경은 흰색으로 바뀌어요.',
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
                        KeyedSubtree(
                          key: const ValueKey('category-field'),
                          child: FormField<GarmentCategory>(
                            key: _categoryField,
                            initialValue: _category,
                            validator: (v) =>
                                v == null ? '카테고리를 선택해 주세요.' : null,
                            builder: (field) => InputDecorator(
                              decoration: InputDecoration(
                                labelText: '카테고리 *',
                                border: const OutlineInputBorder(),
                                errorText: field.errorText,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<GarmentCategory>(
                                  value: _category,
                                  isExpanded: true,
                                  items: GarmentCategory.values
                                      .map(
                                        (v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(v.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _changeCategory,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_classificationNotice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _classificationNotice!,
                              key: const ValueKey(
                                'classification-change-notice',
                              ),
                            ),
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
                              Text(
                                (_persisted ?? widget.garment) == null
                                    ? '카테고리·종류를 바꾸면 맞지 않는 임시 종류·핏은 초기화해요.'
                                    : '카테고리·종류를 바꾸면 맞지 않는 임시 종류·핏을 확인 후 초기화해요. 저장 전 원본은 유지돼요.',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              SuggestedTextField(
                                controller: _subtypeInput,
                                selectedValue: _subtype.text,
                                errorText: _subtypeError,
                                label: '세부 종류 직접 입력',
                                suggestions:
                                    subtypeSuggestions[_category] ?? [],
                                onChanged: () =>
                                    setState(() => _subtypeError = null),
                                onApply: () =>
                                    _changeSubtype(_subtypeInput.text),
                                onSuggestionSelected: _changeSubtype,
                              ),
                              if (subtypeBelongsToOtherCategory(
                                _category,
                                _subtype.text,
                              ))
                                const Text(
                                  '다른 카테고리의 추천 종류가 입력되어 있어요. 값을 유지했으니 현재 카테고리에 맞는지 확인해 주세요.',
                                  key: ValueKey('subtype-review-notice'),
                                  style: TextStyle(fontSize: 12),
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
                                onToggle: (v) => _setPrimary(
                                  _primaryColor.text == v ? '' : v,
                                ),
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
                                onPendingChanged: (v) =>
                                    setState(() => _pendingAdditional = v),
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          '계절',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          '선택 사항 · 주로 사용하는 계절을 여러 개 골라 주세요.',
                          style: TextStyle(fontSize: 12),
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
                            category: _category,
                            onChanged: (v) => setState(() => _thickness = v),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '스타일 태그',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          '선택 사항 · 이 아이템의 분위기에 맞게 골라 주세요.',
                          style: TextStyle(fontSize: 12),
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
                                    selected
                                        ? _styles.add(v)
                                        : _styles.remove(v);
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
                            onPendingChanged: (v) =>
                                setState(() => _pendingMaterial = v),
                          ),
                        ),
                        GarmentInputSection(
                          id: 'fit',
                          title: '핏',
                          summary: _fit.text.isEmpty
                              ? fitsForCategory(
                                      _category,
                                      subtype: _subtype.text,
                                    ).isEmpty
                                    ? '선택 사항 · 이 카테고리는 핏 추천을 생략해요'
                                    : '선택 사항 · 실루엣을 보고 선택하거나 직접 입력'
                              : needsFitReview(
                                  _category,
                                  _subtype.text,
                                  _fit.text,
                                )
                              ? '${_fit.text} · 현재 분류와 맞는지 확인해 주세요'
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
                        if (_progress != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_progress!),
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
  }

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
